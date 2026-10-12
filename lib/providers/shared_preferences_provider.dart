import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 全局注入的 SharedPreferences 实例。
///
/// 单独成文件：连接、语言、本地工作流等多个 provider 都要用它，
/// 挂在 connection_provider 下会让彼此形成环形依赖。
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('须在 main.dart 中初始化');
});
