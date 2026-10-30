import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:comfyui_mobilepocket/providers/haptics_provider.dart';
import 'package:comfyui_mobilepocket/providers/shared_preferences_provider.dart';

Future<SharedPreferences> _prefsWith([Map<String, Object>? values]) async {
  SharedPreferences.setMockInitialValues(values ?? {});
  return SharedPreferences.getInstance();
}

ProviderContainer _container(SharedPreferences prefs) => ProviderContainer(
  overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
);

void main() {
  group('震动分类编码', () {
    test('键不存在 = 全部开启（新装用户）', () {
      expect(decodeHaptics(null), HapticCategory.values.toSet());
    });

    test('空串 = 一个都不开（用户主动全关）', () {
      // 这一条与上一条必须区分开：混成一个默认值的话，
      // 用户把每一类都关掉之后重进设置，又会看到「全部开启」
      expect(decodeHaptics(''), isEmpty);
    });

    test('认得出来的类别才进集合，不认识的直接忽略', () {
      expect(decodeHaptics('nav,fold'), {
        HapticCategory.nav,
        HapticCategory.fold,
      });
      expect(decodeHaptics('nav,hover,fold'), {
        HapticCategory.nav,
        HapticCategory.fold,
      });
    });

    test('编码按枚举顺序输出，同一组合同一个字符串', () {
      expect(
        encodeHaptics({HapticCategory.fold, HapticCategory.nav}),
        'nav,fold',
      );
      expect(encodeHaptics(<HapticCategory>{}), '');
    });
  });

  group('HapticsNotifier', () {
    test('默认全部开启', () async {
      final container = _container(await _prefsWith());
      addTearDown(container.dispose);

      expect(container.read(hapticsProvider), HapticCategory.values.toSet());
    });

    test('关掉一类后只少这一类，并落盘', () async {
      final prefs = await _prefsWith();
      final container = _container(prefs);
      addTearDown(container.dispose);

      await container
          .read(hapticsProvider.notifier)
          .toggle(HapticCategory.reorder);

      expect(container.read(hapticsProvider), isNot(contains(HapticCategory.reorder)));
      expect(container.read(hapticsProvider), contains(HapticCategory.nav));
      // press 在枚举末尾追加，同样的开关组合永远多出最后一段
      expect(
        prefs.getString(kHapticsPrefsKey),
        'nav,check,fold,submit,press',
      );
      // 落盘的同时记下「这次写入时知道哪些类别」，
      // 之后再新增类别时才能区分「用户关掉了」和「当时还没这一项」
      expect(
        prefs.getString(kHapticsKnownPrefsKey),
        'nav,check,reorder,fold,submit,press',
      );
    });

    test('再点一次又开回来', () async {
      final prefs = await _prefsWith({kHapticsPrefsKey: 'nav'});
      final container = _container(prefs);
      addTearDown(container.dispose);

      await container.read(hapticsProvider.notifier).toggle(HapticCategory.fold);

      // 老数据（只存了 nav）里没有 press，也没有 known 键：
      // press 按「默认开启」补进来，而不是当成用户关掉了
      expect(container.read(hapticsProvider), {
        HapticCategory.nav,
        HapticCategory.fold,
        HapticCategory.press,
      });
    });

    test('全部关闭落盘成空串；重新读取时仍然是「一个都没开」', () async {
      final prefs = await _prefsWith();
      final first = _container(prefs);
      addTearDown(first.dispose);
      await first.read(hapticsProvider.notifier).setAll(false);

      expect(prefs.getString(kHapticsPrefsKey), '');

      // 换一个容器模拟「重开 App」：读同一份 prefs
      final second = _container(prefs);
      addTearDown(second.dispose);
      expect(second.read(hapticsProvider), isEmpty);
    });

    test('全部开启后落盘包含所有类别', () async {
      final prefs = await _prefsWith({kHapticsPrefsKey: ''});
      final container = _container(prefs);
      addTearDown(container.dispose);

      await container.read(hapticsProvider.notifier).setAll(true);

      expect(prefs.getString(kHapticsPrefsKey), 'nav,check,reorder,fold,submit,press');
    });
  });

  group('新类别的存储迁移', () {
    test('老数据：旧类别里被关掉的保持关，新类别按默认开启补上', () async {
      // 老用户在 v1.4.1 里关掉了 reorder，那时还没有 press，
      // 存的值里必然没有这两个名字 —— 只有 reorder 该维持关，press 要开。
      final prefs = await _prefsWith({kHapticsPrefsKey: 'nav,check,fold,submit'});
      final container = _container(prefs);
      addTearDown(container.dispose);

      expect(container.read(hapticsProvider), {
        HapticCategory.nav,
        HapticCategory.check,
        HapticCategory.fold,
        HapticCategory.submit,
        HapticCategory.press,
      });
    });

    test('老数据全关（空串）：一个都不补，新类别也不补', () async {
      // 「全部关闭」表达的是「这个 App 别震」；拿默认值偷偷把新类别打开
      // 等于违背这个选择。
      final prefs = await _prefsWith({kHapticsPrefsKey: ''});
      final container = _container(prefs);
      addTearDown(container.dispose);

      expect(container.read(hapticsProvider), isEmpty);
    });

    test('known 键在：缺的名字就是用户关掉的，不再补', () async {
      // 用户升级后主动把 press 关掉 → 落盘的名单里没有 press，
      // 但 known 里有 → 下次启动不能又把它补回来。
      final prefs = await _prefsWith({
        kHapticsPrefsKey: 'nav,check,reorder,fold,submit',
        kHapticsKnownPrefsKey: 'nav,check,reorder,fold,submit,press',
      });
      final container = _container(prefs);
      addTearDown(container.dispose);

      expect(container.read(hapticsProvider), isNot(contains(HapticCategory.press)));
      expect(container.read(hapticsProvider), contains(HapticCategory.nav));
    });

    test('关掉新类别 → 重启后仍然是关的（迁移不会反复生效）', () async {
      final prefs = await _prefsWith(); // 新装，全部开启
      final first = _container(prefs);
      addTearDown(first.dispose);
      await first.read(hapticsProvider.notifier).toggle(HapticCategory.press);

      expect(
        prefs.getString(kHapticsPrefsKey),
        'nav,check,reorder,fold,submit',
      );

      final second = _container(prefs); // 模拟重开 App
      addTearDown(second.dispose);
      expect(second.read(hapticsProvider), isNot(contains(HapticCategory.press)));
      expect(second.read(hapticsProvider), contains(HapticCategory.nav));
    });

    test('没存过 = 新装用户，全部开启且不需要迁移', () async {
      final prefs = await _prefsWith();
      final container = _container(prefs);
      addTearDown(container.dispose);

      expect(container.read(hapticsProvider), HapticCategory.values.toSet());
    });
  });

  group('关掉的类别不产生平台调用', () {
    late List<String> calls;

    setUp(() {
      calls = <String>[];
      TestDefaultBinaryMessengerBinding
          .instance
          .defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'HapticFeedback.vibrate') {
              calls.add(call.arguments as String);
            }
            return null;
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding
          .instance
          .defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    testWidgets('开启时震，关掉后不再产生平台调用（走真实入口）', (tester) async {
      final prefs = await _prefsWith();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
          child: MaterialApp(
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) => TextButton(
                  onPressed: () =>
                      hapticFeedback(ref, HapticCategory.nav),
                  child: const Text('tap'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('tap'));
      await tester.pump();
      expect(calls, hasLength(1));

      final container = ProviderScope.containerOf(
        tester.element(find.text('tap')),
      );
      await container.read(hapticsProvider.notifier).toggle(HapticCategory.nav);
      await tester.pump();

      await tester.tap(find.text('tap'));
      await tester.pump();
      expect(calls, hasLength(1), reason: '这一类已关闭，不该再震');
    });
  });
}
