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

/// 长按浮起时，绿框**不能把段间距一起框进去**。
///
/// 回归背景（2026-10-29）：`proxyDecorator` 收到的 `child` **不是**
/// `_buildSection` 的返回值 —— Flutter 在交给 proxy 之前包了一层
/// `Semantics`（`reorderable_list.dart` 的 `_wrapWithSemantics`，
/// `_DragInfo.child = item.widget.child`）。
/// 所以 `child is Padding` 恒为 false，「把间距拆出来」那段代码从来没执行过，
/// 绿框底部一直多出 10dp（真机实测 33px @density 420），还会压住下一段顶部。
///
/// 这个 bug 光读代码看不出来：写法本身完全合理，错在「以为 child 是原始 widget」。
/// 断言用「绿框高度 == 卡片高度」而不是「绿框比 item 矮 10」，
/// 是为了让失败信息直接说明偏差多少。

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
  '1': {
    'class_type': 'UNETLoader',
    'inputs': {'unet_name': 'a.safetensors'},
    '_meta': {'title': 'UNet加载器'},
  },
  '2': {
    'class_type': 'VAELoader',
    'inputs': {'vae_name': 'b.safetensors'},
    '_meta': {'title': '加载VAE'},
  },
};

List<Map<String, dynamic>> _mappingConfig() => [
  {
    'id': '1',
    'classType': 'UNETLoader',
    'key': 'unet_name',
    'alias': 'UNet 模型',
    'exposed': true,
    'title': 'UNet加载器',
    'paramType': 'text',
    'options': <String>[],
    'value': 'a.safetensors',
    'control': 'text',
  },
  {
    'id': '2',
    'classType': 'VAELoader',
    'key': 'vae_name',
    'alias': 'VAE 模型',
    'exposed': true,
    'title': '加载VAE',
    'paramType': 'text',
    'options': <String>[],
    'value': 'b.safetensors',
    'control': 'text',
  },
];

void _installServer() {
  final previous = ObjectInfoService.instance.client;
  ObjectInfoService.instance.client = MockClient(
    (_) async => http.Response('{}', 200),
  );
  addTearDown(() => ObjectInfoService.instance.client = previous);
}

Future<void> _pumpConfig(WidgetTester tester) async {
  // 手机竖屏尺寸：默认 800×600 太宽，卡片会挤成一行，量出来的高度没有代表性
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.625;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

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
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  group('配置页拖动浮起项', () {
    testWidgets('绿框只包卡片本体，不把段间距框进去', (tester) async {
      _installServer();
      await _pumpConfig(tester);

      final sectionKey = find.byKey(const ValueKey('param-section-1'));
      expect(sectionKey, findsOneWidget);

      // 静止时卡片本体的高度（这段间距是一段 Padding，不在 Card 里）
      final cardSize = tester.getSize(
        find.descendant(of: sectionKey, matching: find.byType(Card)),
      );
      final itemSize = tester.getSize(sectionKey);
      // 自证脚手架是对的：item 比卡片高出正好一段间距
      expect(itemSize.height, greaterThan(cardSize.height));

      // 长按 300ms 才会起拖（ParamDragStartListener 的延迟），再微移一点让代理出现
      final gesture = await tester.startGesture(tester.getCenter(sectionKey));
      await tester.pump(const Duration(milliseconds: 400));
      await gesture.moveBy(const Offset(0, 40));
      await tester.pump();

      final proxy = find.byKey(const ValueKey('param-drag-proxy'));
      expect(proxy, findsOneWidget, reason: '长按后应出现浮起代理');

      final proxySize = tester.getSize(proxy);
      // 绿框自己有一圈 1.5dp 描边（上下各一条），这是设计的一部分，不算问题。
      // 允许的差值只能是它；一旦把 10dp 段间距框进来，差值会变成 13 起步。
      const proxyBorder = 1.5 * 2;
      expect(
        proxySize.height,
        moreOrLessEquals(cardSize.height + proxyBorder, epsilon: 0.5),
        reason:
            '绿框 ${proxySize.height} vs 卡片 ${cardSize.height}'
            '（允许 +$proxyBorder 描边）：差值超出就是段间距被框进来了',
      );

      await gesture.up();
      await tester.pumpAndSettle();
    });
  });
}
