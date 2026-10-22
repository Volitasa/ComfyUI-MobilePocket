import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:comfyui_mobilepocket/providers/connection_provider.dart';
import 'package:comfyui_mobilepocket/providers/ws_event_provider.dart';

/// 假的下行通道：只记下被关了几次。
class _FakeSink implements WebSocketSink {
  int closeCalls = 0;

  @override
  Future<void> get done => Completer<void>().future;

  @override
  void add(dynamic data) {}

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<dynamic> stream) => Future<void>.value();

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {
    closeCalls++;
  }
}

/// 一条假连接：断线信号可以在想要的时刻才抛出来。
///
/// 幽灵连接的前提是「旧连接的断线信号来得比新连接还晚」—— 半开连接上
/// 这个信号会晚几十秒才到。真起一台 WebSocket 服务器，关闭握手几毫秒就完成了，
/// 根本造不出这种时序，所以这里自己造连接。
class _FakeChannel extends StreamChannelMixin<dynamic>
    implements WebSocketChannel {
  final _controller = StreamController<dynamic>();
  final _FakeSink _sink = _FakeSink();

  @override
  Stream<dynamic> get stream => _controller.stream;

  @override
  WebSocketSink get sink => _sink;

  @override
  Future<void> get ready => Future<void>.value();

  @override
  int? get closeCode => null;

  @override
  String? get closeReason => null;

  @override
  String? get protocol => null;

  int get closeCalls => _sink.closeCalls;

  /// 服务端把这条连接关掉
  void simulateRemoteClose() => _controller.close();
}

/// 指向一个必然连不上的地址：真有幽灵连接去连它，只会立刻失败。
class _UnreachableServer extends ConnectionNotifier {
  @override
  ConfigState build() => ConfigState(
    servers: [
      ServerConfig(id: 'srv', name: '', primaryUrl: 'http://127.0.0.1:1'),
    ],
    activeServerId: 'srv',
    comfyUrl: 'http://127.0.0.1:1',
    isConnected: true,
    clientId: 'test-client',
  );
}

Future<ProviderContainer> _container() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      connectionProvider.overrideWith(() => _UnreachableServer()),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('WebSocket 重建连接', () {
    test('旧连接迟到的断线信号不会把新连接抹掉', () async {
      final container = await _container();
      final ws = container.read(wsProvider.notifier);

      // 回到前台的重建就是这个顺序：先断开旧的，再连上新的
      final first = _FakeChannel();
      ws.attachForTest(first);
      ws.disconnect();

      final second = _FakeChannel();
      ws.attachForTest(second);
      expect(container.read(wsProvider).isConnected, isTrue);

      // 旧连接的断线信号现在才到
      first.simulateRemoteClose();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // 修复前：这一下会清空 _channel（那会儿它已经是新连接了），
      // 状态当场掉回未连接，接着又排一次重连
      expect(container.read(wsProvider).isConnected, isTrue);
      expect(second.closeCalls, 0, reason: '新连接不该被旧连接的回调牵连');
    });

    test('迟到的信号不会牵出一条连不上的幽灵连接', () async {
      final container = await _container();
      final ws = container.read(wsProvider.notifier);

      final first = _FakeChannel();
      ws.attachForTest(first);
      ws.disconnect();
      ws.attachForTest(_FakeChannel());

      first.simulateRemoteClose();
      // 等过重连间隔：真有幽灵连接的话，它这会儿已经去连 127.0.0.1:1 并失败了
      await Future<void>.delayed(const Duration(seconds: 4));

      expect(
        container.read(wsProvider).isConnected,
        isTrue,
        reason: '每重建一次就多一条的话，来回切几次前台状态就不对了',
      );
    });

    test('当前连接真的断了，状态还是会如实掉回未连接', () async {
      final container = await _container();
      final ws = container.read(wsProvider.notifier);

      final only = _FakeChannel();
      ws.attachForTest(only);
      expect(container.read(wsProvider).isConnected, isTrue);

      only.simulateRemoteClose();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // 挡掉过期回调的同时，不能把真断线也一起吞了
      expect(container.read(wsProvider).isConnected, isFalse);
    });
  });
}
