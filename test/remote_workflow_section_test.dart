import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:comfyui_mobilepocket/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:comfyui_mobilepocket/models/parsed_workflow.dart';
import 'package:comfyui_mobilepocket/providers/connection_provider.dart';
import 'package:comfyui_mobilepocket/providers/parsed_workflow_provider.dart';
import 'package:comfyui_mobilepocket/providers/workflow_provider.dart';
import 'package:comfyui_mobilepocket/ui/home/remote_workflow_section.dart';
import 'package:comfyui_mobilepocket/utils.dart';

/// 已连接的连接状态（不真的去探测服务器）
class _ConnectedFake extends ConnectionNotifier {
  @override
  ConfigState build() {
    final base = super.build();
    return base.copyWith(
      isConnected: true,
      comfyUrl: 'http://127.0.0.1:8190',
      activeServerId: 'srv1',
    );
  }
}

/// 带指定工作流列表的状态（不真的去请求服务器）
class _ListedFake extends WorkflowNotifier {
  final List<String> api;
  final List<String> ui;
  final Map<String, UiWorkflowStatus> uiStatuses;

  _ListedFake(this.api, this.ui, [this.uiStatuses = const {}]);

  @override
  WorkflowState build() {
    final base = super.build();
    return base.copyWith(
      workflowList: api,
      uiWorkflowList: ui,
      uiStatuses: uiStatuses,
    );
  }
}

Future<SharedPreferences> _prefs([Map<String, Object> seed = const {}]) async {
  SharedPreferences.setMockInitialValues(seed);
  return SharedPreferences.getInstance();
}

/// 一份落在 srv1 上的解析缓存，id 与 provider 的推导规则保持一致
ParsedWorkflow _cached(String filename) => ParsedWorkflow(
      id: ParsedWorkflowNotifier.buildId('srv1', filename),
      serverId: 'srv1',
      filename: filename,
      name: uiWorkflowTitle(filename),
      sourceHash: 'h',
      parsedAt: 0,
      workflowJson: const {
        '3': {
          'inputs': {'seed': 1, 'steps': 20},
          'class_type': 'KSampler',
        },
      },
    );

Future<void> _pump(
  WidgetTester tester, {
  required List<String> api,
  required List<String> ui,
  bool connected = true,
  Map<String, UiWorkflowStatus> uiStatuses = const {},
  List<ParsedWorkflow> cached = const [],
}) async {
  final prefs = await _prefs({
    if (cached.isNotEmpty)
      parsedWorkflowsPrefsKey: jsonEncode(cached.map((e) => e.toJson()).toList()),
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        if (connected) connectionProvider.overrideWith(_ConnectedFake.new),
        workflowProvider.overrideWith(() => _ListedFake(api, ui, uiStatuses)),
      ],
      child: MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: RemoteWorkflowSection()),
      ),
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
    // UI 条目明确标注还没解析，现在可以点击触发解析了
    expect(find.text('尚未解析 · 点击解析'), findsNWidgets(2));
  });

  testWidgets('已解析且内容未变时显示已解析', (tester) async {
    await _pump(
      tester,
      api: const [],
      ui: ['基础文生图.json'],
      uiStatuses: const {'基础文生图.json': UiWorkflowStatus.parsed},
      cached: [_cached('基础文生图.json')],
    );

    expect(find.text('已解析'), findsOneWidget);
    expect(find.text('尚未解析 · 点击解析'), findsNothing);
  });

  testWidgets('服务器内容有更新时提示可重新解析', (tester) async {
    await _pump(
      tester,
      api: const [],
      ui: ['基础文生图.json'],
      uiStatuses: const {'基础文生图.json': UiWorkflowStatus.stale},
      cached: [_cached('基础文生图.json')],
    );

    expect(find.text('服务器有更新，可重新解析'), findsOneWidget);
  });

  testWidgets('已解析的条目可进入配置页，不再提示需解析', (tester) async {
    await _pump(
      tester,
      api: const [],
      ui: ['基础文生图.json'],
      uiStatuses: const {'基础文生图.json': UiWorkflowStatus.parsed},
      cached: [_cached('基础文生图.json')],
    );

    await tester.tap(find.text('基础文生图'));
    // 配置页里的进行中动效会让 pumpAndSettle 永远等不到静止，按需 pump 帧
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }

    // 走到配置页说明解析结果确实被当作可用工作流接进了下游
    expect(find.text('配置面板: 基础文生图'), findsOneWidget);
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
