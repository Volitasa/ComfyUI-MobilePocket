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
import 'package:comfyui_mobilepocket/ui/builder/run_view.dart';

/// 提交前检查的**接线**测试：确认 `_handleExecute` 真的调了那次检查、
/// 并且把结果变成了用户看得见的一句话。
///
/// 判定规则本身在 `test/submit_check_test.dart` 里按纯函数测 —— 不放在这里，
/// 是因为「不拦」的那几条要走到真实提交，网络请求会把断言搅浑。

const String _baseUrl = 'http://test.local:8190';

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
  '4': {
    'class_type': 'GhostNode',
    'inputs': {'ckpt_name': 'old.safetensors'},
  },
};

Map<String, dynamic> _config() => {
  'id': '4',
  'classType': 'GhostNode',
  'key': 'ckpt_name',
  'alias': '大模型',
  'exposed': true,
  'title': '',
  'paramType': 'enumType',
  'options': ['old.safetensors'],
  'value': 'old.safetensors',
  'control': 'select',
};

void _installServer(String body) {
  final previous = ObjectInfoService.instance.client;
  ObjectInfoService.instance.client = MockClient(
    (_) async => http.Response(body, 200),
  );
  addTearDown(() => ObjectInfoService.instance.client = previous);
}

Future<void> _pumpRunView(WidgetTester tester) async {
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
        'mappingConfig': [_config()],
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
        home: const RunView(workflowId: 'local_test', snapshotId: 'snap_1'),
      ),
    ),
  );
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _tapGenerate(WidgetTester tester) async {
  await tester.tap(find.text('立即生成'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  group('运行页：提交前检查接线（方案 §3.7）', () {
    testWidgets('缺节点 → 弹「服务器缺少节点：<类名>」，不进提交态', (tester) async {
      _installServer('{}');
      await _pumpRunView(tester);

      await _tapGenerate(tester);

      expect(find.text('服务器缺少节点：GhostNode'), findsOneWidget);
      // 被拦下就不会进入提交态
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('缺选项 → 弹「<参数名> 的当前值…请重新选择」，不进提交态', (tester) async {
      _installServer(
        jsonEncode({
          'GhostNode': {
            'input': {
              'required': {
                'ckpt_name': [
                  ['a.safetensors', 'b.safetensors'],
                  <String, dynamic>{},
                ],
              },
            },
          },
        }),
      );
      await _pumpRunView(tester);

      await _tapGenerate(tester);

      expect(find.text('「大模型」的当前值服务器上没有，请重新选择'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });
}
