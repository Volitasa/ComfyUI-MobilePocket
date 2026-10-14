import 'dart:ui' show Locale;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:comfyui_mobilepocket/l10n/app_localizations.dart';
import 'package:comfyui_mobilepocket/providers/locale_provider.dart';
import 'package:comfyui_mobilepocket/providers/shared_preferences_provider.dart';

Future<SharedPreferences> _prefsWith([Map<String, Object>? values]) async {
  SharedPreferences.setMockInitialValues(values ?? {});
  return SharedPreferences.getInstance();
}

ProviderContainer _container(SharedPreferences prefs) => ProviderContainer(
  overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
);

void main() {
  // 应用支持的语言，顺序与生成产物保持一致
  const supported = [Locale('en'), Locale('zh')];

  group('resolveLocale', () {
    test('用户显式选过语言时直接生效，不受系统语言影响', () {
      expect(
        resolveLocale(const Locale('zh'), const Locale('en'), supported),
        const Locale('zh'),
      );
      expect(
        resolveLocale(const Locale('en'), const Locale('zh'), supported),
        const Locale('en'),
      );
    });

    test('跟随系统时按系统语言匹配受支持列表', () {
      expect(
        resolveLocale(null, const Locale('en'), supported),
        const Locale('en'),
      );
      expect(
        resolveLocale(null, const Locale('zh'), supported),
        const Locale('zh'),
      );
    });

    test('系统语言不在受支持列表时回退中文，而不是列表首项英文', () {
      // 应用本来就是中文的：不能因为新增了英文就让法语用户看到英文
      expect(
        resolveLocale(null, const Locale('fr'), supported),
        fallbackLocale,
      );
      expect(
        resolveLocale(null, const Locale('ja'), supported),
        fallbackLocale,
      );
    });

    test('读不到系统语言时同样回退中文', () {
      expect(resolveLocale(null, null, supported), fallbackLocale);
    });

    test('只比 languageCode：地区与书写变体不影响匹配', () {
      // en-GB / en-US 都算英文
      expect(
        resolveLocale(null, const Locale('en', 'GB'), supported),
        const Locale('en'),
      );
      // 已知边界：zh-Hant-TW 目前也落到简体中文（尚未区分繁简）
      expect(
        resolveLocale(null, const Locale('zh', 'TW'), supported),
        const Locale('zh'),
      );
    });
  });

  group('LocaleNotifier', () {
    test('默认未设置时是 null（跟随系统）', () async {
      final prefs = await _prefsWith();
      final container = _container(prefs);
      addTearDown(container.dispose);

      expect(container.read(localeProvider), isNull);
    });

    test('prefs 里存了语言代码时读出来', () async {
      final prefs = await _prefsWith({uiLocalePrefsKey: 'en'});
      final container = _container(prefs);
      addTearDown(container.dispose);

      expect(container.read(localeProvider), const Locale('en'));
    });

    test('prefs 里的值不认识时当作跟随系统', () async {
      final prefs = await _prefsWith({uiLocalePrefsKey: 'fr'});
      final container = _container(prefs);
      addTearDown(container.dispose);

      expect(container.read(localeProvider), isNull);
    });

    test('setLocale 更新状态并持久化', () async {
      final prefs = await _prefsWith();
      final container = _container(prefs);
      addTearDown(container.dispose);

      await container
          .read(localeProvider.notifier)
          .setLocale(const Locale('en'));

      expect(container.read(localeProvider), const Locale('en'));
      expect(prefs.getString(uiLocalePrefsKey), 'en');
    });

    test('setFollowSystem 清除偏好并回到跟随系统', () async {
      final prefs = await _prefsWith({uiLocalePrefsKey: 'en'});
      final container = _container(prefs);
      addTearDown(container.dispose);

      await container.read(localeProvider.notifier).setFollowSystem();

      expect(container.read(localeProvider), isNull);
      expect(prefs.getString(uiLocalePrefsKey), isNull);
    });
  });

  group('l10nFor', () {
    test('按传入的语言偏好给出对应文案', () {
      expect(l10nFor(const Locale('zh')).settingsTitle, '设置');
      expect(l10nFor(const Locale('en')).settingsTitle, 'Settings');
    });

    test('跟随系统时按 resolveLocale 的规则取文案', () {
      // 不传偏好 → 走设备语言；测试环境的设备语言由
      // PlatformDispatcher 决定，这里只断言一定能取到文案且类型正确
      final l10n = l10nFor(null);
      expect(l10n, isA<AppLocalizations>());
      expect(l10n.settingsTitle, isNotEmpty);
    });
  });
}
