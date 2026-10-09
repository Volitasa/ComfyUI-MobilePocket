import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'providers/connection_provider.dart';
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
      child: const ComfyUI_MobilePocket(),
    ),
  );
}

class ComfyUI_MobilePocket extends StatelessWidget {
  const ComfyUI_MobilePocket({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ComfyUI Remote',
      debugShowCheckedModeBanner: false, // 隐藏右上角 Debug 标签
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