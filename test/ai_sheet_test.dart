import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:comfyui_mobilepocket/l10n/app_localizations.dart';
import 'package:comfyui_mobilepocket/models/ai_provider_config.dart';
import 'package:comfyui_mobilepocket/models/workflow_node.dart';
import 'package:comfyui_mobilepocket/providers/ai_settings_provider.dart';
import 'package:comfyui_mobilepocket/providers/shared_preferences_provider.dart';
import 'package:comfyui_mobilepocket/services/ai/ai_client.dart';
import 'package:comfyui_mobilepocket/ui/builder/ai/ai_sheet.dart';

WorkflowNode node({
  required String id,
  String key = 'prompt',
  String title = '',
  String value = '',
}) => WorkflowNode(
  id: id,
  classType: 'TextEncodeQwen',
  key: key,
  alias: key,
  title: title,
  paramType: ParamType.text,
  control: ParamControl.text,
  value: value,
);

AiClient patchClient(String value) {
  return AiClient(
    client: MockClient.streaming((request, body) async {
      final payload =
          '{"patches":[{"node":"5","key":"prompt","value":${jsonEncode(value)}}]}';
      final chunks = [
        'data: {"model":"mock-model","choices":[{"delta":{"content":${jsonEncode(payload)}}}]}\n\n',
        'data: [DONE]\n\n',
      ].map(utf8.encode).toList();
      return http.StreamedResponse(Stream.fromIterable(chunks), 200);
    }),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TextEditingController controller;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      kAiSettingsPrefsKey: jsonEncode(
        const AiSettings(
          providers: [
            AiProviderConfig(
              id: 't',
              name: 't',
              baseUrl: 'https://example.test',
              model: 'm',
              apiKey: 'sk',
            ),
          ],
          activeId: 't',
        ).toJson(),
      ),
    });
    controller = TextEditingController(text: 'old prompt');
  });

  Widget wrap(Widget child, SharedPreferences prefs) {
    return ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: child),
      ),
    );
  }

  AiSheetArgs args({required WorkflowNode output, AiClient? client}) {
    final nodes = [
      output,
      node(id: '10', key: 'text', title: '基础设定', value: 'base'),
    ];
    return AiSheetArgs(
      workflowKey: 'wf',
      serverId: 's',
      baseUrl: 'http://h',
      nodes: nodes,
      textOf: (n) => n.id == output.id ? controller.text : 'base',
      imageValueOf: (_) => null,
      localBytesOf: (_) => null,
      controllerOf: (_) => controller,
      scrollController: ScrollController(),
      sheetController: null,
      initialParam: output,
      client: client,
    );
  }

  testWidgets('生成 → 结果卡 → 写入，控制器文本被替换', (tester) async {
    final prefs = await SharedPreferences.getInstance();
    final output = node(id: '5', title: '文本编码', value: 'old prompt');

    await tester.pumpWidget(
      wrap(
        AiSheet(args: args(output: output, client: patchClient('new prompt'))),
        prefs,
      ),
    );

    // 选「改写」模板（看图写词需要图片输入，这里没有）
    await tester.tap(find.text('改写'));
    await tester.pump();

    await tester.tap(find.text('生成'));
    await tester.pump();
    // 流式回调是真实异步：让事件循环跑一会儿再收敛
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();

    expect(find.textContaining('new prompt'), findsWidgets);
    // 卡片展示的是要写入的文本，不是整包 JSON
    expect(find.textContaining('patches'), findsNothing);
    // 结果卡底部显示供应商实际回报的模型名
    expect(find.text('模型：mock-model'), findsOneWidget);
    final writeButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '写入'),
    );
    expect(writeButton.onPressed, isNotNull);

    await tester.ensureVisible(find.text('写入'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('写入'));
    await tester.pumpAndSettle();

    expect(controller.text, 'new prompt');
    // 写入后按钮变「已写入」，并出现可撤销的横幅
    expect(find.text('已写入'), findsWidgets);
    expect(find.text('撤销'), findsOneWidget);
  });

  testWidgets('默认是「自定义」：指令为空时提示，输入后即可发送', (tester) async {
    final prefs = await SharedPreferences.getInstance();
    final output = node(id: '5', title: '文本编码', value: 'old prompt');

    await tester.pumpWidget(
      wrap(AiSheet(args: args(output: output, client: patchClient('自定义结果'))), prefs),
    );

    // 自定义是默认项，指令框本来就是空的
    await tester.tap(find.text('生成'));
    await tester.pumpAndSettle();
    expect(find.text('写一句要求，或选一个模板'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '把这段改成赛博朋克风格');
    await tester.tap(find.text('生成'));
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();

    expect(find.textContaining('自定义结果'), findsWidgets);
  });

  testWidgets('长按非文本参数 → 作为输入引用预填，而不是输出', (tester) async {
    final prefs = await SharedPreferences.getInstance();
    final steps = WorkflowNode(
      id: '4',
      classType: 'KSampler',
      key: 'steps',
      alias: '步数',
      title: 'K采样器',
      paramType: ParamType.intType,
      control: ParamControl.number,
      value: 20,
    );
    final output = node(id: '5', title: '文本编码', value: 'old');

    final a = AiSheetArgs(
      workflowKey: 'wf',
      serverId: 's',
      baseUrl: 'http://h',
      nodes: [steps, output],
      textOf: (n) => n.id == '5' ? controller.text : '20',
      imageValueOf: (_) => null,
      localBytesOf: (_) => null,
      controllerOf: (_) => controller,
      scrollController: ScrollController(),
      sheetController: null,
      initialParam: steps,
      client: patchClient('x'),
    );

    await tester.pumpWidget(wrap(AiSheet(args: a), prefs));
    await tester.pumpAndSettle();

    // 出现在「输入」区（chip 文案为 节点标题 · 参数名）
    expect(find.text('K采样器 · steps'), findsOneWidget);
    // 输出区仍是「选择要填充的参数」
    expect(find.text('选择要填充的参数'), findsOneWidget);
  });

  testWidgets('缺图片时给出内联提示（不能是会被抽屉挡住的 SnackBar）', (tester) async {
    final prefs = await SharedPreferences.getInstance();
    final output = node(id: '5', title: '文本编码', value: 'old prompt');

    await tester.pumpWidget(
      wrap(AiSheet(args: args(output: output, client: patchClient('x'))), prefs),
    );

    // 切到「看图写词」，但没有选任何图片
    await tester.tap(find.text('看图写词'));
    await tester.pump();
    await tester.tap(find.text('生成'));
    await tester.pumpAndSettle();

    expect(find.text('看图写词需要至少一张参考图'), findsOneWidget);
  });

  testWidgets('撤销恢复旧值', (tester) async {
    final prefs = await SharedPreferences.getInstance();
    final output = node(id: '5', title: '文本编码', value: 'old prompt');

    await tester.pumpWidget(
      wrap(
        AiSheet(args: args(output: output, client: patchClient('new prompt'))),
        prefs,
      ),
    );
    await tester.tap(find.text('改写'));
    await tester.pump();
    await tester.tap(find.text('生成'));
    await tester.pump();
    // 流式回调是真实异步：让事件循环跑一会儿再收敛
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('写入'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('写入'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();

    expect(controller.text, 'old prompt');
  });
}
