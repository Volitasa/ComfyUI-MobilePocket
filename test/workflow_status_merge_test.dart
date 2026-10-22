import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:comfyui_mobilepocket/providers/connection_provider.dart';
import 'package:comfyui_mobilepocket/providers/workflow_provider.dart';

/// 已连接，但指向一个必然连不上的端口：拉内容立刻失败 →
/// 状态按「保持已配置」处理，测试不必真的起一台 ComfyUI。
class _DeadServer extends ConnectionNotifier {
  @override
  ConfigState build() => ConfigState(
    servers: [
      ServerConfig(id: 'srv1', name: '', primaryUrl: 'http://127.0.0.1:1'),
    ],
    activeServerId: 'srv1',
    comfyUrl: 'http://127.0.0.1:1',
    isConnected: true,
  );
}

String _mappingPayload() => jsonEncode({
  'version': 1,
  'contentHash': 'h1',
  'nodes': [
    {
      'id': '3',
      'classType': 'KSampler',
      'key': 'steps',
      'alias': '采样步数',
      'exposed': true,
      'title': '',
      'paramType': 'intType',
      'options': <String>[],
      'value': 20,
    },
  ],
});

Future<ProviderContainer> _container(Map<String, Object> seed) async {
  SharedPreferences.setMockInitialValues(seed);
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      connectionProvider.overrideWith(() => _DeadServer()),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('工作流状态表：单条刷新不得抹掉其它条目', () {
    test('点进 A 再返回后，B 仍然是「已配置」而不是 unknown', () async {
      final container = await _container({
        'mapping_a_api.json': _mappingPayload(),
        'mapping_b_api.json': _mappingPayload(),
      });
      final notifier = container.read(workflowProvider.notifier);

      // 首次进页面：整张表按服务器列表算一遍
      await notifier.refreshStatuses(['a_api.json', 'b_api.json']);
      expect(
        container.read(workflowProvider).statusOf('a_api.json'),
        WorkflowMappingStatus.configured,
      );
      expect(
        container.read(workflowProvider).statusOf('b_api.json'),
        WorkflowMappingStatus.configured,
      );

      // 点进 a 再返回（只刷新 a 这一条）
      await notifier.refreshStatuses(['a_api.json']);

      // 这是本次报的 bug：修复前 b 会掉成 unknown → 列表显示「未配置」，
      // 但配置其实还在、点进去照样能直接运行
      expect(
        container.read(workflowProvider).statusOf('b_api.json'),
        WorkflowMappingStatus.configured,
      );
    });

    test('未配置的条目保持 unconfigured，不会退化成 unknown', () async {
      final container = await _container({
        'mapping_a_api.json': _mappingPayload(),
      });
      final notifier = container.read(workflowProvider.notifier);

      await notifier.refreshStatuses(['a_api.json', 'c_api.json']);
      expect(
        container.read(workflowProvider).statusOf('c_api.json'),
        WorkflowMappingStatus.unconfigured,
      );

      await notifier.refreshStatuses(['a_api.json']);
      expect(
        container.read(workflowProvider).statusOf('c_api.json'),
        WorkflowMappingStatus.unconfigured,
      );
    });

    test('传完整列表（pruneMissing）时才清掉已删除条目的状态', () async {
      final container = await _container({
        'mapping_a_api.json': _mappingPayload(),
        'mapping_b_api.json': _mappingPayload(),
      });
      final notifier = container.read(workflowProvider.notifier);

      await notifier.refreshStatuses([
        'a_api.json',
        'b_api.json',
      ], pruneMissing: true);
      // 服务器上 b 被删了，列表刷新后不该留着它的旧状态
      await notifier.refreshStatuses(['a_api.json'], pruneMissing: true);

      expect(
        container.read(workflowProvider).statusOf('b_api.json'),
        WorkflowMappingStatus.unknown,
      );
      expect(
        container.read(workflowProvider).statusOf('a_api.json'),
        WorkflowMappingStatus.configured,
      );
    });

    test('UI 工作流的解析状态同样按条合并', () async {
      final container = await _container({});
      final notifier = container.read(workflowProvider.notifier);

      // 两个都没有解析缓存 → unparsed；这条路径不发请求
      await notifier.refreshUiStatuses(['x.json', 'y.json']);
      expect(
        container.read(workflowProvider).uiStatusOf('y.json'),
        UiWorkflowStatus.unparsed,
      );

      // 解析 x 之后只会单条刷新（remote_workflow_section 里那样）
      await notifier.refreshUiStatuses(['x.json']);
      // 修复前 y 会掉成 unknown，界面上「服务器有更新」的提示随之消失
      expect(
        container.read(workflowProvider).uiStatusOf('y.json'),
        UiWorkflowStatus.unparsed,
      );
    });
  });
}
