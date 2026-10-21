import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:comfyui_mobilepocket/l10n/app_localizations.dart';
import 'package:comfyui_mobilepocket/models/workflow_node.dart';
import 'package:comfyui_mobilepocket/ui/builder/param_widgets/latent_size_card.dart';
import 'package:comfyui_mobilepocket/ui/builder/param_widgets/param_card_registry.dart';

WorkflowNode _node(
  String key, {
  String classType = 'EmptyLatentImage',
  String alias = '',
}) => WorkflowNode(
  id: '7',
  classType: classType,
  key: key,
  alias: alias.isEmpty ? key : alias,
  exposed: true,
  paramType: ParamType.intType,
);

Future<void> _pump(
  WidgetTester tester,
  List<WorkflowNode> params,
  Map<String, TextEditingController> controllers,
) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: LatentSizeCard(
          params: params,
          controllerOf: (node) => controllers[node.key],
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('宽高都在 → 显示当前尺寸，且不改写它', (tester) async {
    final c = {
      'width': TextEditingController(text: '720'),
      'height': TextEditingController(text: '1281'),
    };
    await _pump(tester, [_node('width'), _node('height')], c);

    // 原样显示，不因为「不是预设」就动它
    expect(find.text('720 × 1281'), findsOneWidget);
    expect(c['width']!.text, '720');
    expect(c['height']!.text, '1281');
  });

  testWidgets('点比例 + 长边 → 写回 width / height', (tester) async {
    final c = {
      'width': TextEditingController(text: '512'),
      'height': TextEditingController(text: '512'),
    };
    await _pump(tester, [_node('width'), _node('height')], c);

    await tester.tap(find.text('3:4'));
    await tester.pump();
    await tester.tap(find.text('1024'));
    await tester.pump();

    expect(c['width']!.text, '768');
    expect(c['height']!.text, '1024');
    expect(find.text('768 × 1024'), findsOneWidget);
  });

  testWidgets('只勾 batch_size → 只有张数，比例那一套不出现', (tester) async {
    final c = {'batch_size': TextEditingController(text: '1')};
    await _pump(tester, [_node('batch_size', alias: '张数')], c);

    expect(find.text('张数'), findsOneWidget);
    expect(find.text('画面比例'), findsNothing);
    expect(find.text('长边'), findsNothing);
  });

  testWidgets('张数步进只改 batch_size，且夹在 1–8', (tester) async {
    final c = {
      'batch_size': TextEditingController(text: '1'),
      'width': TextEditingController(text: '1024'),
    };
    await _pump(tester, [_node('batch_size', alias: '张数'), _node('width')], c);

    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();
    expect(c['batch_size']!.text, '2');
    // 宽高没被顺手动过
    expect(c['width']!.text, '1024');

    for (var i = 0; i < 10; i++) {
      await tester.tap(find.byIcon(Icons.add));
      await tester.pump();
    }
    expect(c['batch_size']!.text, '8');
  });

  testWidgets('自定义宽高入口可展开，直接改原控制器', (tester) async {
    final c = {
      'width': TextEditingController(text: '1024'),
      'height': TextEditingController(text: '1024'),
    };
    await _pump(tester, [_node('width'), _node('height')], c);

    await tester.tap(find.text('自定义宽高'));
    await tester.pump();

    final fields = tester
        .widgetList<TextField>(find.byType(TextField))
        .toList();
    expect(fields.length, 2);
    await tester.enterText(find.byType(TextField).first, '960');
    expect(c['width']!.text, '960');
  });

  group('matchParamCard', () {
    test('latent 且宽高都在 → 命中尺寸卡', () {
      final m = matchParamCard([_node('width'), _node('height')]);
      expect(m?.kind, ParamCardKind.latentSize);
    });

    test('只勾 batch_size → 也命中（卡片只显示张数）', () {
      final m = matchParamCard([_node('batch_size')]);
      expect(m?.kind, ParamCardKind.latentSize);
    });

    test('只勾 width（没有 height）→ 不命中，回退通用渲染', () {
      expect(matchParamCard([_node('width')]), isNull);
    });

    test('非 latent 节点 → 不命中', () {
      final n = _node('steps', classType: 'KSampler');
      expect(matchParamCard([n]), isNull);
    });
  });
}
