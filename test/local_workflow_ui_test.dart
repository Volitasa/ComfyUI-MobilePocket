import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:comfyui_mobilepocket/providers/connection_provider.dart';
import 'package:comfyui_mobilepocket/providers/local_workflow_provider.dart';
import 'package:comfyui_mobilepocket/ui/home/local_workflow_section.dart';
import 'package:comfyui_mobilepocket/ui/settings/workflow_storage_view.dart';

Future<SharedPreferences> _prefsWithOneWorkflow() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(
    localWorkflowsPrefsKey,
    jsonEncode([
      {
        'id': 'local_x1',
        'name': '我的写真',
        'createdAt': DateTime.now().millisecondsSinceEpoch,
        'sourceKind': 'importFile',
        'originName': 'portrait_api.json',
        'workflowJson': {
          '1': {
            'inputs': {'text': 'a cat'},
            'class_type': 'CLIPTextEncode',
          },
        },
      },
    ]),
  );
  return prefs;
}

Future<void> _pump(WidgetTester tester, Widget child, SharedPreferences prefs) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: child),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('本地段：显示库里的名称、来源标签与删除入口', (tester) async {
    final prefs = await _prefsWithOneWorkflow();
    await _pump(tester, const LocalWorkflowSection(), prefs);

    // 不再统一显示「本地导入」，而是库里保存的真实名称
    expect(find.text('我的写真'), findsOneWidget);
    expect(find.text('本地导入'), findsNothing);
    // 段顶汇总与来源标签（卡片副标题形如「导入 · 10-12 · 0.1 KB · 未配置」）
    expect(find.textContaining('本地库 1 项'), findsOneWidget);
    expect(find.textContaining('导入 ·'), findsOneWidget);
    // 删除入口在弹出菜单里
    expect(find.byIcon(Icons.more_vert), findsOneWidget);
  });

  testWidgets('本地段空态：提示还没有本地工作流', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await _pump(tester, const LocalWorkflowSection(), prefs);

    expect(find.text('还没有本地工作流'), findsOneWidget);
  });

  testWidgets('设置页工作流存储：显示合计占用与每条占用，并提供删除', (tester) async {
    final prefs = await _prefsWithOneWorkflow();
    await _pump(tester, const WorkflowStorageView(), prefs);

    expect(find.textContaining('共 1 项 · 合计'), findsOneWidget);
    expect(find.text('我的写真'), findsOneWidget);
    expect(find.textContaining('来源 portrait_api.json'), findsOneWidget);
    expect(find.byIcon(Icons.delete_outline), findsOneWidget);
  });

  testWidgets('设置页工作流存储：删除后条目消失且 prefs 同步', (tester) async {
    final prefs = await _prefsWithOneWorkflow();
    await _pump(tester, const WorkflowStorageView(), prefs);

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();

    expect(find.text('我的写真'), findsNothing);
    expect(find.textContaining('本机还没有保存任何工作流'), findsOneWidget);
  });
}
