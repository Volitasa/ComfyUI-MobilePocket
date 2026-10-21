import 'dart:async';
import 'dart:convert';

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
    ref.onDispose(_cancelReconnect);
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
      final channel = WebSocketChannel.connect(Uri.parse(wsUrl));

      channel.stream.listen(
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
          _resetChannel();
          _scheduleReconnect();
        },
        onError: (error) {
          _resetChannel();
          _scheduleReconnect();
        },
      );

      // stream 订阅成功后标记已连接
      _channel = channel;
      _lastMessageAt = DateTime.now();
      _resetReconnectAttempts();
      state = WsState(isConnected: true);
    } catch (e) {
      state = WsState(isConnected: false);
    }
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
    _channel?.sink.close();
    _channel = null;
    _lastMessageAt = null;
    _resetReconnectAttempts();
    state = WsState(isConnected: false);
  }
}

final wsProvider = NotifierProvider<WsNotifier, WsState>(() {
  return WsNotifier();
});
