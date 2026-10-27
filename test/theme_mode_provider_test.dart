import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:comfyui_mobilepocket/providers/shared_preferences_provider.dart';
import 'package:comfyui_mobilepocket/providers/theme_mode_provider.dart';

Future<SharedPreferences> _prefsWith([Map<String, Object>? values]) async {
  SharedPreferences.setMockInitialValues(values ?? {});
  return SharedPreferences.getInstance();
}

ProviderContainer _container(SharedPreferences prefs) => ProviderContainer(
  overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
);

void main() {
  group('ThemeModeNotifier', () {
    test('默认未设置时是 null（跟随系统）', () async {
      final prefs = await _prefsWith();
      final container = _container(prefs);
      addTearDown(container.dispose);

      expect(container.read(themeModeProvider), isNull);
    });

    test('prefs 里存了 dark 时读出来', () async {
      final prefs = await _prefsWith({uiThemePrefsKey: 'dark'});
      final container = _container(prefs);
      addTearDown(container.dispose);

      expect(container.read(themeModeProvider), ThemeMode.dark);
    });

    test('prefs 里的值不认识时当作跟随系统', () async {
      final prefs = await _prefsWith({uiThemePrefsKey: 'sepia'});
      final container = _container(prefs);
      addTearDown(container.dispose);

      expect(container.read(themeModeProvider), isNull);
    });

    test('setThemeMode 更新状态并持久化', () async {
      final prefs = await _prefsWith();
      final container = _container(prefs);
      addTearDown(container.dispose);

      await container
          .read(themeModeProvider.notifier)
          .setThemeMode(ThemeMode.dark);

      expect(container.read(themeModeProvider), ThemeMode.dark);
      expect(prefs.getString(uiThemePrefsKey), 'dark');
    });

    test('setFollowSystem 清除偏好并回到跟随系统', () async {
      final prefs = await _prefsWith({uiThemePrefsKey: 'dark'});
      final container = _container(prefs);
      addTearDown(container.dispose);

      await container.read(themeModeProvider.notifier).setFollowSystem();

      expect(container.read(themeModeProvider), isNull);
      expect(prefs.getString(uiThemePrefsKey), isNull);
    });

    test('传 system 走的是清除偏好，不会把 system 存进去', () async {
      // 同一个语义只存一种值：存了 'system' 就等于既"跟随"又"手动"，
      // 设置页会分不清用户到底选过没有
      final prefs = await _prefsWith({uiThemePrefsKey: 'light'});
      final container = _container(prefs);
      addTearDown(container.dispose);

      await container
          .read(themeModeProvider.notifier)
          .setThemeMode(ThemeMode.system);

      expect(container.read(themeModeProvider), isNull);
      expect(prefs.getString(uiThemePrefsKey), isNull);
    });
  });
}
