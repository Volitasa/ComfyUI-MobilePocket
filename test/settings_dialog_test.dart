import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:comfyui_mobilepocket/l10n/app_localizations.dart';
import 'package:comfyui_mobilepocket/providers/locale_provider.dart';
import 'package:comfyui_mobilepocket/providers/shared_preferences_provider.dart';
import 'package:comfyui_mobilepocket/providers/theme_mode_provider.dart';
import 'package:comfyui_mobilepocket/ui/settings/settings_view.dart';

Future<SharedPreferences> _prefs([Map<String, Object> values = const {}]) async {
  SharedPreferences.setMockInitialValues(values);
  return SharedPreferences.getInstance();
}

Future<void> _pump(WidgetTester tester, SharedPreferences prefs) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const SettingsView(),
      ),
    ),
  );
  await tester.pump();
}

/// 弹窗里某一选项行结尾的那个勾选图标。
Icon _checkIconOf(WidgetTester tester, String label) {
  final row = find
      .ancestor(of: find.text(label), matching: find.byType(Row))
      .first;
  return tester.widget<Icon>(
    find.descendant(of: row, matching: find.byType(Icon)),
  );
}

void main() {
  testWidgets('外观弹窗：当前项打勾，未选项只有透明占位', (tester) async {
    // 没存过偏好 = 跟随系统，打勾的应该是「跟随系统」那一行
    final prefs = await _prefs();
    await _pump(tester, prefs);

    // 通用段在视口外（测试默认 800×600），先滚到能点的地方
    await tester.scrollUntilVisible(find.text('外观'), 120);
    await tester.pump();
    await tester.tap(find.text('外观'));
    await tester.pumpAndSettle();

    expect(_checkIconOf(tester, '跟随系统').color, isNot(Colors.transparent));
    expect(_checkIconOf(tester, '浅色').color, Colors.transparent);
    expect(_checkIconOf(tester, '深色').color, Colors.transparent);
  });

  testWidgets('外观弹窗：选了深色后重开，勾在「深色」上', (tester) async {
    final prefs = await _prefs({uiThemePrefsKey: 'dark'});
    await _pump(tester, prefs);

    await tester.scrollUntilVisible(find.text('外观'), 120);
    await tester.pump();
    await tester.tap(find.text('外观'));
    await tester.pumpAndSettle();

    expect(_checkIconOf(tester, '深色').color, isNot(Colors.transparent));
    expect(_checkIconOf(tester, '跟随系统').color, Colors.transparent);
  });

  testWidgets('语言弹窗：当前项打勾；选完偏好真的落盘', (tester) async {
    final prefs = await _prefs({uiLocalePrefsKey: 'zh'});
    await _pump(tester, prefs);

    await tester.tap(find.text('界面语言'));
    await tester.pumpAndSettle();

    expect(_checkIconOf(tester, '简体中文').color, isNot(Colors.transparent));
    expect(_checkIconOf(tester, '跟随系统').color, Colors.transparent);
    expect(_checkIconOf(tester, 'English').color, Colors.transparent);

    // 顺手验证重构没破坏弹窗本身的功能：选 English 要生效
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    expect(prefs.getString(uiLocalePrefsKey), 'en');
  });
}
