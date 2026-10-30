import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:comfyui_mobilepocket/l10n/app_localizations.dart';
import 'package:comfyui_mobilepocket/providers/connection_provider.dart';
import 'package:comfyui_mobilepocket/ui/widgets/connection_status_badge.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('不在重连时圆点保持常亮（不透明度必须是 1）', (tester) async {
    // 这条锁的是一个真实翻过的车：呼吸动画的控制器默认停在 0，
    // 而 0 对应的 opacity 是 0.35 —— 结果常态绿点被压成三四成透明，
    // 看起来「变浅变暗」。判据只能是渲染出来的不透明度，不是"代码里有 FadeTransition"。
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: ConnectionStatusBadge()),
        ),
      ),
    );
    await tester.pump();

    // 取第一个：圆点的 FadeTransition 在 Row 里排第一，
    // 后面文案的 AnimatedSwitcher 自己也会造 FadeTransition
    final fade = tester.widget<FadeTransition>(
      find
          .descendant(
            of: find.byType(ConnectionStatusBadge),
            matching: find.byType(FadeTransition),
          )
          .first,
    );
    expect(fade.opacity.value, 1.0);
  });
}
