import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:comfyui_mobilepocket/models/local_workflow.dart';
import 'package:comfyui_mobilepocket/models/workflow_node.dart';
import 'package:comfyui_mobilepocket/providers/connection_provider.dart';
import 'package:comfyui_mobilepocket/providers/local_workflow_provider.dart';
import 'package:comfyui_mobilepocket/providers/workflow_provider.dart';
import 'package:comfyui_mobilepocket/utils.dart';

Map<String, dynamic> _workflow([String text = 'a cat']) => {
  '1': {
    'inputs': {'text': text, 'seed': 123},
    'class_type': 'CLIPTextEncode',
  },
};

WorkflowNode _node() => WorkflowNode(
  id: '1',
  classType: 'CLIPTextEncode',
  key: 'text',
  alias: '提示词',
  exposed: true,
  title: 'CLIP 文本编码',
  paramType: ParamType.text,
  value: 'a cat',
);

Future<SharedPreferences> _prefsWith([Map<String, Object>? values]) async {
  SharedPreferences.setMockInitialValues(values ?? {});
  return SharedPreferences.getInstance();
}

ProviderContainer _container(SharedPreferences prefs) => ProviderContainer(
  overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
);

void main() {
  group('本地工作流库', () {
    test('保存后写入 prefs，重建 provider 依然读得到（不再是一次性会话）', () async {
      final prefs = await _prefsWith();
      final container = _container(prefs);
      addTearDown(container.dispose);

      container
          .read(localWorkflowProvider.notifier)
          .save(
            name: '我的写真',
            workflowJson: _workflow(),
            sourceKind: LocalWorkflowSource.importFile,
            originName: 'portrait_api.json',
          );

      // 模拟重启：用同一个 prefs 建一个新容器
      final restarted = _container(prefs);
      addTearDown(restarted.dispose);
      final list = restarted.read(localWorkflowProvider);

      expect(list.length, 1);
      expect(list.first.name, '我的写真');
      expect(list.first.sourceKind, LocalWorkflowSource.importFile);
      expect(list.first.workflowJson['1']['inputs']['text'], 'a cat');
    });

    test('指定 id 时沿用该 id，已有的 mapping_local_ 配置可直接复用', () async {
      final prefs = await _prefsWith();
      final container = _container(prefs);
      addTearDown(container.dispose);

      // 旧版本遗留：配置已按 local_abc 存好
      await container.read(workflowProvider.notifier).saveMappingConfig(
        'local_abc',
        [_node()],
      );

      final id = container
          .read(localWorkflowProvider.notifier)
          .save(
            name: '导入的工作流',
            workflowJson: _workflow(),
            sourceKind: LocalWorkflowSource.importFile,
            id: 'local_abc',
          );

      expect(id, 'local_abc');
      expect(
        container.read(workflowProvider.notifier).hasMappingConfig(id),
        isTrue,
      );
    });

    test('重名自动追加序号；覆盖同一 id 时不给自己加序号', () async {
      final prefs = await _prefsWith();
      final container = _container(prefs);
      addTearDown(container.dispose);
      final notifier = container.read(localWorkflowProvider.notifier);

      final firstId = notifier.save(
        name: '产品图',
        workflowJson: _workflow('v1'),
        sourceKind: LocalWorkflowSource.importFile,
      );
      expect(notifier.byId(firstId)?.name, '产品图');

      // 用同一 id 再存一次（重复导入同一文件）：不该给自己加序号
      notifier.save(
        name: '产品图',
        workflowJson: _workflow('v2'),
        sourceKind: LocalWorkflowSource.importFile,
        id: firstId,
      );
      expect(notifier.byId(firstId)?.name, '产品图');

      // 另一条同名条目才需要追加序号
      final secondId = notifier.save(
        name: '产品图',
        workflowJson: _workflow('v3'),
        sourceKind: LocalWorkflowSource.importFile,
      );
      expect(notifier.byId(secondId)?.name, '产品图 (2)');
    });

    test('重命名生效并持久化', () async {
      final prefs = await _prefsWith();
      final container = _container(prefs);
      addTearDown(container.dispose);
      final notifier = container.read(localWorkflowProvider.notifier);

      final id = notifier.save(
        name: '旧名字',
        workflowJson: _workflow(),
        sourceKind: LocalWorkflowSource.importFile,
      );
      notifier.rename(id, '  新名字  ');

      expect(notifier.byId(id)?.name, '新名字');
      expect(prefs.getString(localWorkflowsPrefsKey), contains('新名字'));
    });

    test('删除本地工作流会连带清掉它的节点配置，不留孤儿键', () async {
      final prefs = await _prefsWith();
      final container = _container(prefs);
      addTearDown(container.dispose);

      final id = container
          .read(localWorkflowProvider.notifier)
          .save(
            name: '待删除',
            workflowJson: _workflow(),
            sourceKind: LocalWorkflowSource.importFile,
          );
      await container.read(workflowProvider.notifier).saveMappingConfig(id, [
        _node(),
      ]);
      expect(prefs.containsKey('mapping_$id'), isTrue);

      container.read(localWorkflowProvider.notifier).remove(id);

      expect(container.read(localWorkflowProvider), isEmpty);
      expect(prefs.containsKey('mapping_$id'), isFalse);
    });

    test('totalBytes 汇总所有条目的实际占用', () async {
      final prefs = await _prefsWith();
      final container = _container(prefs);
      addTearDown(container.dispose);
      final notifier = container.read(localWorkflowProvider.notifier);

      notifier.save(
        name: 'A',
        workflowJson: _workflow('a'),
        sourceKind: LocalWorkflowSource.importFile,
      );
      notifier.save(
        name: 'B',
        workflowJson: _workflow('b'),
        sourceKind: LocalWorkflowSource.savedFromRemote,
      );

      final sum = notifier.state.fold(0, (s, w) => s + w.sizeBytes);
      expect(notifier.totalBytes, sum);
      expect(notifier.totalBytes, greaterThan(0));
    });

    test('损坏的持久化数据不会让页面崩掉', () async {
      final prefs = await _prefsWith({localWorkflowsPrefsKey: '{not json'});
      final container = _container(prefs);
      addTearDown(container.dispose);

      expect(container.read(localWorkflowProvider), isEmpty);
    });
  });

  group('展示名解析', () {
    test('本地工作流用库里的名称，非本地沿用文件名去后缀', () {
      final workflows = [
        LocalWorkflow(
          id: 'local_x1',
          name: '我的写真',
          createdAt: 0,
          sourceKind: LocalWorkflowSource.importFile,
          workflowJson: _workflow(),
        ),
      ];

      expect(
        resolveWorkflowName(workflows, 'local_x1', localLabel: '本地导入'),
        '我的写真',
      );
      // 库里没有对应条目时回退到调用方给的本地标签，而不是崩掉
      expect(
        resolveWorkflowName(<LocalWorkflow>[], 'local_x1', localLabel: '本地导入'),
        '本地导入',
      );
      expect(
        resolveWorkflowName(workflows, 'upscale_api.json', localLabel: '本地导入'),
        'upscale',
      );
    });
  });

  group('节点配置的内容哈希', () {
    test('旧格式（裸数组）仍能读出节点，哈希为 null', () async {
      final prefs = await _prefsWith({
        'mapping_old': jsonEncode([_node().toJson()]),
      });
      final container = _container(prefs);
      addTearDown(container.dispose);
      final notifier = container.read(workflowProvider.notifier);

      expect(notifier.getMappingConfig('old')?.length, 1);
      expect(notifier.getMappingContentHash('old'), isNull);
      expect(notifier.hasMappingConfig('old'), isTrue);
    });

    test('新格式写入后可读回哈希与节点', () async {
      final prefs = await _prefsWith();
      final container = _container(prefs);
      addTearDown(container.dispose);
      final notifier = container.read(workflowProvider.notifier);

      await notifier.saveMappingConfig('wf', [_node()], contentHash: 'h123');

      expect(notifier.getMappingContentHash('wf'), 'h123');
      expect(notifier.getMappingConfig('wf')?.first.alias, '提示词');
    });

    test('内容哈希不受 prompt 包装格式影响（先归一化再算）', () {
      final flat = _workflow();
      final wrapped = {'prompt': _workflow(), 'extra_data': {}};

      expect(
        WorkflowNotifier.contentHashOf(flat),
        WorkflowNotifier.contentHashOf(wrapped),
      );
      expect(
        WorkflowNotifier.contentHashOf(_workflow('another text')),
        isNot(WorkflowNotifier.contentHashOf(flat)),
      );
    });
  });

  group('另存到本地的 id 前缀（历史 bug：lw_ 被误判成服务器工作流）', () {
    test('save 不指定 id 时使用 local_ 前缀', () async {
      final prefs = await _prefsWith();
      final container = _container(prefs);
      addTearDown(container.dispose);

      final id = container
          .read(localWorkflowProvider.notifier)
          .save(
            name: '来自服务器',
            workflowJson: _workflow(),
            sourceKind: LocalWorkflowSource.savedFromRemote,
          );

      expect(id, startsWith('local_'));
    });

    test('读取时旧 lw_ 条目迁移成 local_ 前缀，名字保留', () async {
      final legacy = {
        'id': 'lw_abc123',
        'name': '基础ZIT文生图',
        'createdAt': 1791579799776,
        'sourceKind': 'savedFromRemote',
        'originName': 'basic_api.json',
        'workflowJson': _workflow(),
      };
      final prefs = await _prefsWith({
        localWorkflowsPrefsKey: jsonEncode([legacy]),
      });
      final container = _container(prefs);
      addTearDown(container.dispose);

      final list = container.read(localWorkflowProvider);
      expect(list, hasLength(1));
      expect(list.single.id, 'local_abc123');
      expect(list.single.name, '基础ZIT文生图');
      // 迁移结果要落盘，重启后依然是 local_ 前缀
      final stored =
          jsonDecode(prefs.getString(localWorkflowsPrefsKey)!) as List;
      expect((stored.single as Map)['id'], 'local_abc123');
    });

    test('lw_ 迁移时若 local_ 同 id 已存在（内容相同），丢弃旧条目', () async {
      final legacy = {
        'id': 'lw_abc123',
        'name': '重复条目',
        'createdAt': 1,
        'sourceKind': 'savedFromRemote',
        'workflowJson': _workflow(),
      };
      final kept = {
        'id': 'local_abc123',
        'name': '正式条目',
        'createdAt': 2,
        'sourceKind': 'importFile',
        'workflowJson': _workflow(),
      };
      final prefs = await _prefsWith({
        localWorkflowsPrefsKey: jsonEncode([legacy, kept]),
      });
      final container = _container(prefs);
      addTearDown(container.dispose);

      final list = container.read(localWorkflowProvider);
      expect(list, hasLength(1));
      expect(list.single.id, 'local_abc123');
      expect(list.single.name, '正式条目');
    });
  });
}
