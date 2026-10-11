import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'connection_provider.dart';

/// GitHub 只读令牌的持久化键。
/// 仓库若是私有的，匿名请求 releases 接口会一律返回 404，
/// 需要在这里配置一个对该仓库有 Contents 读取权限的令牌。
const String githubTokenPrefsKey = 'comfy_github_token';

class GithubTokenNotifier extends Notifier<String> {
  late SharedPreferences _prefs;

  @override
  String build() {
    _prefs = ref.watch(sharedPreferencesProvider);
    return _prefs.getString(githubTokenPrefsKey) ?? '';
  }

  /// 保存令牌；传空串等同于清除。
  Future<void> save(String token) async {
    final t = token.trim();
    if (t.isEmpty) {
      await _prefs.remove(githubTokenPrefsKey);
    } else {
      await _prefs.setString(githubTokenPrefsKey, t);
    }
    state = t;
  }

  Future<void> clear() => save('');
}

final githubTokenProvider =
    NotifierProvider<GithubTokenNotifier, String>(GithubTokenNotifier.new);
