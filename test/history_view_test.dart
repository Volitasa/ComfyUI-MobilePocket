import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:comfyui_mobilepocket/providers/connection_provider.dart';
import 'package:comfyui_mobilepocket/ui/gallery/history_view.dart';

/// 用给定的历史记录构建 HistoryView。
/// 历史通过 SharedPreferences 注入，TaskManager 在 build 时自行读取。
Future<void> _pumpHistory(
  WidgetTester tester,
  List<Map<String, dynamic>> history,
) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('comfy_task_history', jsonEncode(history));

  await tester.pumpWidget(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const MaterialApp(home: HistoryView()),
    ),
  );
  // 不用 pumpAndSettle：连接状态徽标可能带常驻动画，会一直等到超时
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

Map<String, dynamic> _task({
  required String status,
  required String promptId,
  List<Map<String, dynamic>> images = const [],
  String nodeInfo = '',
  int progressValue = 0,
  int progressMax = 0,
}) {
  return {
    'promptId': promptId,
    'workflowId': 'ComfyUI_01010__api.json',
    'title': 'ComfyUI_01010_',
    'status': status,
    'progressValue': progressValue,
    'progressMax': progressMax,
    'nodeInfo': nodeInfo,
    'images': images,
    'timestamp': 1791579799776,
    'serverId': 'srv_test',
  };
}

void main() {
  group('HistoryView 无输出时的缩略图占位', () {
    testWidgets('已失败记录不再显示加载动画，改为错误图标', (tester) async {
      await _pumpHistory(tester, [
        _task(status: '已失败', promptId: 'p-failed', nodeInfo: "❌ 执行出错: 'NextDiT' object has no attribute 'patch'"),
      ]);

      // 关键断言：失败是终态，不能继续转圈
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      // 终态也不该留着永远不动的进度条
      expect(find.byType(LinearProgressIndicator), findsNothing);
      // 状态文案仍然是失败
      expect(find.textContaining('已失败'), findsOneWidget);
    });

    testWidgets('已中断记录不显示加载动画', (tester) async {
      await _pumpHistory(tester, [
        _task(status: '已中断', promptId: 'p-interrupted', nodeInfo: '⏹️ 任务已被中断'),
      ]);

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byIcon(Icons.remove_circle_outline), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });

    testWidgets('已完成但无图的记录显示“无图”', (tester) async {
      await _pumpHistory(tester, [
        _task(status: '已完成', promptId: 'p-done', nodeInfo: '✅ 生成成功'),
      ]);

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('无图'), findsOneWidget);
    });

    testWidgets('生成中的记录仍然显示加载动画与进度条', (tester) async {
      await _pumpHistory(tester, [
        _task(
          status: '生成中',
          promptId: 'p-running',
          nodeInfo: '🔄 K采样器 · 80%',
          progressValue: 8,
          progressMax: 10,
        ),
      ]);

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsNothing);
    });
  });
}
