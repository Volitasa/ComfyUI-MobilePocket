import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:comfyui_mobilepocket/providers/object_info_provider.dart';
import 'package:comfyui_mobilepocket/services/object_info_service.dart';

/// 装一个假客户端，并记录每个请求
class _Recorder {
  final List<String> paths = [];
  int inflight = 0;
  int maxInflight = 0;

  void _enter() {
    inflight++;
    if (inflight > maxInflight) maxInflight = inflight;
  }

  void _leave() => inflight--;

  void install(Future<http.Response> Function(http.Request req) handler) {
    final previous = ObjectInfoService.instance.client;
    ObjectInfoService.instance.client = MockClient((req) async {
      paths.add(req.url.path);
      _enter();
      try {
        return await handler(req);
      } finally {
        _leave();
      }
    });
    addTearDown(() => ObjectInfoService.instance.client = previous);
  }
}

/// 形态 A 的 COMBO 响应：选项列表在数组第 0 位
String _ckptBody(List<String> options) =>
    '{"CheckpointLoaderSimple":{"input":{"required":'
    '{"ckpt_name":[[${options.map((o) => '"$o"').join(',')}], {}]}}}}';

void main() {
  late ProviderContainer container;
  late ObjectInfoNotifier notifier;

  setUp(() {
    container = ProviderContainer();
    addTearDown(container.dispose);
    notifier = container.read(objectInfoProvider.notifier);
  });

  group('缓存', () {
    test('首次加载写入缓存，能取到定义', () async {
      final rec = _Recorder()
        ..install(
          (_) async => http.Response(_ckptBody(['a.safetensors']), 200),
        );

      final ok = await notifier.ensureLoaded(
        serverId: 'srv_1',
        baseUrl: 'http://1.2.3.4:8190',
        classTypes: ['CheckpointLoaderSimple'],
      );

      expect(ok, isTrue);
      expect(rec.paths, ['/object_info/CheckpointLoaderSimple']);
      final state = container.read(objectInfoProvider);
      expect(state.hasNode('srv_1', 'CheckpointLoaderSimple'), isTrue);
      expect(
        state.specFor('srv_1', 'CheckpointLoaderSimple', 'ckpt_name')!.options,
        ['a.safetensors'],
      );
    });

    test('已经问过就不再发第二次请求', () async {
      final rec = _Recorder()
        ..install((_) async => http.Response(_ckptBody(['a']), 200));

      await notifier.ensureLoaded(
        serverId: 'srv_1',
        baseUrl: 'http://1.2.3.4:8190',
        classTypes: ['CheckpointLoaderSimple'],
      );
      await notifier.ensureLoaded(
        serverId: 'srv_1',
        baseUrl: 'http://1.2.3.4:8190',
        classTypes: ['CheckpointLoaderSimple'],
      );

      expect(rec.paths.length, 1);
    });

    test('换一台服务器要重新问，不复用上一台的缓存', () async {
      final rec = _Recorder()
        ..install((_) async => http.Response(_ckptBody(['a']), 200));

      await notifier.ensureLoaded(
        serverId: 'srv_1',
        baseUrl: 'http://1.2.3.4:8190',
        classTypes: ['CheckpointLoaderSimple'],
      );
      await notifier.ensureLoaded(
        serverId: 'srv_2',
        baseUrl: 'http://5.6.7.8:8190',
        classTypes: ['CheckpointLoaderSimple'],
      );

      expect(rec.paths.length, 2);
      final state = container.read(objectInfoProvider);
      expect(state.hasNode('srv_1', 'CheckpointLoaderSimple'), isTrue);
      expect(state.hasNode('srv_2', 'CheckpointLoaderSimple'), isTrue);
    });

    test('并发时同一节点只问一次', () async {
      final rec = _Recorder()
        ..install((_) async {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          return http.Response(_ckptBody(['a']), 200);
        });

      await Future.wait([
        notifier.ensureLoaded(
          serverId: 'srv_1',
          baseUrl: 'http://1.2.3.4:8190',
          classTypes: ['CheckpointLoaderSimple'],
        ),
        notifier.ensureLoaded(
          serverId: 'srv_1',
          baseUrl: 'http://1.2.3.4:8190',
          classTypes: ['CheckpointLoaderSimple'],
        ),
      ]);

      expect(rec.paths.length, 1);
    });
  });

  group('并发上限', () {
    test('一堆节点也不会一次全打出去（上限 4）', () async {
      final rec = _Recorder()
        ..install((_) async {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          return http.Response(_ckptBody(['a']), 200);
        });

      await notifier.ensureLoaded(
        serverId: 'srv_1',
        baseUrl: 'http://1.2.3.4:8190',
        classTypes: ['C1', 'C2', 'C3', 'C4', 'C5', 'C6', 'C7'],
      );

      expect(rec.paths.length, 7);
      expect(rec.maxInflight, 4);
    });
  });

  group('拿不到时静默', () {
    test('请求抛异常 → 不抛出、不写入可用数据，且记为「没取到」以便下次重试', () async {
      final rec = _Recorder()..install((_) async => throw Exception('timeout'));

      final ok = await notifier.ensureLoaded(
        serverId: 'srv_1',
        baseUrl: 'http://1.2.3.4:8190',
        classTypes: ['CheckpointLoaderSimple'],
      );

      expect(ok, isFalse);
      expect(rec.paths.length, 1);
      final state = container.read(objectInfoProvider);
      // 失败**不算答案**：specFor 仍是 null，界面退回原样
      expect(
        state.statusFor('srv_1', 'CheckpointLoaderSimple'),
        ObjectInfoFetchStatus.failure,
      );
      expect(
        state.specFor('srv_1', 'CheckpointLoaderSimple', 'ckpt_name'),
        isNull,
      );

      // 关键：网络恢复后再来一次必须**重试**。
      // 早先的实现把 failure 也算「问过」→ 一次断网就让配置页在整个会话里
      // 一直显示「未获取到服务器节点信息」，用户只能重启 App 才能恢复。
      ObjectInfoService.instance.client = MockClient(
        (_) async => http.Response(_ckptBody(['a']), 200),
      );
      await notifier.ensureLoaded(
        serverId: 'srv_1',
        baseUrl: 'http://1.2.3.4:8190',
        classTypes: ['CheckpointLoaderSimple'],
      );
      expect(
        container
            .read(objectInfoProvider)
            .specFor('srv_1', 'CheckpointLoaderSimple', 'ckpt_name')!
            .options,
        ['a'],
      );
    });

    test('非 200 响应 → 同样静默', () async {
      _Recorder().install((_) async => http.Response('nope', 500));

      final ok = await notifier.ensureLoaded(
        serverId: 'srv_1',
        baseUrl: 'http://1.2.3.4:8190',
        classTypes: ['CheckpointLoaderSimple'],
      );

      expect(ok, isFalse);
    });

    test('服务器不认识这个节点 → 问到了但没内容，不算「没有这个模型」', () async {
      _Recorder().install((_) async => http.Response('{}', 200));

      final ok = await notifier.ensureLoaded(
        serverId: 'srv_1',
        baseUrl: 'http://1.2.3.4:8190',
        classTypes: ['SomeCustomNode'],
      );

      expect(ok, isFalse);
      expect(
        container
            .read(objectInfoProvider)
            .specFor('srv_1', 'SomeCustomNode', 'model_name'),
        isNull,
      );
    });

    test('没连服务器时（serverId 为空）不请求', () async {
      final rec = _Recorder()
        ..install((_) async => http.Response(_ckptBody(['a']), 200));

      await notifier.ensureLoaded(
        serverId: '',
        baseUrl: '',
        classTypes: ['CheckpointLoaderSimple'],
      );

      expect(rec.paths, isEmpty);
    });
  });

  group('刷新与清理', () {
    test('refreshInPlace 能把上次失败的条目覆盖成可用数据', () async {
      // 配置页第一次断网 → 缓存里是 failure；刷新回来后必须换成真定义，
      // 否则「缺节点」检查会永远拿不到 spec。
      final rec = _Recorder()..install((_) async => throw Exception('boom'));

      await notifier.ensureLoaded(
        serverId: 'srv_1',
        baseUrl: 'http://1.2.3.4:8190',
        classTypes: ['CheckpointLoaderSimple'],
      );
      expect(
        container
            .read(objectInfoProvider)
            .statusFor('srv_1', 'CheckpointLoaderSimple'),
        ObjectInfoFetchStatus.failure,
      );
      final before = rec.paths.length;

      // 仍然走 rec，才能数到这次请求
      rec.install((_) async => http.Response(_ckptBody(['a', 'b']), 200));
      final ok = await notifier.refreshInPlace(
        serverId: 'srv_1',
        baseUrl: 'http://1.2.3.4:8190',
        classTypes: ['CheckpointLoaderSimple'],
      );

      expect(ok, isTrue);
      expect(rec.paths.length, before + 1);
      final state = container.read(objectInfoProvider);
      expect(
        state.statusFor('srv_1', 'CheckpointLoaderSimple'),
        ObjectInfoFetchStatus.ok,
      );
      expect(
        state.specFor('srv_1', 'CheckpointLoaderSimple', 'ckpt_name')!.options,
        ['a', 'b'],
      );
    });

    test('refreshInPlace 会重取已缓存过的节点（写入式，不是补缺式）', () async {
      var first = true;
      final rec = _Recorder()
        ..install((_) async {
          final body = first ? _ckptBody(['a']) : _ckptBody(['a', 'b']);
          first = false;
          return http.Response(body, 200);
        });

      await notifier.ensureLoaded(
        serverId: 'srv_1',
        baseUrl: 'http://1.2.3.4:8190',
        classTypes: ['CheckpointLoaderSimple'],
      );
      await notifier.refreshInPlace(
        serverId: 'srv_1',
        baseUrl: 'http://1.2.3.4:8190',
        classTypes: ['CheckpointLoaderSimple'],
      );

      expect(rec.paths.length, 2);
      expect(
        container
            .read(objectInfoProvider)
            .specFor('srv_1', 'CheckpointLoaderSimple', 'ckpt_name')!
            .options,
        ['a', 'b'],
      );
    });

    test('删除服务器连接时清掉它的缓存', () async {
      _Recorder().install((_) async => http.Response(_ckptBody(['a']), 200));

      await notifier.ensureLoaded(
        serverId: 'srv_1',
        baseUrl: 'http://1.2.3.4:8190',
        classTypes: ['CheckpointLoaderSimple'],
      );
      notifier.clearServer('srv_1');

      expect(
        container
            .read(objectInfoProvider)
            .hasNode('srv_1', 'CheckpointLoaderSimple'),
        isFalse,
      );
    });
  });
}
