import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:comfyui_mobilepocket/l10n/app_localizations.dart';
import 'package:comfyui_mobilepocket/providers/shared_preferences_provider.dart';
import 'package:comfyui_mobilepocket/ui/builder/workflow_view.dart';
import 'package:comfyui_mobilepocket/ui/widgets/param_config_tile.dart';

const Map<String, dynamic> _workflow = {
  '4': {
    'class_type': 'CheckpointLoaderSimple',
    'inputs': {'ckpt_name': 'old.safetensors'},
  },
  '3': {
    'class_type': 'KSampler',
    'inputs': {'seed': 1, 'steps': 20},
  },
  '9': {
    'class_type': 'CLIPLoader',
    'inputs': {
      'clip_name': 'qwen.safetensors',
      'type': 'lumina2',
      'device': 'default',
    },
    '_meta': {'title': '加载CLIP'},
  },
};

/// 两个节点的已保存配置：用来验证「单行参数」与「搜索无命中」。
List<Map<String, dynamic>> _mappingConfig() => [
  {
    'id': '4',
    'classType': 'CheckpointLoaderSimple',
    'key': 'ckpt_name',
    'alias': '大模型',
    'exposed': true,
    'title': '',
    'paramType': 'enumType',
    'options': ['old.safetensors'],
    'value': 'old.safetensors',
  },
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
];

/// 卡片头是 `Text.rich`（节点名 + 角色），`find.text` 够不着。
Finder richTextContaining(String text) => find.byWidgetPredicate(
  (w) => w is Text && ((w.textSpan?.toPlainText().contains(text)) ?? false),
);

/// 用「快照模式」进配置页：不请求服务器，配置直接来自快照里的 mappingConfig。
Future<void> _pumpConfig(
  WidgetTester tester, {
  List<Map<String, dynamic>>? mapping,
}) async {
  // 列表够长时 `ListView.builder` 只建可见的那几项，靠后的节点卡片会查不到 ——
  // 放大视口让它们一次都渲染出来（不影响被测的行为本身）
  tester.view.physicalSize = const Size(400, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(
    'comfy_workflow_snapshots',
    jsonEncode([
      {
        'id': 'snap_1',
        'sourceName': '测试工作流',
        'createdAt': 1760000000000,
        'serverId': 'srv_1',
        'workflowJson': _workflow,
        'mappingConfig': mapping ?? _mappingConfig(),
      },
    ]),
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const WorkflowView(workflowId: 'wf_test', snapshotId: 'snap_1'),
      ),
    ),
  );
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  testWidgets('参数行是单行：每个参数只占 44px', (tester) async {
    await _pumpConfig(tester);

    // 卡片里的参数行会随解析结果增减，这里只关心「每行多高」
    expect(find.byType(ParamConfigTile), findsWidgets);
    for (final tile in tester.widgetList<ParamConfigTile>(
      find.byType(ParamConfigTile),
    )) {
      final size = tester.getSize(find.byWidget(tile));
      expect(size.height, lessThanOrEqualTo(44));
    }

    // 别名只出现一次（以前勾选行与输入框各显示一遍）
    expect(find.text('采样步数'), findsOneWidget);
  });

  testWidgets('搜索没有命中时给出空态，而不是整片留白', (tester) async {
    await _pumpConfig(tester);

    // 搜索住在「添加参数」页里 —— 主视图只放已选的几项，用不上搜索
    await tester.tap(find.textContaining('添加参数'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '不存在的参数');
    await tester.pumpAndSettle();

    expect(find.byType(ParamConfigTile), findsNothing);
    expect(find.text('没有匹配的参数'), findsOneWidget);

    // 清空后恢复
    await tester.enterText(find.byType(TextField).first, '');
    await tester.pumpAndSettle();
    expect(find.byType(ParamConfigTile), findsWidgets);
  });

  testWidgets('旧配置里「别名 = 节点标题」的坏值会自愈成真实参数名', (tester) async {
    await _pumpConfig(
      tester,
      mapping: [
        {
          'id': '9',
          'classType': 'CLIPLoader',
          'key': 'type',
          'alias': '加载CLIP',
          'exposed': true,
          'title': '加载CLIP',
          'paramType': 'text',
          'options': <String>[],
          'value': 'lumina2',
        },
        {
          'id': '9',
          'classType': 'CLIPLoader',
          'key': 'device',
          'alias': '加载CLIP',
          'exposed': true,
          'title': '加载CLIP',
          'paramType': 'text',
          'options': <String>[],
          'value': 'default',
        },
      ],
    );

    // 主视图只放已选参数、不再有节点卡片头，所以坏别名一个都不剩
    expect(find.text('加载CLIP'), findsNothing);
    expect(find.text('type'), findsOneWidget);
    expect(find.text('device'), findsOneWidget);

    // 节点身份由「添加参数」页的卡片头给出 —— 全量列表在那边
    await tester.tap(find.textContaining('添加参数'));
    await tester.pumpAndSettle();
    expect(richTextContaining('加载CLIP'), findsOneWidget);
  });
}
