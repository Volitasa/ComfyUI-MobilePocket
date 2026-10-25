import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:comfyui_mobilepocket/l10n/app_localizations.dart';
import 'package:comfyui_mobilepocket/models/workflow_node.dart';
import 'package:comfyui_mobilepocket/services/node_role.dart';
import 'package:comfyui_mobilepocket/services/workflow_node_parser.dart';
import 'package:comfyui_mobilepocket/ui/builder/param_picker_view.dart';
import 'package:comfyui_mobilepocket/ui/widgets/page_title.dart';

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
  testWidgets('顶部标题与同级页面同一字号', (tester) async {
    await _pumpPicker(tester);

    // 以前添加页是系统默认字号、配置页是 16 号，两个页面来回切能看出跳字
    final title = tester.widget<Text>(find.text('添加参数'));
    expect(title.style, kSubPageTitleStyle);
  });

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

  testWidgets('同名节点靠连线说清谁是谁 —— 连到哪个节点的哪个参数', (tester) async {
    await _pumpPicker(tester);

    // 两个都叫「CLIP文本编码」，区别只在接到了采样器的哪个口；
    // 这两个名字都取自工作流本身（节点名 + 输入名），不是我们起的标签
    expect(find.text('CLIP文本编码'), findsNWidgets(2));
    expect(find.text('连到 KSampler · positive'), findsOneWidget);
    expect(find.text('连到 KSampler · negative'), findsOneWidget);

    // 加载类节点直接说装了什么
    expect(find.text('v1-5'), findsOneWidget);
  });

  testWidgets('说不清位置的节点不硬编一句', (tester) async {
    await _pumpPicker(tester);

    // 这个 KSampler 没有下游，也不装资源 —— 没有就别编
    expect(find.text('KSampler'), findsOneWidget);
    expect(find.textContaining('连到 KSampler'), findsNWidgets(2));
  });
}
