import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:comfyui_mobilepocket/providers/connection_provider.dart';
import 'package:comfyui_mobilepocket/providers/workflow_provider.dart';
import 'package:comfyui_mobilepocket/ui/home/remote_workflow_section.dart';

/// 已连接的连接状态（不真的去探测服务器）
class _ConnectedFake extends ConnectionNotifier {
  @override
  ConfigState build() {
    final base = super.build();
    return base.copyWith(isConnected: true, comfyUrl: 'http://127.0.0.1:8190');
  }
}

/// 带指定工作流列表的状态（不真的去请求服务器）
class _ListedFake extends WorkflowNotifier {
  final List<String> api;
  final List<String> ui;

  _ListedFake(this.api, this.ui);

  @override
  WorkflowState build() {
    final base = super.build();
    return base.copyWith(workflowList: api, uiWorkflowList: ui);
  }
}

Future<SharedPreferences> _prefs() async {
  SharedPreferences.setMockInitialValues({});
  return SharedPreferences.getInstance();
}

Future<void> _pump(
  WidgetTester tester, {
  required List<String> api,
  required List<String> ui,
  bool connected = true,
}) async {
  final prefs = await _prefs();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        if (connected) connectionProvider.overrideWith(_ConnectedFake.new),
        workflowProvider.overrideWith(() => _ListedFake(api, ui)),
      ],
      child: const MaterialApp(home: Scaffold(body: RemoteWorkflowSection())),
    ),
  );
  await tester.pump();
}

void main() {
  group('工作流文件分类', () {
    test('_api.json 归为 API 工作流', () {
      expect(isApiWorkflowFile('基础文生图_api.json'), isTrue);
      expect(isUiWorkflowFile('基础文生图_api.json'), isFalse);
    });

    test('普通 .json 归为 UI 工作流', () {
      expect(isUiWorkflowFile('基础文生图.json'), isTrue);
      expect(isApiWorkflowFile('基础文生图.json'), isFalse);
    });

    test('非 json 文件两边都不算', () {
      expect(isWorkflowFile('readme.txt'), isFalse);
      expect(isUiWorkflowFile('readme.txt'), isFalse);
    });
  });

  testWidgets('两类工作流分别成组，UI 组标注尚未解析', (tester) async {
    await _pump(
      tester,
      api: ['基础文生图_api.json', 'upscale_api.json'],
      ui: ['基础文生图.json', '测试1.json'],
    );

    expect(find.text('API 工作流 · 可直接运行'), findsOneWidget);
    expect(find.text('UI 工作流 · 需解析'), findsOneWidget);
    // 文件名去掉后缀
    expect(find.text('基础文生图'), findsNWidgets(2));
    expect(find.text('upscale'), findsOneWidget);
    // UI 条目明确标注还不能用
    expect(find.text('尚未解析 · 暂不可运行'), findsNWidgets(2));
  });

  testWidgets('没有 UI 工作流时不显示 UI 分组', (tester) async {
    await _pump(tester, api: ['基础文生图_api.json'], ui: const []);

    expect(find.text('API 工作流 · 可直接运行'), findsOneWidget);
    expect(find.text('UI 工作流 · 需解析'), findsNothing);
  });

  testWidgets('两个列表都为空时显示空态', (tester) async {
    await _pump(tester, api: const [], ui: const []);

    expect(find.text('未找到工作流'), findsOneWidget);
  });

  testWidgets('未连接时显示连接引导', (tester) async {
    await _pump(
      tester,
      api: ['基础文生图_api.json'],
      ui: const [],
      connected: false,
    );

    expect(find.text('尚未连接到服务器'), findsOneWidget);
    expect(find.text('API 工作流 · 可直接运行'), findsNothing);
  });
}
