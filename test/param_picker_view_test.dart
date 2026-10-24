import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:comfyui_mobilepocket/l10n/app_localizations.dart';
import 'package:comfyui_mobilepocket/models/workflow_node.dart';
import 'package:comfyui_mobilepocket/services/node_role.dart';
import 'package:comfyui_mobilepocket/services/workflow_node_parser.dart';
import 'package:comfyui_mobilepocket/ui/builder/param_picker_view.dart';

/// 一条带连线的链路：两个同名的文本编码 + 一段采样 + 一个模型。
const Map<String, dynamic> _workflow = {
  '1': {
    'class_type': 'CheckpointLoaderSimple',
    'inputs': {'ckpt_name': 'v1-5.safetensors'},
  },
  '2': {
    'class_type': 'CLIPTextEncode',
    'inputs': {
      'text': 'a cat',
      'clip': ['1', 1],
    },
  },
  '3': {
    'class_type': 'CLIPTextEncode',
    'inputs': {
      'text': 'blurry',
      'clip': ['1', 1],
    },
  },
  '5': {
    'class_type': 'KSampler',
    'inputs': {
      'seed': 1,
      'steps': 20,
      'model': ['1', 0],
      'positive': ['2', 0],
      'negative': ['3', 0],
    },
  },
};

List<WorkflowNode> _nodes() => [
  WorkflowNode(
    id: '2',
    classType: 'CLIPTextEncode',
    key: 'text',
    alias: 'text',
    title: 'CLIP文本编码',
    exposed: true,
    paramType: ParamType.text,
    value: 'a cat',
  ),
  WorkflowNode(
    id: '3',
    classType: 'CLIPTextEncode',
    key: 'text',
    alias: 'text',
    title: 'CLIP文本编码',
    exposed: false,
    paramType: ParamType.text,
    value: 'blurry',
  ),
  WorkflowNode(
    id: '5',
    classType: 'KSampler',
    key: 'steps',
    alias: 'steps',
    title: '',
    exposed: true,
    paramType: ParamType.intType,
    value: 20,
  ),
  WorkflowNode(
    id: '1',
    classType: 'CheckpointLoaderSimple',
    key: 'ckpt_name',
    alias: 'ckpt_name',
    title: '',
    exposed: true,
    paramType: ParamType.enumType,
    value: 'v1-5.safetensors',
  ),
  WorkflowNode(
    id: '99',
    classType: 'SomeCommunityNode',
    key: 'whatever',
    alias: 'whatever',
    title: '',
    exposed: false,
    paramType: ParamType.text,
    value: 'x',
  ),
];

/// 卡片头是 `Text.rich`（节点名 + 角色拼在一起），`find.text` 够不着，
/// 只能按渲染出来的纯文本找。
Finder richTextContaining(String text) => find.byWidgetPredicate(
  (w) => w is Text && ((w.textSpan?.toPlainText().contains(text)) ?? false),
);

Future<void> _pumpPicker(WidgetTester tester) async {
  // 列表够长时 `ListView.builder` 只建可见的那几项，段头会查不到 ——
  // 放大视口，让五个节点一次都渲染出来（不影响被测的行为本身）
  tester.view.physicalSize = const Size(400, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: ParamPickerView(
        nodes: _nodes(),
        aliasControllers: {},
        issues: const SpecIssues(),
        roles: inferNodeRoles(_workflow),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('按用途分段，常用的排在前', (tester) async {
    await _pumpPicker(tester);

    expect(find.text('提示词'), findsOneWidget);
    expect(find.text('采样'), findsOneWidget);
    expect(find.text('模型与权重'), findsOneWidget);
    // 没收录的节点不消失，只是排在最后一段
    expect(find.text('其余节点'), findsOneWidget);

    final promptY = tester.getTopLeft(find.text('提示词')).dy;
    final samplingY = tester.getTopLeft(find.text('采样')).dy;
    final modelY = tester.getTopLeft(find.text('模型与权重')).dy;
    final otherY = tester.getTopLeft(find.text('其余节点')).dy;
    expect(promptY, lessThan(samplingY));
    expect(samplingY, lessThan(modelY));
    expect(modelY, lessThan(otherY));
  });

  testWidgets('同名节点靠角色区分谁是谁', (tester) async {
    await _pumpPicker(tester);

    // 两个都叫「CLIP文本编码」，标签把它们区分开
    expect(richTextContaining('CLIP文本编码 · 正向条件'), findsOneWidget);
    expect(richTextContaining('CLIP文本编码 · 负向条件'), findsOneWidget);
    // 模型节点直接说装了什么
    expect(richTextContaining('CheckpointLoaderSimple · v1-5'), findsOneWidget);
  });

  testWidgets('没角色的节点不硬编一个', (tester) async {
    await _pumpPicker(tester);

    // 这个 KSampler 看不出阶段（没画 latent 连线），就不该硬给它贴一个
    expect(richTextContaining('KSampler'), findsOneWidget);
    expect(richTextContaining('KSampler · '), findsNothing);
  });
}
