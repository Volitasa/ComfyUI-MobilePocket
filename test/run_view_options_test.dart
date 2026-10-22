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

const String _baseUrl = 'http://test.local:8190';

/// 造一份「已连接」的连接状态。
///
/// 连接状态是运行期的（不落盘），没法靠注入 prefs 造出来，
/// 所以这里直接换掉 build 的结果。
class _FakeConnectionNotifier extends ConnectionNotifier {
  @override
  ConfigState build() => ConfigState(
    servers: [ServerConfig(id: 'srv_1', name: '', primaryUrl: _baseUrl)],
    activeServerId: 'srv_1',
    comfyUrl: _baseUrl,
    isConnected: true,
  );
}

/// 形态 A 的 COMBO 响应
String _comboBody(String classType, String key, List<String> options) =>
    jsonEncode({
      classType: {
        'input': {
          'required': {
            key: [options, <String, dynamic>{}],
          },
        },
      },
    });

const Map<String, dynamic> _workflow = {
  '4': {
    'class_type': 'CheckpointLoaderSimple',
    'inputs': {'ckpt_name': 'old.safetensors'},
  },
  '3': {
    'class_type': 'KSampler',
    'inputs': {
      'seed': 1,
      'steps': 20,
      'sampler_name': 'euler',
      'scheduler': 'normal',
    },
  },
};

/// 快照里存的配置：模型用了一个服务器上没有的名字
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
    'key': 'sampler_name',
    'alias': '采样器',
    'exposed': true,
    'title': '',
    'paramType': 'enumType',
    'options': ['euler'],
    'value': 'euler',
  },
];

/// 假服务器：问什么节点就回什么节点的选项
void _installServer(Map<String, String> bodies, [List<String>? log]) {
  final previous = ObjectInfoService.instance.client;
  ObjectInfoService.instance.client = MockClient((req) async {
    log?.add(req.url.path);
    final name = req.url.pathSegments.isEmpty
        ? ''
        : Uri.decodeComponent(req.url.pathSegments.last);
    return http.Response(bodies[name] ?? '{}', 200);
  });
  addTearDown(() => ObjectInfoService.instance.client = previous);
}

/// 表单里只有一个提示词、没有模型下拉时用的配置
List<Map<String, dynamic>> _textOnlyConfig() => [
  {
    'id': '6',
    'classType': 'CLIPTextEncode',
    'key': 'text',
    'alias': '正向提示词',
    'exposed': true,
    'title': '',
    'paramType': 'text',
    'options': <String>[],
    'value': 'a cat',
  },
];

Future<void> _pumpRunView(
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
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        connectionProvider.overrideWith(() => _FakeConnectionNotifier()),
      ],
      child: MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: RunView(workflowId: 'local_test', snapshotId: 'snap_1'),
      ),
    ),
  );
  // 页面进 initState 时会把数据与下拉请求推到下一个事件循环，多泵几次
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  group('运行页：下拉取服务器真实选项', () {
    testWidgets('进页面后，下拉里换成服务器上的真实模型', (tester) async {
      _installServer({
        'CheckpointLoaderSimple': _comboBody(
          'CheckpointLoaderSimple',
          'ckpt_name',
          ['a.safetensors', 'b.safetensors'],
        ),
        'KSampler': _comboBody('KSampler', 'sampler_name', ['euler', 'heun']),
      });

      await _pumpRunView(tester);

      // 点开模型下拉：里面只有服务器上的两个，工作流里那个不再出现
      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      expect(find.text('a.safetensors'), findsWidgets);
      expect(find.text('b.safetensors'), findsWidgets);
      expect(find.text('old.safetensors'), findsNothing);

      // 打开的是模型那个下拉（节点 4），采样器在后面。
      // 关掉菜单再验证采样器那一个保留了正常选中值。
      await tester.tap(find.text('a.safetensors').last);
      await tester.pumpAndSettle();
      expect(find.text('a.safetensors'), findsWidgets);
    });

    testWidgets('工作流里的模型服务器没有 → 标注出来，且不混进下拉选项里', (tester) async {
      _installServer({
        'CheckpointLoaderSimple': _comboBody(
          'CheckpointLoaderSimple',
          'ckpt_name',
          ['a.safetensors'],
        ),
        'KSampler': _comboBody('KSampler', 'sampler_name', ['euler', 'heun']),
      });

      await _pumpRunView(tester);

      expect(find.text('服务器没有此模型'), findsOneWidget);
      // 采样器在服务器上存在，不该被误报
      expect(find.text('采样器'), findsOneWidget);
    });

    testWidgets('模型没选时提交会被拦下，不让必然失败的请求发出去', (tester) async {
      _installServer({
        'CheckpointLoaderSimple': _comboBody(
          'CheckpointLoaderSimple',
          'ckpt_name',
          ['a.safetensors'],
        ),
        'KSampler': _comboBody('KSampler', 'sampler_name', ['euler', 'heun']),
      });

      await _pumpRunView(tester);

      await tester.tap(find.text('立即生成'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('请先选择模型'), findsOneWidget);
    });

    testWidgets('选过一个真实模型后，标注消失', (tester) async {
      _installServer({
        'CheckpointLoaderSimple': _comboBody(
          'CheckpointLoaderSimple',
          'ckpt_name',
          ['a.safetensors', 'b.safetensors'],
        ),
        'KSampler': _comboBody('KSampler', 'sampler_name', ['euler', 'heun']),
      });

      await _pumpRunView(tester);
      expect(find.text('服务器没有此模型'), findsOneWidget);

      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('b.safetensors').last);
      await tester.pumpAndSettle();

      expect(find.text('服务器没有此模型'), findsNothing);
      expect(find.text('b.safetensors'), findsWidgets);
    });

    testWidgets('拿不到服务器数据时退回原样：还是工作流里那个值，也不乱标缺失', (tester) async {
      // 服务器一律返回 500：等于我们什么都不知道
      final previous = ObjectInfoService.instance.client;
      ObjectInfoService.instance.client = MockClient(
        (_) async => http.Response('boom', 500),
      );
      addTearDown(() => ObjectInfoService.instance.client = previous);

      await _pumpRunView(tester);

      expect(find.text('服务器没有此模型'), findsNothing);
      // 退回现状：下拉里仍是工作流自带的那个值
      expect(find.text('old.safetensors'), findsOneWidget);
    });

    testWidgets('刷新按钮：有模型下拉才出现，点一下重新问一次服务器', (tester) async {
      final requests = <String>[];
      _installServer({
        'CheckpointLoaderSimple': _comboBody(
          'CheckpointLoaderSimple',
          'ckpt_name',
          ['a.safetensors'],
        ),
        'KSampler': _comboBody('KSampler', 'sampler_name', ['euler']),
      }, requests);

      await _pumpRunView(tester);

      // 两个节点各问一次
      expect(requests.length, 2);
      expect(find.byTooltip('刷新模型列表'), findsOneWidget);

      await tester.tap(find.byTooltip('刷新模型列表'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(requests.length, 4);
      expect(find.text('已刷新'), findsOneWidget);
    });

    testWidgets('表单里没有模型下拉时不摆刷新按钮', (tester) async {
      final requests = <String>[];
      _installServer({}, requests);

      await _pumpRunView(tester, mapping: _textOnlyConfig());

      expect(find.byTooltip('刷新模型列表'), findsNothing);
      // 也不该为了填提示词去问服务器
      expect(requests, isEmpty);
    });
  });

  group('运行页：数值范围提示', () {
    /// 形态：INT + min/max 元数据
    String intRangeBody(String classType, String key, int min, int max) =>
        jsonEncode({
          classType: {
            'input': {
              'required': {
                key: [
                  'INT',
                  {'default': 20, 'min': min, 'max': max},
                ],
              },
            },
          },
        });

    List<Map<String, dynamic>> stepsOnlyConfig() => [
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

    // 上界超过 1e9：能校验，但不画滑块（种子类参数就是这种）
    const bigMax = 2000000000;

    testWidgets('超出服务器范围 → 输入框下方红字提示', (tester) async {
      _installServer({
        'KSampler': intRangeBody('KSampler', 'steps', 1, bigMax),
      });
      await _pumpRunView(tester, mapping: stepsOnlyConfig());

      await tester.enterText(find.byType(TextField).first, '9999999999');
      await tester.pump();

      expect(find.text('范围 1 – 2000000000'), findsOneWidget);
    });

    testWidgets('不是数字 → 提示请输入数字', (tester) async {
      _installServer({
        'KSampler': intRangeBody('KSampler', 'steps', 1, bigMax),
      });
      await _pumpRunView(tester, mapping: stepsOnlyConfig());

      await tester.enterText(find.byType(TextField).first, 'abc');
      await tester.pump();

      expect(find.text('请输入数字'), findsOneWidget);
    });

    testWidgets('只提示、不拦提交：生成按钮仍然可点', (tester) async {
      _installServer({
        'KSampler': intRangeBody('KSampler', 'steps', 1, bigMax),
      });
      await _pumpRunView(tester, mapping: stepsOnlyConfig());

      await tester.enterText(find.byType(TextField).first, '9999999999');
      await tester.pump();

      expect(find.text('范围 1 – 2000000000'), findsOneWidget);
      // 放行：按钮不能因为越界就被禁用
      expect(
        find.byWidgetPredicate((w) => w is FilledButton && w.onPressed != null),
        findsOneWidget,
      );
    });

    testWidgets('拿不到说明书 → 不显示任何范围提示', (tester) async {
      _installServer({'KSampler': '{}'});
      await _pumpRunView(tester, mapping: stepsOnlyConfig());

      await tester.enterText(find.byType(TextField).first, '999');
      await tester.pump();

      expect(find.text('范围'), findsNothing);
      expect(find.text('请输入数字'), findsNothing);
    });

    testWidgets('范围可信（1–100）→ 画成滑块，数值仍可手改', (tester) async {
      _installServer({'KSampler': intRangeBody('KSampler', 'steps', 1, 100)});
      await _pumpRunView(tester, mapping: stepsOnlyConfig());

      expect(find.byType(Slider), findsOneWidget);
      // 初值 20 显示在滑块右侧的数值框里
      expect(find.text('20'), findsWidgets);
    });
  });

  group('运行页：密度与卡片', () {
    String intRangeBody(String classType, String key, int min, int max) =>
        jsonEncode({
          classType: {
            'input': {
              'required': {
                key: [
                  'INT',
                  {'default': 20, 'min': min, 'max': max},
                ],
              },
            },
          },
        });

    List<Map<String, dynamic>> oneParam(
      String key,
      String alias,
      String paramType,
      dynamic value,
    ) => [
      {
        'id': '3',
        'classType': 'KSampler',
        'key': key,
        'alias': alias,
        'exposed': true,
        'title': '',
        'paramType': paramType,
        'options': <String>[],
        'value': value,
      },
    ];

    testWidgets('布尔参数与别名同一行', (tester) async {
      await _pumpRunView(
        tester,
        mapping: oneParam('enabled', '启用高清修复', 'boolType', true),
      );

      expect(find.byType(Switch), findsOneWidget);
      // 旧的 SwitchListTile 会自己带一行「开启 / 关闭」标题，白白多占 40px
      expect(find.byType(SwitchListTile), findsNothing);

      // 同一行：别名与开关的中心点在同一高度上
      final aliasY = tester.getCenter(find.text('启用高清修复')).dy;
      final switchY = tester.getCenter(find.byType(Switch)).dy;
      expect((aliasY - switchY).abs(), lessThan(1.0));
    });

    testWidgets('随机种子只留图标，不再用带文字的按钮挤输入框', (tester) async {
      await _pumpRunView(tester, mapping: oneParam('seed', '随机种子', 'seed', 42));

      expect(find.byTooltip('随机'), findsOneWidget);
      // 按钮文字版会把输入框挤窄，现在只留图标（提示走 tooltip）
      expect(find.text('随机'), findsNothing);
    });

    testWidgets('滑块模式下手输越界也要提示', (tester) async {
      _installServer({'KSampler': intRangeBody('KSampler', 'steps', 1, 100)});
      await _pumpRunView(
        tester,
        mapping: oneParam('steps', '采样步数', 'intType', 20),
      );

      expect(find.byType(Slider), findsOneWidget);

      // 滑块拖不出范围，但右边的数值框能手输
      await tester.enterText(find.byType(TextField).first, '999');
      await tester.pump();

      expect(find.text('范围 1 – 100'), findsOneWidget);
    });

    testWidgets('节点多于一张卡时提供折叠全部', (tester) async {
      _installServer({});
      // 默认配置两个节点（大模型 + 采样器）
      await _pumpRunView(tester);

      expect(find.byTooltip('展开与折叠'), findsOneWidget);

      await tester.tap(find.byTooltip('展开与折叠'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('折叠全部'));
      await tester.pumpAndSettle();

      // 折叠后卡片里的控件都不在了，只剩卡头
      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    });
  });
}
