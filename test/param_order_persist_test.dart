import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:comfyui_mobilepocket/models/workflow_node.dart';
import 'package:comfyui_mobilepocket/providers/shared_preferences_provider.dart';
import 'package:comfyui_mobilepocket/providers/workflow_provider.dart';
import 'package:comfyui_mobilepocket/services/param_order.dart';

WorkflowNode _n(String id, String key, {bool exposed = true}) => WorkflowNode(
  id: id,
  classType: 'Node',
  key: key,
  alias: '$id-$key',
  exposed: exposed,
);

/// 运行页取卡片顺序的方式（`run_view.dart:928`）：按 node.id 分组、保持首现顺序。
List<String> _runViewCardOrder(List<WorkflowNode> config) => [
  for (final s in buildParamSections(config.where((n) => n.exposed)))
    s.nodeId,
];

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
  test('段顺序随配置落盘，运行页读回来是同一个顺序', () async {
    final container = await _container();
    final notifier = container.read(workflowProvider.notifier);

    // 配置页把「参考人物」那段拖到了最前面
    final nodes = [
      _n('refA', 'image'),
      _n('size', 'width'),
      _n('size', 'height'),
      _n('clip', 'text', exposed: false), // 未选，位置不该被挤走
      _n('refB', 'image'),
    ];
    await notifier.saveMappingConfig('wf.json', nodes, serverId: 'srv1');

    final saved = notifier.getMappingConfig('wf.json', serverId: 'srv1')!;
    expect(saved.map((n) => '${n.id}:${n.key}').toList(), [
      'refA:image',
      'size:width',
      'size:height',
      'clip:text',
      'refB:image',
    ]);

    // 运行页只取已选的，卡片顺序 = 配置页段顺序
    expect(_runViewCardOrder(saved), ['refA', 'size', 'refB']);
  });

  test('合并新解析后仍是用户排的段顺序', () async {
    await _container();

    final saved = [
      _n('refA', 'image'),
      _n('size', 'width'),
      _n('size', 'height'),
    ];
    // 服务器重新解析回来的是工作流里的原始顺序
    final parsed = [
      _n('size', 'width'),
      _n('size', 'height'),
      _n('refA', 'image'),
    ];
    final merged = orderLikeSavedConfig(parsed, saved);
    expect(_runViewCardOrder(merged), ['refA', 'size']);
  });
}
