import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:comfyui_mobilepocket/models/workflow_node.dart';
import 'package:comfyui_mobilepocket/providers/shared_preferences_provider.dart';
import 'package:comfyui_mobilepocket/providers/workflow_provider.dart';
import 'package:comfyui_mobilepocket/utils.dart';

WorkflowNode _node({required String alias}) => WorkflowNode(
  id: '3',
  classType: 'KSampler',
  key: 'steps',
  alias: alias,
  exposed: true,
  title: '',
  paramType: ParamType.intType,
  value: 20,
);

Future<ProviderContainer> _container() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('节点配置键：服务器工作流必须带归属', () {
    test('两台服务器上同名的工作流各存各的，互不覆盖', () async {
      final container = await _container();
      final notifier = container.read(workflowProvider.notifier);

      await notifier.saveMappingConfig('workflow_api.json', [
        _node(alias: 'A 的步数'),
      ], serverId: 'srv1');
      await notifier.saveMappingConfig('workflow_api.json', [
        _node(alias: 'B 的步数'),
      ], serverId: 'srv2');

      expect(
        notifier
            .getMappingConfig('workflow_api.json', serverId: 'srv1')
            ?.first
            .alias,
        'A 的步数',
      );
      expect(
        notifier
            .getMappingConfig('workflow_api.json', serverId: 'srv2')
            ?.first
            .alias,
        'B 的步数',
      );
    });

    test('不给 serverId 就读不到带归属的配置（旧键与归属键互不串台）', () async {
      final container = await _container();
      final notifier = container.read(workflowProvider.notifier);

      await notifier.saveMappingConfig('workflow_api.json', [
        _node(alias: 'A 的步数'),
      ], serverId: 'srv1');

      expect(
        notifier.getMappingConfig('workflow_api.json'),
        isNull,
        reason: '换键前这条能读到，换键后旧键必须彻底失效',
      );
      expect(notifier.hasMappingConfig('workflow_api.json'), isFalse);
    });

    test('删除配置只删自己那台服务器的，不误伤另一台', () async {
      final container = await _container();
      final notifier = container.read(workflowProvider.notifier);

      await notifier.saveMappingConfig('a_api.json', [
        _node(alias: 'A1'),
      ], serverId: 'srv1');
      await notifier.saveMappingConfig('a_api.json', [
        _node(alias: 'A2'),
      ], serverId: 'srv2');

      await notifier.removeMappingConfig('a_api.json', serverId: 'srv1');

      expect(
        notifier.hasMappingConfig('a_api.json', serverId: 'srv1'),
        isFalse,
      );
      expect(notifier.hasMappingConfig('a_api.json', serverId: 'srv2'), isTrue);
    });

    test('本地与解析缓存的 ID 自身唯一，不掺服务器前缀', () async {
      final container = await _container();
      final notifier = container.read(workflowProvider.notifier);

      // 哪怕把 serverId 传进去，这两类也不该改键 ——
      // 否则保存时加了前缀、读取时按原键找，配置就存进去却读不出来了
      await notifier.saveMappingConfig('local_abc', [
        _node(alias: '本地'),
      ], serverId: 'srv1');
      await notifier.saveMappingConfig('parsed_xyz', [
        _node(alias: '解析'),
      ], serverId: 'srv1');

      expect(notifier.getMappingConfig('local_abc')?.first.alias, '本地');
      expect(notifier.getMappingConfig('parsed_xyz')?.first.alias, '解析');
    });
  });

  group('节点配置键：纯函数判定', () {
    test('服务器工作流才需要归属', () {
      expect(needsServerScope('workflow_api.json'), isTrue);
      expect(needsServerScope('local_abc'), isFalse);
      expect(needsServerScope('parsed_xyz'), isFalse);
    });

    test('缺 serverId 时退回原键，不生成半成品键', () {
      expect(
        mappingKeyFor('workflow_api.json', null),
        'mapping_workflow_api.json',
      );
      expect(
        mappingKeyFor('workflow_api.json', ''),
        'mapping_workflow_api.json',
      );
    });

    test('同一个工作流在不同服务器上得到不同的键', () {
      expect(
        mappingKeyFor('workflow_api.json', 'srv1'),
        isNot(mappingKeyFor('workflow_api.json', 'srv2')),
      );
    });
  });
}
