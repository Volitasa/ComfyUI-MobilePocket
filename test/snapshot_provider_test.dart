import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:comfyui_mobilepocket/models/task_history.dart';
import 'package:comfyui_mobilepocket/models/workflow_node.dart';
import 'package:comfyui_mobilepocket/providers/connection_provider.dart';
import 'package:comfyui_mobilepocket/providers/snapshot_provider.dart';

Map<String, dynamic> _workflow([String text = 'a cat']) => {
      '1': {
        'inputs': {'text': text, 'seed': 123},
        'class_type': 'CLIPTextEncode',
      },
    };

WorkflowNode _node({bool exposed = true}) => WorkflowNode(
      id: '1',
      classType: 'CLIPTextEncode',
      key: 'text',
      alias: '提示词',
      exposed: exposed,
      title: 'CLIP 文本编码',
      paramType: ParamType.text,
      value: 'a cat',
    );

void main() {
  group('快照 provider', () {
    test('upsert 新建快照，id 由工作流内容决定', () async {
      final prefs = await _prefsWith();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);

      final id = container.read(snapshotProvider.notifier).upsert(
            workflowJson: _workflow(),
            mappingConfig: [_node()],
            sourceName: '基础文生图',
            serverId: 'srv-1',
          );

      expect(id, startsWith('snap_'));
      final list = container.read(snapshotProvider);
      expect(list.length, 1);
      expect(list.first.sourceName, '基础文生图');
      expect(list.first.serverId, 'srv-1');
      expect(list.first.mappingConfig.length, 1);
    });

    test('内容不变则复用同一份快照，且沿用原创建时间', () async {
      final prefs = await _prefsWith();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);

      final notifier = container.read(snapshotProvider.notifier);
      final firstId = notifier.upsert(
        workflowJson: _workflow(),
        mappingConfig: [_node()],
        sourceName: '基础文生图',
      );
      final firstCreatedAt = notifier.byId(firstId)!.createdAt;

      await Future<void>.delayed(const Duration(milliseconds: 5));

      // 同一个工作流再跑一次（参数值不同不影响快照身份）
      final secondId = notifier.upsert(
        workflowJson: _workflow(),
        mappingConfig: [_node(exposed: false)],
        sourceName: '基础文生图',
      );

      expect(secondId, firstId, reason: '内容未变必须复用，否则旧记录会引用失效');
      expect(container.read(snapshotProvider).length, 1);
      expect(notifier.byId(secondId)!.createdAt, firstCreatedAt);
    });

    test('工作流内容变了则新建快照', () async {
      final prefs = await _prefsWith();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);

      final notifier = container.read(snapshotProvider.notifier);
      final idA = notifier.upsert(
        workflowJson: _workflow('a cat'),
        mappingConfig: [_node()],
        sourceName: '基础文生图',
      );
      final idB = notifier.upsert(
        workflowJson: _workflow('a dog'),
        mappingConfig: [_node()],
        sourceName: '基础文生图',
      );

      expect(idB, isNot(idA));
      expect(container.read(snapshotProvider).length, 2);
    });

    test('改暴露配置不改变快照 id（否则已存在的记录会失效）', () async {
      final prefs = await _prefsWith();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);

      final notifier = container.read(snapshotProvider.notifier);
      final id = notifier.upsert(
        workflowJson: _workflow(),
        mappingConfig: [_node(exposed: false)],
        sourceName: '基础文生图',
      );

      notifier.updateMappingConfig(id, [_node(exposed: true)]);

      final updated = notifier.byId(id);
      expect(updated, isNotNull);
      expect(updated!.mappingConfig.first.exposed, true);
      expect(container.read(snapshotProvider).length, 1);
    });

    test('删除快照后可重新固化；持久化能从 prefs 读回', () async {
      final prefs = await _prefsWith();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);

      final notifier = container.read(snapshotProvider.notifier);
      final id = notifier.upsert(
        workflowJson: _workflow(),
        mappingConfig: [_node()],
        sourceName: '基础文生图',
      );
      expect(prefs.getString(snapshotsPrefsKey), isNotNull);

      notifier.remove(id);
      expect(notifier.byId(id), isNull);

      // 新容器 = 模拟重启 App：应从 prefs 反序列化出快照列表
      final reloaded = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(reloaded.dispose);
      expect(reloaded.read(snapshotProvider), isEmpty);
    });
  });

  group('TaskHistory 快照字段', () {
    test('新增字段序列化往返一致', () {
      final task = TaskHistory(
        promptId: 'p1',
        workflowId: '基础文生图_api.json',
        title: '基础文生图',
        serverId: 'srv-1',
        snapshotId: 'snap_abc',
        params: {'1:text': 'a cat', '1:seed': 123},
      );

      final restored = TaskHistory.fromJson(task.toJson());

      expect(restored.snapshotId, 'snap_abc');
      expect(restored.params, {'1:text': 'a cat', '1:seed': 123});
      expect(restored.serverId, 'srv-1');
    });

    test('旧数据（无快照字段）反序列化为 null，不报错', () {
      final legacy = {
        'promptId': 'p0',
        'workflowId': 'ComfyUI_01010__api.json',
        'title': 'ComfyUI_01010_',
        'status': '已完成',
        'progressValue': 1,
        'progressMax': 1,
        'nodeInfo': '',
        'images': [],
        'timestamp': 1700000000000,
        'serverId': 'srv-0',
      };

      final task = TaskHistory.fromJson(jsonDecode(jsonEncode(legacy)));

      expect(task.snapshotId, isNull);
      expect(task.params, isNull);
    });
  });
}

Future<SharedPreferences> _prefsWith() async {
  SharedPreferences.setMockInitialValues({});
  return SharedPreferences.getInstance();
}
