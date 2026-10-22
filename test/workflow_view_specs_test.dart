import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:comfyui_mobilepocket/l10n/app_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:comfyui_mobilepocket/providers/connection_provider.dart';
import 'package:comfyui_mobilepocket/services/object_info_service.dart';
import 'package:comfyui_mobilepocket/ui/builder/workflow_view.dart';

/// 配置页的「降级提示」有没有误报。
///
/// 回归背景：`waitWithin` 原来返回 `T?`，而这里的 task 是 `Future<void>` ——
/// 成功完成的值就是 `null`，于是 `finished == null` 恒成立，
/// **所有工作流**都被标成「未获取到服务器节点信息，已按参数名推断控件」。
/// 光看代码看不出来，必须拿一个能正常返回说明书的假服务器盯住这个横幅。

const String _baseUrl = 'http://test.local:8190';

const String _degradedText = '未获取到服务器节点信息，已按参数名推断控件';

class _FakeConnectionNotifier extends ConnectionNotifier {
  @override
  ConfigState build() => ConfigState(
    servers: [ServerConfig(id: 'srv_1', name: '', primaryUrl: _baseUrl)],
    activeServerId: 'srv_1',
    comfyUrl: _baseUrl,
    isConnected: true,
  );
}

const Map<String, dynamic> _workflow = {
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

/// `type` 在工作流里只是一串字符（paramType 会被推断成 text），
/// 只有拿到说明书才知道它其实是下拉。
List<Map<String, dynamic>> _mappingConfig() => [
  {
    'id': '9',
    'classType': 'CLIPLoader',
    'key': 'type',
    'alias': '类型',
    'exposed': true,
    'title': '加载CLIP',
    'paramType': 'text',
    'options': <String>[],
    'value': 'lumina2',
  },
];

String _clipLoaderSpec() => jsonEncode({
  'CLIPLoader': {
    'input': {
      'required': {
        'type': [
          ['lumina2', 'qwen_image'],
          <String, dynamic>{},
        ],
        'device': [
          ['default', 'cpu'],
          <String, dynamic>{},
        ],
      },
    },
  },
});

/// 装一个假客户端；[delay] 用来模拟「预算用完了还没回来」。
void _installServer(
  String body, {
  int statusCode = 200,
  Duration delay = Duration.zero,
}) {
  final previous = ObjectInfoService.instance.client;
  ObjectInfoService.instance.client = MockClient((_) async {
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    return http.Response(body, statusCode);
  });
  addTearDown(() => ObjectInfoService.instance.client = previous);
}

Future<SharedPreferences> _pumpConfig(WidgetTester tester) async {
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
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        connectionProvider.overrideWith(() => _FakeConnectionNotifier()),
      ],
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
  return prefs;
}

void main() {
  testWidgets('说明书取到了 → 不显示降级提示，且控件按说明书定型', (tester) async {
    _installServer(_clipLoaderSpec());
    await _pumpConfig(tester);

    expect(find.text(_degradedText), findsNothing);

    // 定型生效的证据：`type` 的摘要写「类型: 选项」而不是「类型: 文本」
    expect(find.textContaining('类型: 选项'), findsWidgets);
    expect(find.textContaining('类型: 文本'), findsNothing);
  });

  testWidgets('保存后 control 真的落盘 —— 运行页才用得上', (tester) async {
    // C2 的 `_parseWorkflow` 曾经漏传 `specs`：说明书取到了、只用来算「缺参数」
    // 标黄，`control` / `bounds` 一个都没写。配置页看着正常（还误标降级），
    // 但保存下来的配置里根本没有 `control`，运行页退回全量推断。
    _installServer(_clipLoaderSpec());
    final prefs = await _pumpConfig(tester);

    await tester.ensureVisible(find.text('保存表单配置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存表单配置'));
    await tester.pumpAndSettle();

    final snaps =
        jsonDecode(prefs.getString('comfy_workflow_snapshots')!) as List;
    final nodes = (snaps.first as Map)['mappingConfig'] as List;
    Map<String, dynamic> byKey(String key) =>
        nodes.cast<Map>().firstWhere((n) => n['key'] == key)
            as Map<String, dynamic>;

    // 两个都是说明书里的 COMBO → 应该被定型成下拉
    expect(byKey('type')['control'], 'select');
    expect(byKey('device')['control'], 'select');
  });

  testWidgets('取数全部失败 → 显示降级提示', (tester) async {
    _installServer('boom', statusCode: 500);
    await _pumpConfig(tester);

    expect(find.text(_degradedText), findsOneWidget);
  });

  testWidgets('服务器不认识这个节点（200 + {}）→ 显示降级提示', (tester) async {
    _installServer('{}');
    await _pumpConfig(tester);

    expect(find.text(_degradedText), findsOneWidget);
  });

  testWidgets('超出 2 秒预算 → 先按推断定型并提示降级', (tester) async {
    // 3 秒才回：预算（2 秒）用完时一个说明书都没有
    _installServer(_clipLoaderSpec(), delay: const Duration(seconds: 3));
    await _pumpConfig(tester);

    // 预算内还没超时，先不该提示
    expect(find.text(_degradedText), findsNothing);

    await tester.pump(const Duration(seconds: 2));
    expect(find.text(_degradedText), findsOneWidget);
    // 超时即定型：控件按 paramType 推断，`type` 是文本
    expect(find.textContaining('类型: 文本'), findsWidgets);

    // 把在飞的那次请求等完，别留下未结束的定时器
    await tester.pump(const Duration(seconds: 4));
  });
}
