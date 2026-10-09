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

  @override
  WsState build() {
    // 监听连接状态：连接成功后自动建立 WS，断开时关闭，保证单点维护连接生命周期
    ref.listen(connectionProvider, (prev, next) {
      if (next.isConnected && !(prev?.isConnected ?? false)) {
        connect();
      } else if (!next.isConnected && (prev?.isConnected ?? false)) {
        disconnect();
      }
    });
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
      state = WsState(isConnected: true);
    } catch (e) {
      state = WsState(isConnected: false);
    }
  }

  void _resetChannel() {
    _channel = null;
    state = WsState(isConnected: false);
  }

  void _scheduleReconnect() {
    // 断线后若连接配置仍有效，自动重连，避免进度更新长期中断
    if (!ref.read(connectionProvider).isConnected) return;
    Future.delayed(const Duration(seconds: 3), () {
      if (_channel == null && ref.read(connectionProvider).isConnected) {
        connect();
      }
    });
  }

  void disconnect() {
    _channel?.sink.close();
    _channel = null;
    state = WsState(isConnected: false);
  }
}

final wsProvider = NotifierProvider<WsNotifier, WsState>(() {
  return WsNotifier();
});
