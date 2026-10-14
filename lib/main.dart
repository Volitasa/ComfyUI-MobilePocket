import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:comfyui_mobilepocket/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'providers/connection_provider.dart';
import 'providers/locale_provider.dart';
import 'ui/main_screen.dart'; // 引入全新的导航壳层

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 启动时初始化本地存储
  final prefs = await SharedPreferences.getInstance();

  runApp(
    ProviderScope(
      overrides: [
        // 覆盖 provider，注入已实例化的 SharedPreferences
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: const ComfyuiMobilePocket(),
    ),
  );
}

class ComfyuiMobilePocket extends ConsumerWidget {
  const ComfyuiMobilePocket({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // null 表示跟随系统：由 resolveLocale 决定，匹配不上时回退中文
    final preferred = ref.watch(localeProvider);

    return MaterialApp(
      // 与 android:label（安装器/桌面显示名）保持一致；
      // 应用名是品牌标识，不随界面语言切换
      title: 'ComfyUI Pocket',
      debugShowCheckedModeBanner: false, // 隐藏右上角 Debug 标签
      // 用户显式选过语言时直接生效；否则走下面的回调按系统语言匹配
      locale: preferred,
      localeResolutionCallback: (deviceLocale, supported) =>
          resolveLocale(preferred, deviceLocale, supported),
      // 让 Material 内置组件（菜单、日期选择器、系统返回提示等）也随语言切换
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.green, // 保持原 Vue 版本的绿色主色调
          surface: Colors.white,
        ),
        scaffoldBackgroundColor: const Color(0xFFF9F9F9),
      ),
      home: const MainScreen(), // 挂载底部导航栏
    );
  }
}
