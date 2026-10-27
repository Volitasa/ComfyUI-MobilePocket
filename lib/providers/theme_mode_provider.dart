import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'shared_preferences_provider.dart';

/// 外观偏好持久化键（存 'light' / 'dark'；不存在表示「跟随系统」）
const uiThemePrefsKey = 'comfy_ui_theme';

/// 界面外观偏好。null = 跟随系统。
///
/// 刻意做成「null 表示跟随系统」而不是存 ThemeMode.system，是为了和
/// [localeProvider] 保持一致：MaterialApp 的 themeMode 需要一个具体值，
/// 由调用方 `?? ThemeMode.system` 兜底，这样设置页也能直接判断
/// 「用户有没有显式选过」。
final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode?>(
  ThemeModeNotifier.new,
);

class ThemeModeNotifier extends Notifier<ThemeMode?> {
  late SharedPreferences _prefs;

  @override
  ThemeMode? build() {
    _prefs = ref.watch(sharedPreferencesProvider);
    return _read(_prefs.getString(uiThemePrefsKey));
  }

  static ThemeMode? _read(String? raw) {
    switch (raw) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return null; // 未设置或值异常 → 跟随系统
    }
  }

  Future<void> setFollowSystem() async {
    await _prefs.remove(uiThemePrefsKey);
    state = null;
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    // 只认 light / dark：system 一律走「清除偏好」这条路径，
    // 避免同一个语义存成两种值
    if (mode == ThemeMode.system) return setFollowSystem();
    await _prefs.setString(uiThemePrefsKey, mode.name);
    state = mode;
  }
}
