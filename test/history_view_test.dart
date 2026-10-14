import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:comfyui_mobilepocket/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:comfyui_mobilepocket/providers/connection_provider.dart';
import 'package:comfyui_mobilepocket/theme.dart';
import 'package:comfyui_mobilepocket/ui/gallery/history_view.dart';

/// 用给定的历史记录构建 HistoryView。
/// 历史通过 SharedPreferences 注入，TaskManager 在 build 时自行读取。
Future<void> _pumpHistory(
  WidgetTester tester,
  List<Map<String, dynamic>> history, {
  List<Map<String, dynamic>> snapshots = const [],
  // 默认按中文渲染；传 en 可验证英文分支（防止翻译漏接）
  Locale locale = const Locale('zh'),
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('comfy_task_history', jsonEncode(history));
  if (snapshots.isNotEmpty) {
    await prefs.setString('comfy_workflow_snapshots', jsonEncode(snapshots));
  }

  await tester.pumpWidget(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const HistoryView(),
      ),
    ),
  );
  // 不用 pumpAndSettle：连接状态徽标可能带常驻动画，会一直等到超时
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

/// [nodeInfo] 只用来模拟旧版本数据（整句中文）；新数据走 nodePhase/nodeDetail。
Map<String, dynamic> _task({
  required String status,
  required String promptId,
  List<Map<String, dynamic>> images = const [],
  String nodeInfo = '',
  String? nodePhase,
  String nodeDetail = '',
  int progressValue = 0,
  int progressMax = 0,
  String? snapshotId,
}) {
  return {
    'promptId': promptId,
    'workflowId': 'ComfyUI_01010__api.json',
    'title': 'ComfyUI_01010_',
    'status': status,
    'progressValue': progressValue,
    'progressMax': progressMax,
    // null-aware element：为 null 时整个键不出现在 map 里
    'nodePhase': ?nodePhase,
    // 旧版本数据没有 nodeDetail 键（详情藏在 nodeInfo 整句里）；
    // 只有显式传入才写这个键，否则空串会挡住 _migrateDetail 的旧数据迁移
    if (nodeDetail.isNotEmpty) 'nodeDetail': nodeDetail,
    'nodeInfo': nodeInfo,
    'images': images,
    'timestamp': 1791579799776,
    'serverId': 'srv_test',
    // null-aware element：snapshotId 为 null 时整个键不出现在 map 里
    'snapshotId': ?snapshotId,
  };
}

void main() {
  group('HistoryView 无输出时的缩略图占位', () {
    testWidgets('已失败记录不再显示加载动画，改为错误图标', (tester) async {
      await _pumpHistory(tester, [
        _task(
          status: 'failed',
          promptId: 'p-failed',
          nodePhase: 'error',
          // 服务端错误原文：只存原始值，不掺展示文案
          nodeDetail: "'NextDiT' object has no attribute 'patch'",
        ),
      ]);

      // 关键断言：失败是终态，不能继续转圈
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      // 终态也不该留着永远不动的进度条
      expect(find.byType(LinearProgressIndicator), findsNothing);
      // 状态文案仍然是失败，且错误原文原样透出
      expect(find.textContaining('已失败'), findsOneWidget);
      expect(find.textContaining("attribute 'patch'"), findsOneWidget);
    });

    testWidgets('已中断记录不显示加载动画', (tester) async {
      await _pumpHistory(tester, [
        _task(
          status: 'interrupted',
          promptId: 'p-interrupted',
          nodePhase: 'interrupted',
        ),
      ]);

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byIcon(Icons.remove_circle_outline), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });

    testWidgets('已完成但无图的记录显示“无图”', (tester) async {
      await _pumpHistory(tester, [
        _task(status: 'completed', promptId: 'p-done', nodePhase: 'done'),
      ]);

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('无图'), findsOneWidget);
    });

    testWidgets('生成中的记录仍然显示加载动画与进度条', (tester) async {
      await _pumpHistory(tester, [
        _task(
          status: 'running',
          promptId: 'p-running',
          nodePhase: 'running',
          nodeDetail: 'K采样器',
          progressValue: 8,
          progressMax: 10,
        ),
      ]);

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsNothing);
    });
  });

  group('英文分支冒烟', () {
    testWidgets('英文界面下空态走英文文案', (tester) async {
      await _pumpHistory(tester, [], locale: const Locale('en'));

      expect(find.text('No history yet'), findsOneWidget);
      expect(find.text('暂无生成记录'), findsNothing);
    });

    testWidgets('英文界面下状态文案走英文', (tester) async {
      await _pumpHistory(tester, [
        _task(status: 'failed', promptId: 'p-en-failed'),
      ], locale: const Locale('en'));

      // 卡片上的状态行形如「Failed · ...」
      expect(find.textContaining('Failed'), findsOneWidget);
      expect(find.textContaining('已失败'), findsNothing);
    });
  });

  group('旧版本中文数据的迁移', () {
    testWidgets('中文状态能映射回枚举，错误详情从整句里捞回来', (tester) async {
      await _pumpHistory(tester, [
        _task(
          status: '已失败',
          promptId: 'p-legacy',
          // 旧格式：只有一整句中文
          nodeInfo: "❌ 执行出错: 'NextDiT' object has no attribute 'patch'",
        ),
      ]);

      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(find.textContaining('已失败'), findsOneWidget);
      expect(find.textContaining("attribute 'patch'"), findsOneWidget);
    });

    testWidgets('中文「已完成」按终态处理，不再转圈', (tester) async {
      await _pumpHistory(tester, [
        _task(status: '已完成', promptId: 'p-legacy-done', nodeInfo: '✅ 生成成功'),
      ]);

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('无图'), findsOneWidget);
    });
  });

  group('HistoryView 再次运行', () {
    testWidgets('快照存在时按钮为正常色；快照被删后置灰', (tester) async {
      final snap = {
        'id': 'snap_ok',
        'displayName': '基础文生图 · 10-11 20:00',
        'sourceName': '基础文生图',
        'createdAt': 1791579799776,
        'serverId': 'srv_test',
        'workflowJson': {
          '1': {
            'inputs': {'text': 'a cat'},
            'class_type': 'CLIPTextEncode',
          },
        },
        'mappingConfig': [],
      };

      // 有快照：按钮应是可用色，而不是置灰
      await _pumpHistory(
        tester,
        [
          _task(
            status: 'completed',
            promptId: 'p-ok',
            nodePhase: 'done',
            snapshotId: 'snap_ok',
          ),
        ],
        snapshots: [snap],
      );
      expect(
        tester.widget<Icon>(find.byIcon(Icons.replay)).color,
        AppColors.success,
      );

      // 快照被手动删除（记录里仍留着 snapshotId）：必须置灰
      await _pumpHistory(tester, [
        _task(
          status: 'completed',
          promptId: 'p-gone',
          nodePhase: 'done',
          snapshotId: 'snap_gone',
        ),
      ]);
      expect(
        tester.widget<Icon>(find.byIcon(Icons.replay)).color,
        Colors.grey.shade400,
      );
    });

    testWidgets('无快照的旧记录点击会说明原因，而不是静默无反应', (tester) async {
      await _pumpHistory(tester, [
        _task(status: 'completed', promptId: 'p-legacy', nodePhase: 'done'),
      ]);

      await tester.tap(find.byIcon(Icons.replay));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('这条记录没有工作流快照（旧版本生成），无法再次运行'), findsOneWidget);
    });

    testWidgets('快照已被删除的记录点击会说明原因', (tester) async {
      await _pumpHistory(tester, [
        _task(
          status: 'completed',
          promptId: 'p-gone',
          nodePhase: 'done',
          snapshotId: 'snap_deleted',
        ),
      ]);

      await tester.tap(find.byIcon(Icons.replay));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('对应的工作流快照已被删除，无法再次运行'), findsOneWidget);
    });
  });
}
