import 'dart:math';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

// 用于全局注入 SharedPreferences 实例
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('须在 main.dart 中初始化');
});

// 状态实体 (对应 Pinia 中的 state)
class ConfigState {
  final String comfyUrl;
  final bool isConnected;
  final bool isTesting;
  final String clientId;
  final String? testResultMessage;

  ConfigState({
    this.comfyUrl = 'http://127.0.0.1:8190',
    this.isConnected = false,
    this.isTesting = false,
    this.clientId = '',
    this.testResultMessage,
  });

  ConfigState copyWith({
    String? comfyUrl,
    bool? isConnected,
    bool? isTesting,
    String? clientId,
    String? testResultMessage,
  }) {
    return ConfigState(
      comfyUrl: comfyUrl ?? this.comfyUrl,
      isConnected: isConnected ?? this.isConnected,
      isTesting: isTesting ?? this.isTesting,
      clientId: clientId ?? this.clientId,
      testResultMessage: testResultMessage,
    );
  }
}

// 状态控制器 (对应 Pinia 中的 actions)
class ConnectionNotifier extends Notifier<ConfigState> {
  late SharedPreferences _prefs;

  @override
  ConfigState build() {
    _prefs = ref.watch(sharedPreferencesProvider);
    return ConfigState(
      comfyUrl: _prefs.getString('comfyUrl') ?? 'http://127.0.0.1:8190',
      clientId: _getOrCreateClientId(),
    );
  }

  // 保证 App 单次运行期间及持久化维度的身份凭证一致性
  String _getOrCreateClientId() {
    String? id = _prefs.getString('comfy_client_id');
    if (id == null) {
      final randomStr = Random().nextInt(9999999).toRadixString(36);
      id = 'mobile_${randomStr}_${DateTime.now().millisecondsSinceEpoch}';
      _prefs.setString('comfy_client_id', id);
    }
    return id;
  }

  // 测试并保存连接
  Future<void> testConnection(String url) async {
    state = state.copyWith(isTesting: true, isConnected: false, testResultMessage: null);

    // 移除末尾的反斜杠
    final cleanUrl = url.endsWith('/') ? url.substring(0, url.length - 1) : url;

    try {
      final uri = Uri.parse('$cleanUrl/system_stats');
      // 设置 5 秒超时防止卡死
      final response = await http.get(uri).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        await _prefs.setString('comfyUrl', cleanUrl);
        state = state.copyWith(
          comfyUrl: cleanUrl,
          isConnected: true,
          isTesting: false,
          testResultMessage: '连接成功！',
        );
      } else {
        state = state.copyWith(
          isTesting: false,
          isConnected: false,
          testResultMessage: '连接失败: HTTP ${response.statusCode}',
        );
      }
    } catch (e) {
      state = state.copyWith(
        isTesting: false,
        isConnected: false,
        testResultMessage: '无法连接到服务器，请检查地址或网络跨域设置。',
      );
    }
  }
}

final connectionProvider = NotifierProvider<ConnectionNotifier, ConfigState>(() {
  return ConnectionNotifier();
});