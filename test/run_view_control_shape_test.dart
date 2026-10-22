import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:comfyui_mobilepocket/l10n/app_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:comfyui_mobilepocket/providers/connection_provider.dart';
import 'package:comfyui_mobilepocket/providers/object_info_provider.dart';
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

String _comboBody(String classType, String key, List<Object?> options) =>
    jsonEncode({
      classType: {
        'input': {
          'required': {
            key: [options, <String, dynamic>{}],
          },
        },
      },
    });

String _specBody(String classType, Map<String, Object?> required) =>
    jsonEncode({
      classType: {
        'input': {'required': required},
      },
    });

/// 造一条配置。**`control` 由配置页写死**，运行页只读它。
Map<String, dynamic> _node({
  required String id,
  required String classType,
  required String key,
  required String alias,
  required String paramType,
  required String control,
  required dynamic value,
  List<String> options = const [],
}) => {
  'id': id,
  'classType': classType,
  'key': key,
  'alias': alias,
  'exposed': true,
  'title': '',
  'paramType': paramType,
  'options': options,
  'value': value,
  'control': control,
};

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
      'denoise': 1.0,
      'sampler_name': 'euler',
      'scheduler': 'normal',
    },
  },
  '5': {
    'class_type': 'EmptyLatentImage',
    'inputs': {'aspect_ratio': '1:1'},
  },
  '10': {
    'class_type': 'LoadImage',
    'inputs': {'image': 'x.png'},
  },
  '11': {
    'class_type': 'CLIPLoader',
    'inputs': {'type': 'cuda'},
  },
};

/// 可控假服务器：请求先挂起，等测试显式放行。
///
/// 这样才能观察到「请求还在飞」那一刻的界面 —— 也就是方案 §3.5 说的
/// 「首帧必须完整」到底成不成立。
class _Gate {
  _Gate(this.bodies);

  final Map<String, String> bodies;
  final List<String> requested = [];
  final List<_PendingRequest> _pending = [];

  void install() {
    final previous = ObjectInfoService.instance.client;
    ObjectInfoService.instance.client = MockClient((req) async {
      final name = req.url.pathSegments.isEmpty
          ? ''
          : Uri.decodeComponent(req.url.pathSegments.last);
      requested.add(name);
      final completer = Completer<http.Response>();
      _pending.add(_PendingRequest(name, completer));
      return completer.future;
    });
    addTearDown(() => ObjectInfoService.instance.client = previous);
  }

  int get pendingCount => _pending.length;

  /// 放行全部挂起请求；没有配说明书的一律回 `{}`（服务器不认识这个节点）。
  Future<void> release(WidgetTester tester) async {
    final pending = List<_PendingRequest>.from(_pending);
    _pending.clear();
    for (final p in pending) {
      p.completer.complete(http.Response(bodies[p.name] ?? '{}', 200));
    }
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }
}

class _PendingRequest {
  const _PendingRequest(this.name, this.completer);

  final String name;
  final Completer<http.Response> completer;
}

/// 只造一次 prefs：**同一个测试里第二次进页面要复用它**，
/// 否则说明书缓存会跟着 ProviderScope 一起被丢掉，就测不出「第二次还刷不刷」了。
Future<SharedPreferences> _seedPrefs(List<Map<String, dynamic>> mapping) async {
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
        'mappingConfig': mapping,
      },
    ]),
  );
  return prefs;
}

/// 换掉 `home`。换成不同类型时会把旧子树移除 —— 用它模拟「退出运行页」。
Future<void> _pumpHost(
  WidgetTester tester, {
  required SharedPreferences prefs,
  required Widget home,
}) async {
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
        home: home,
      ),
    ),
  );
  // 页面进 initState 时会把数据与下拉请求推到下一个事件循环，多泵几次
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _pumpRunView(
  WidgetTester tester, {
  required List<Map<String, dynamic>> mapping,
}) async {
  final prefs = await _seedPrefs(mapping);
  await _pumpHost(
    tester,
    prefs: prefs,
    home: const RunView(workflowId: 'local_test', snapshotId: 'snap_1'),
  );
}

void main() {
  group('运行页：形态只认 control（方案 §3.5）', () {
    testWidgets('请求还挂着，表单已经是完整的', (tester) async {
      final gate = _Gate({
        'CheckpointLoaderSimple': _comboBody(
          'CheckpointLoaderSimple',
          'ckpt_name',
          ['a.safetensors'],
        ),
        'KSampler': _comboBody('KSampler', 'sampler_name', ['euler']),
      })..install();

      await _pumpRunView(
        tester,
        mapping: [
          _node(
            id: '4',
            classType: 'CheckpointLoaderSimple',
            key: 'ckpt_name',
            alias: '大模型',
            paramType: 'enumType',
            control: 'select',
            value: 'old.safetensors',
            options: ['old.safetensors'],
          ),
          _node(
            id: '3',
            classType: 'KSampler',
            key: 'sampler_name',
            alias: '采样器',
            paramType: 'enumType',
            control: 'select',
            value: 'euler',
            options: ['euler'],
          ),
        ],
      );

      // 请求确实发出去了，而且一个都还没回来
      expect(gate.requested, hasLength(2));
      expect(gate.pendingCount, 2);

      // 但两个参数条都画出来了：别名在，下拉在
      expect(find.text('大模型'), findsOneWidget);
      expect(find.text('采样器'), findsOneWidget);
      expect(find.byType(DropdownButtonFormField<String>), findsNWidgets(2));

      // 没有任何「等网络」的转圈 / 占位
      expect(find.byType(CircularProgressIndicator), findsNothing);

      // 收尾放行：否则请求上挂着的 5 秒超时定时器会一直 pending，
      // 测试框架在树销毁后判为未结束的定时器，把整条用例拖挂。
      await gate.release(tester);
    });

    testWidgets('取数回来后，控件类型不随说明书变化', (tester) async {
      // 关键：说明书里 sampler_name 是 COMBO、steps 是 0–1（够格画滑块），
      // 但配置页当时把 sampler_name 定成了文本框、steps 定成了下拉。
      // 运行页必须照配置页的结论画，不能因为说明书回来了就变样。
      final gate = _Gate({
        'CheckpointLoaderSimple': _comboBody(
          'CheckpointLoaderSimple',
          'ckpt_name',
          ['a.safetensors'],
        ),
        'KSampler': _specBody('KSampler', {
          'sampler_name': [
            ['euler', 'heun'],
            <String, dynamic>{},
          ],
          'steps': [
            'INT',
            {'default': 20, 'min': 0, 'max': 1, 'step': 0.01},
          ],
        }),
      })..install();

      await _pumpRunView(
        tester,
        mapping: [
          _node(
            id: '4',
            classType: 'CheckpointLoaderSimple',
            key: 'ckpt_name',
            alias: '大模型',
            paramType: 'enumType',
            control: 'select',
            value: 'old.safetensors',
            options: ['old.safetensors'],
          ),
          _node(
            id: '3',
            classType: 'KSampler',
            key: 'sampler_name',
            alias: '采样器',
            paramType: 'text',
            control: 'text',
            value: 'euler',
          ),
          _node(
            id: '3',
            classType: 'KSampler',
            key: 'steps',
            alias: '步数',
            paramType: 'intType',
            control: 'select',
            value: 20,
          ),
        ],
      );

      // 首帧（请求还在飞）：1 个文本框 + 2 个下拉
      expect(find.byType(TextField), findsOneWidget);
      expect(find.byType(DropdownButtonFormField<String>), findsNWidgets(2));
      expect(find.byType(Slider), findsNothing);

      // 放行使请求返回
      await gate.release(tester);

      // 形态不变：sampler_name 仍是文本框（没被 COMBO 变成下拉），
      // steps 仍是下拉（没被 INT 变成输入框/滑块）
      expect(find.byType(TextField), findsOneWidget);
      expect(find.byType(DropdownButtonFormField<String>), findsNWidgets(2));
      expect(find.byType(Slider), findsNothing);
    });

    testWidgets('刷新回来的 bounds 不参与「滑块 / 输入框」判定', (tester) async {
      // 配置页定型时没拿到说明书 → denoise 落成了 number（输入框）。
      // 这次说明书回来了、范围是 0–1（本来够格画滑块），但形态只认 control。
      final gate = _Gate({
        'KSampler': _specBody('KSampler', {
          'denoise': [
            'FLOAT',
            {'default': 1.0, 'min': 0, 'max': 1, 'step': 0.01},
          ],
        }),
      })..install();

      await _pumpRunView(
        tester,
        mapping: [
          _node(
            id: '3',
            classType: 'KSampler',
            key: 'denoise',
            alias: '重绘幅度',
            paramType: 'float',
            control: 'number',
            value: 1.0,
          ),
        ],
      );

      expect(find.byType(Slider), findsNothing);
      expect(find.byType(TextField), findsOneWidget);

      await gate.release(tester);

      // 不给滑块 —— 否则档位数跨过阈值就会 number ↔ slider 来回跳
      expect(find.byType(Slider), findsNothing);
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('图片参数即使说明书说是 COMBO，也仍然是上传卡', (tester) async {
      // LoadImage.image 在服务器上确实声明成了 COMBO（一串 input 目录里的文件名），
      // 但它是图片上传位 —— 塞一个文件名下拉进去，用户就传不了新图了。
      final gate = _Gate({
        'LoadImage': _comboBody('LoadImage', 'image', ['x.png', 'y.png']),
      })..install();

      await _pumpRunView(
        tester,
        mapping: [
          _node(
            id: '10',
            classType: 'LoadImage',
            key: 'image',
            alias: '参考图',
            paramType: 'image',
            control: 'upload',
            value: 'x.png',
          ),
        ],
      );

      await gate.release(tester);

      expect(find.text('选择图片'), findsOneWidget);
      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    });

    testWidgets('type / device 的当前值不在服务器选项里也不拦提交', (tester) async {
      // `type` 在不同服务器版本上选项本就会变，全拦会大面积误伤 ——
      // §3.7 的「缺选项拦」只认模型 / 采样器类键。
      final gate = _Gate({
        'CLIPLoader': _comboBody('CLIPLoader', 'type', ['cpu']),
      })..install();

      await _pumpRunView(
        tester,
        mapping: [
          _node(
            id: '11',
            classType: 'CLIPLoader',
            key: 'type',
            alias: '类型',
            paramType: 'text',
            control: 'select',
            value: 'cuda',
            options: ['cuda'],
          ),
        ],
      );

      await gate.release(tester);

      // 会标注「服务器上没有」，但……
      expect(find.text('服务器没有此模型'), findsOneWidget);

      // ……提交照常放行（按钮没被禁用，也没弹「请先选择模型」）
      await tester.tap(find.text('立即生成'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('请先选择模型'), findsNothing);
    });

    testWidgets('连进两次运行页，第二次下拉选项仍然刷新', (tester) async {
      // 回归点：以前走 ensureLoaded（补缺式），第二次一个请求都不发 ——
      // 电脑上刚装的模型就永远拉不到。
      final gate = _Gate({
        'CheckpointLoaderSimple': _comboBody(
          'CheckpointLoaderSimple',
          'ckpt_name',
          ['a.safetensors'],
        ),
      })..install();

      final mapping = [
        _node(
          id: '4',
          classType: 'CheckpointLoaderSimple',
          key: 'ckpt_name',
          alias: '大模型',
          paramType: 'enumType',
          control: 'select',
          value: 'old.safetensors',
          options: ['old.safetensors'],
        ),
      ];
      final prefs = await _seedPrefs(mapping);

      await _pumpHost(
        tester,
        prefs: prefs,
        home: const RunView(workflowId: 'local_test', snapshotId: 'snap_1'),
      );
      await gate.release(tester);
      expect(gate.requested, hasLength(1));

      // 退出运行页：只换 home，ProviderScope 还在 —— 说明书缓存得以保留。
      // （直接再 pumpWidget 一个 RunView 是不行的：同类型同位置，
      //   State 会被复用，initState 根本不会再跑一遍。）
      await _pumpHost(tester, prefs: prefs, home: const SizedBox());

      // 第二次进：缓存里已经有了，仍然要再问一次
      await _pumpHost(
        tester,
        prefs: prefs,
        home: const RunView(workflowId: 'local_test', snapshotId: 'snap_1'),
      );
      expect(gate.requested, hasLength(2));

      // 收尾放行，别把超时定时器留在那儿
      await gate.release(tester);
    });

    testWidgets('老名单外的下拉（aspect_ratio）也能刷回服务器选项', (tester) async {
      // 陷阱 5 的验收点：配置页是按**全部** classType 定型的，
      // 所以运行页刷新候选值时不能再拿 `kDynamicOptionKeys` 那张老名单筛 ——
      // 否则 aspect_ratio 这类键永远刷不回来，下拉里只剩当前值一项。
      final gate = _Gate({
        'EmptyLatentImage': _comboBody('EmptyLatentImage', 'aspect_ratio', [
          '1:1',
          '16:9',
          '4:3',
        ]),
      })..install();

      await _pumpRunView(
        tester,
        mapping: [
          _node(
            id: '5',
            classType: 'EmptyLatentImage',
            key: 'aspect_ratio',
            alias: '画布比例',
            paramType: 'text',
            control: 'select',
            value: '1:1',
            options: ['1:1'],
          ),
        ],
      );

      await gate.release(tester);

      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      expect(find.text('1:1'), findsWidgets);
      expect(find.text('16:9'), findsWidgets);
      expect(find.text('4:3'), findsWidgets);
    });

    testWidgets('刷新过程中下拉选项不会先缩成「只剩当前值」', (tester) async {
      // 回归点：以前用 refresh()（先清整桶），首帧的完整选项会先塌成
      // 一项再涨回去，观感上闪一下。
      final gate = _Gate({
        'CheckpointLoaderSimple': _comboBody(
          'CheckpointLoaderSimple',
          'ckpt_name',
          ['a.safetensors', 'b.safetensors'],
        ),
      })..install();

      await _pumpRunView(
        tester,
        mapping: [
          _node(
            id: '4',
            classType: 'CheckpointLoaderSimple',
            key: 'ckpt_name',
            alias: '大模型',
            paramType: 'enumType',
            control: 'select',
            value: 'a.safetensors',
            options: ['a.safetensors'],
          ),
        ],
      );

      // 让第一次请求回来：下拉里有两个真实选项
      await gate.release(tester);
      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      expect(find.text('b.safetensors'), findsWidgets);
      await tester.tap(find.text('b.safetensors').last);
      await tester.pumpAndSettle();

      // 点刷新：新请求挂起，此刻旧选项必须还在
      await tester.tap(find.byTooltip('刷新模型列表'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      expect(find.text('a.safetensors'), findsWidgets);
      expect(find.text('b.safetensors'), findsWidgets);

      // 收尾放行，别把超时定时器留在那儿
      await gate.release(tester);
    });
  });

  group('说明书缓存：写入式刷新（方案 §3.5）', () {
    test('refreshInPlace 缓存已有也重取，ensureLoaded 第二次不发', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      var calls = 0;
      final previous = ObjectInfoService.instance.client;
      ObjectInfoService.instance.client = MockClient((_) async {
        calls += 1;
        return http.Response(_comboBody('A', 'k', ['x']), 200);
      });
      addTearDown(() => ObjectInfoService.instance.client = previous);

      final notifier = container.read(objectInfoProvider.notifier);

      await notifier.refreshInPlace(
        serverId: 's',
        baseUrl: _baseUrl,
        classTypes: ['A'],
      );
      expect(calls, 1);

      // 缓存里已经有 A 了 —— 写入式照样再问一次
      await notifier.refreshInPlace(
        serverId: 's',
        baseUrl: _baseUrl,
        classTypes: ['A'],
      );
      expect(calls, 2);

      // 对照：补缺式第二次一个请求都不发（所以它不能用在运行页首帧后）
      await notifier.ensureLoaded(
        serverId: 's',
        baseUrl: _baseUrl,
        classTypes: ['A'],
      );
      expect(calls, 2);
    });

    test('refreshInPlace 等待期间旧选项仍在，不先清桶', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      var current = _comboBody('A', 'k', ['old']);
      final previous = ObjectInfoService.instance.client;
      ObjectInfoService.instance.client = MockClient(
        (_) async => http.Response(current, 200),
      );
      addTearDown(() => ObjectInfoService.instance.client = previous);

      final notifier = container.read(objectInfoProvider.notifier);
      await notifier.refreshInPlace(
        serverId: 's',
        baseUrl: _baseUrl,
        classTypes: ['A'],
      );
      expect(
        container.read(objectInfoProvider).specFor('s', 'A', 'k')?.options,
        ['old'],
      );

      // 换成挂起的请求再刷一次：这一刻旧选项必须还在，
      // 不能像 refresh() 那样先把桶清空、让下拉塌成「只剩当前值」。
      final gate = Completer<http.Response>();
      ObjectInfoService.instance.client = MockClient((_) async => gate.future);
      current = _comboBody('A', 'k', ['new']);
      final flying = notifier.refreshInPlace(
        serverId: 's',
        baseUrl: _baseUrl,
        classTypes: ['A'],
      );

      await Future<void>.delayed(Duration.zero);
      expect(
        container.read(objectInfoProvider).specFor('s', 'A', 'k')?.options,
        ['old'],
      );

      gate.complete(http.Response(current, 200));
      await flying;
      expect(
        container.read(objectInfoProvider).specFor('s', 'A', 'k')?.options,
        ['new'],
      );
    });
  });
}
