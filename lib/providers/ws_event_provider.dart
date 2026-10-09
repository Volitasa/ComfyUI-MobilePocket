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
    return WsState();
  }

  void connect() {
    if (_channel != null && state.isConnected) return;

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
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      state = WsState(isConnected: true);

      _channel!.stream.listen(
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
          state = WsState(isConnected: false);
          _channel = null;
        },
        onError: (error) {
          state = WsState(isConnected: false);
          _channel = null;
        },
      );
    } catch (e) {
      state = WsState(isConnected: false);
    }
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