import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'connection_provider.dart';
import 'task_manager.dart';

class WsState {
  final bool isConnected;
  WsState({this.isConnected = false});
}

class WsNotifier extends Notifier<WsState> {
  WebSocketChannel? _channel;

  /// 当前连接的消息订阅。
  ///
  /// ⚠️ 必须存下来并在断开时取消。旧 socket 的断线回调是**迟到**的：
  /// 半开连接上要等 TCP 超时才到，可达分钟级。它一到就把 `_channel` 清空，
  /// 而那时 `_channel` 早就换成新连接了 —— 等于把刚连上的那条抹掉，
  /// 紧接着又排一次重连。于是每重建一次就多一条连不上的幽灵连接，
  /// 每条消息也被重复处理一遍。
  /// 取消订阅是源头解法：cancel 之后流不会再回调 onDone。
  StreamSubscription<dynamic>? _subscription;

  /// 连接代次，每次新建连接递增。
  ///
  /// 迟到的断线/错误回调拿它跟当前代次比对，对不上就说明自己已经过期，
  /// 直接忽略。这是取消订阅之外的第二道保险。
  int _generation = 0;

  /// 最后一次收到服务端消息的时间。
  ///
  /// 用于识别「半开连接」：App 进后台后系统可能让 socket 静默失效——
  /// 既不触发 onDone/onError（所以不会自动重连），也收不到任何数据。
  /// 这种连接看上去还活着，实际已经死了。
  DateTime? _lastMessageAt;

  /// 超过这个时间没收到任何消息就认为连接已失效。
  /// 只在「回到前台且有未终结任务」时判定，避免空闲状态下无谓重连。
  static const Duration _staleAfter = Duration(seconds: 45);

  /// 自动重连的次数上限。
  ///
  /// 服务器关着时无限重试既连不上又白耗电，还会在后台一直撞墙；
  /// 试满就停，等用户主动操作（切服务器、重新测试连接、回到前台）再给机会。
  static const int _maxReconnectAttempts = 3;

  /// 重连基础间隔，逐次翻倍：3s → 6s → 12s。
  static const Duration _reconnectBaseDelay = Duration(seconds: 3);

  int _reconnectAttempts = 0;
  Timer? _reconnectTimer;

  @override
  WsState build() {
    ref.onDispose(() {
      _cancelReconnect();
      _subscription?.cancel();
      _subscription = null;
    });
    // 注意：不在 build() 里用 ref.listen 做跨 provider 副作用监听
    // （这是 Riverpod 反模式，且会触发 Flutter 3.47 的 InheritedElement
    //  deactivate 断言）。连接触发由 UI 层（home_view）在连接状态变化时
    //  显式调用 connect()/disconnect()。
    return WsState();
  }

  void connect() {
    if (_channel != null) return;

    final config = ref.read(connectionProvider);
    if (!config.isConnected) return;

    String wsUrl;
    if (config.comfyUrl.startsWith('https')) {
      wsUrl = config.comfyUrl.replaceFirst('https://', 'wss://');
    } else {
      wsUrl = config.comfyUrl.replaceFirst('http://', 'ws://');
    }
    wsUrl = '$wsUrl/ws?clientId=${config.clientId}';

    try {
      _attach(WebSocketChannel.connect(Uri.parse(wsUrl)));
    } catch (e) {
      state = WsState(isConnected: false);
    }
  }

  /// 接上一条连接：登记订阅、记下代次、标记已连接。
  ///
  /// 与 [connect] 分开，是为了让测试能用假连接走**完全相同**的一条路径。
  /// 幽灵连接是「旧连接的断线信号迟到，把新连接抹掉」造成的：半开连接上
  /// 这个信号会晚几十秒才到，真起一台 WebSocket 服务器根本造不出这种时序。
  @visibleForTesting
  void attachForTest(WebSocketChannel channel) => _attach(channel);

  void _attach(WebSocketChannel channel) {
    // 这一轮连接的代号：只有代号仍等于当前代次的回调才是「现在这条连接」的，
    // 迟到的旧回调（半开连接上会晚很久）一律忽略，不许它动 _channel。
    final generation = ++_generation;
    _subscription = channel.stream.listen(
      (message) {
        if (message is String) {
          _lastMessageAt = DateTime.now();
          try {
            final msg = jsonDecode(message);
            // 将消息派发给任务管理器更新 UI
            ref.read(taskManagerProvider.notifier).updateTaskFromWs(msg);
          } catch (e) {
            // json parse error
          }
        }
      },
      onDone: () {
        if (generation != _generation) return;
        _resetChannel();
        _scheduleReconnect();
      },
      onError: (error) {
        if (generation != _generation) return;
        _resetChannel();
        _scheduleReconnect();
      },
    );

    // stream 订阅成功后标记已连接
    _channel = channel;
    _lastMessageAt = DateTime.now();
    _resetReconnectAttempts();
    state = WsState(isConnected: true);
  }

  void _resetChannel() {
    _channel = null;
    state = WsState(isConnected: false);
  }

  void _cancelReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }

  /// 一轮连接生命周期结束（连上了 / 主动断开）时清零，下次再断重新给满次数。
  void _resetReconnectAttempts() {
    _cancelReconnect();
    _reconnectAttempts = 0;
  }

  void _scheduleReconnect() {
    // 断线后若连接配置仍有效，自动重连，避免进度更新长期中断
    if (!ref.read(connectionProvider).isConnected) return;
    // 已在等待重连就不重复排：onDone 与 onError 可能都触发，
    // 叠加会让重连次数被快速耗尽
    if (_reconnectTimer != null) return;
    if (_reconnectAttempts >= _maxReconnectAttempts) return;

    final delay = _reconnectBaseDelay * (1 << _reconnectAttempts);
    _reconnectAttempts++;
    _reconnectTimer = Timer(delay, () {
      _reconnectTimer = null;
      if (_channel == null && ref.read(connectionProvider).isConnected) {
        connect();
      }
    });
  }

  /// 供页面回到前台时调用：连接已失效就重建。
  ///
  /// 后台期间 socket 可能被系统静默掐断（半开连接），此时不会触发
  /// onDone/onError，`_channel` 也还在，常规重连逻辑永远等不到信号，
  /// 表现为「回到 App 后进度不动，必须手动刷新」。这里主动重建。
  void ensureAlive() {
    if (!ref.read(connectionProvider).isConnected) return;
    final last = _lastMessageAt;
    final dead =
        _channel == null ||
        last == null ||
        DateTime.now().difference(last) > _staleAfter;
    if (!dead) return;
    disconnect();
    connect();
  }

  void disconnect() {
    final subscription = _subscription;
    final channel = _channel;
    _subscription = null;
    _channel = null;
    _lastMessageAt = null;
    _resetReconnectAttempts();
    state = WsState(isConnected: false);

    // 先掐断回调来源：取消订阅后旧 socket 的 onDone **不会**再被回调，
    // 也就无从在几十秒后把新连接抹掉。
    // IOWebSocketChannel 的订阅被取消时会连带关掉底层 socket，
    // 所以下面这个 close 只是兜底；已经关掉的会抛，吞掉即可。
    subscription?.cancel();
    try {
      channel?.sink.close();
    } catch (_) {
      // 已被订阅取消时关掉了
    }
  }
}

final wsProvider = NotifierProvider<WsNotifier, WsState>(() {
  return WsNotifier();
});
