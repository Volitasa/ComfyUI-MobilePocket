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

/// 用「快照模式」进配置页：不请求服务器，配置直接来自快照里的 mappingConfig。
Future<void> _pumpConfig(
  WidgetTester tester, {
  List<Map<String, dynamic>>? mapping,
}) async {
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

    // 参数行改用真实参数名；「加载CLIP」只剩卡片头那一个
    expect(find.text('加载CLIP'), findsOneWidget);
    expect(find.text('type'), findsOneWidget);
    expect(find.text('device'), findsOneWidget);
  });
}
