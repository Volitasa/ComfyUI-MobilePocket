import 'dart:ui' show Locale, PlatformDispatcher;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'shared_preferences_provider.dart';

/// 界面语言偏好持久化键（存语言代码；不存在表示「跟随系统」）
const uiLocalePrefsKey = 'comfy_ui_locale';

/// 未匹配到受支持语言时的回退语言（应用原生语言）
const Locale fallbackLocale = Locale('zh');

/// 界面语言偏好。null = 跟随系统。
final localeProvider = NotifierProvider<LocaleNotifier, Locale?>(LocaleNotifier.new);

class LocaleNotifier extends Notifier<Locale?> {
  late SharedPreferences _prefs;

  @override
  Locale? build() {
    _prefs = ref.watch(sharedPreferencesProvider);
    return _read(_prefs.getString(uiLocalePrefsKey));
  }

  static Locale? _read(String? raw) {
    switch (raw) {
      case 'zh':
        return const Locale('zh');
      case 'en':
        return const Locale('en');
      default:
        return null; // 未设置或值异常 → 跟随系统
    }
  }

  Future<void> setFollowSystem() async {
    await _prefs.remove(uiLocalePrefsKey);
    state = null;
  }

  Future<void> setLocale(Locale locale) async {
    await _prefs.setString(uiLocalePrefsKey, locale.languageCode);
    state = locale;
  }
}

/// 决定实际生效的语言。
///
/// [preferred] 为用户显式选择（非空时直接生效）；否则按系统语言匹配受支持
/// 列表，匹配不上（法语、日语…）回退到 [fallbackLocale] 而不是列表首项——
/// 应用本来就是中文的，不该因为新增英文而让其它语种用户看到英文。
///
/// 抽成纯函数便于测试，也便于 MaterialApp 与 Notifier 复用同一套规则。
Locale resolveLocale(
  Locale? preferred,
  Locale? device,
  Iterable<Locale> supported,
) {
  if (preferred != null) return preferred;
  final code = device?.languageCode;
  if (code != null) {
    for (final s in supported) {
      if (s.languageCode == code) return s;
    }
  }
  return fallbackLocale;
}

/// 供拿不到 BuildContext 的地方取得当前语言的文案：Notifier、服务层，
/// 以及 async gap 之后不方便再用 context 的 UI 代码。
///
/// 传当前的语言偏好（跟随系统时传 null）。只读一次不建立依赖：
/// 语言切换由 MaterialApp 重建 UI，Notifier 不该跟着重建
/// （否则正在加载的任务状态会被丢弃）。
AppLocalizations l10nFor(Locale? preferred) {
  final locale = resolveLocale(
    preferred,
    PlatformDispatcher.instance.locale,
    AppLocalizations.supportedLocales,
  );
  return lookupAppLocalizations(locale);
}
