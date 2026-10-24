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
};

/// 三个参数里只把「采样步数」放进表单，另外两个留着没勾。
List<Map<String, dynamic>> _mappingConfig() => [
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
  {
    'id': '3',
    'classType': 'KSampler',
    'key': 'seed',
    'alias': '随机种子',
    'exposed': false,
    'title': '',
    'paramType': 'seed',
    'options': <String>[],
    'value': 1,
  },
  {
    'id': '4',
    'classType': 'CheckpointLoaderSimple',
    'key': 'ckpt_name',
    'alias': '大模型',
    'exposed': false,
    'title': '',
    'paramType': 'enumType',
    'options': ['old.safetensors'],
    'value': 'old.safetensors',
  },
];

/// 用「快照模式」进配置页：不请求服务器，配置直接来自快照里的 mappingConfig。
Future<void> _pumpConfig(WidgetTester tester) async {
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
        'mappingConfig': _mappingConfig(),
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

/// 点某个参数所在行的勾选框（别名由输入框显示，先按它定位到行）。
Future<void> _toggleRow(WidgetTester tester, String alias) async {
  final row = find.ancestor(
    of: find.text(alias),
    matching: find.byType(ParamConfigTile),
  );
  await tester.tap(find.descendant(of: row, matching: find.byType(Checkbox)));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('主视图只放已选参数，没勾的不占地方', (tester) async {
    await _pumpConfig(tester);

    expect(find.text('采样步数'), findsOneWidget);
    expect(find.text('随机种子'), findsNothing);
    expect(find.text('大模型'), findsNothing);

    // 剩下的两项都还有路可去 —— 入口上写明还剩多少
    expect(find.text('添加参数（还有 2 项）'), findsOneWidget);
  });

  testWidgets('主视图的行不再画勾选框，行尾是移出', (tester) async {
    await _pumpConfig(tester);

    // 已经放进表单的参数不需要再勾一次，否则一行上两个相反的入口
    expect(find.byType(Checkbox), findsNothing);
    expect(find.byIcon(Icons.close), findsOneWidget);
  });

  testWidgets('移出后从表单里消失，全移完给出空态', (tester) async {
    await _pumpConfig(tester);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    expect(find.text('采样步数'), findsNothing);
    expect(find.text('还没有参数放进表单'), findsOneWidget);
    // 移出不是删除：还能加回来，数量也跟着回到 3
    expect(find.text('添加参数（还有 3 项）'), findsOneWidget);
  });

  testWidgets('在添加页勾上，返回主视图就出现了', (tester) async {
    await _pumpConfig(tester);

    await tester.tap(find.textContaining('添加参数'));
    await tester.pumpAndSettle();

    // 添加页是完整列表：同一节点下没勾的那项也在（该节点有已勾项，默认展开）
    expect(find.text('采样步数'), findsOneWidget);
    expect(find.text('随机种子'), findsOneWidget);

    await _toggleRow(tester, '随机种子');
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();

    // 回到主视图：新勾的进了表单，统计也跟着变
    expect(find.text('采样步数'), findsOneWidget);
    expect(find.text('随机种子'), findsOneWidget);
    expect(find.textContaining('已放进表单 2 项'), findsOneWidget);
    expect(find.text('添加参数（还有 1 项）'), findsOneWidget);
  });

  testWidgets('全部参数一个不少：主视图收窄不等于裁剪', (tester) async {
    await _pumpConfig(tester);

    await tester.tap(find.textContaining('添加参数'));
    await tester.pumpAndSettle();

    // 两张节点卡片都在 —— 收窄只发生在主视图，不是识别范围
    expect(find.text('KSampler'), findsOneWidget);
    expect(find.text('CheckpointLoaderSimple'), findsOneWidget);

    // 没勾过的节点默认收起，展开后三个参数一个不少
    await tester.tap(find.text('CheckpointLoaderSimple'));
    await tester.pumpAndSettle();
    expect(find.byType(ParamConfigTile), findsNWidgets(3));
  });
}
