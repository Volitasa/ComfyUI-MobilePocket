import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'workflow_provider.dart'; 
import 'ws_event_provider.dart';

// 【标准规范 1】：定义全局 SharedPreferences 依赖注入点
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('必须在 main.dart 的 ProviderScope 中通过 overrideWithValue 初始化');
});

// 【标准规范 2】：纯净的状态模型
class ConnectionState {
  final String comfyUrl;
  final bool isConnected;
  final bool isTesting;

  ConnectionState({
    this.comfyUrl = '',
    this.isConnected = false,
    this.isTesting = false,
  });

  ConnectionState copyWith({
    String? comfyUrl,
    bool? isConnected,
    bool? isTesting,
  }) {
    return ConnectionState(
      comfyUrl: comfyUrl ?? this.comfyUrl,
      isConnected: isConnected ?? this.isConnected,
      isTesting: isTesting ?? this.isTesting,
    );
  }
}

// 【标准规范 3】：统一的状态控制器
class ConnectionNotifier extends Notifier<ConnectionState> {
  @override
  ConnectionState build() {
    // 规范做法：依赖注入后可以直接【同步读取】，抛弃繁琐的 await
    final prefs = ref.read(sharedPreferencesProvider);
    final savedUrl = prefs.getString('comfy_url') ?? '';
    
    if (savedUrl.isNotEmpty) {
      // 触发异步连接，且不阻塞应用初始化渲染
      Future.microtask(() => testAndConnect(savedUrl));
      return ConnectionState(comfyUrl: savedUrl); // 直接将取到的值设为初始状态
    }
    
    return ConnectionState();
  }

  // 供输入框使用的同步方法
  void setUrl(String url) {
    state = state.copyWith(comfyUrl: url);
  }

  // 规范的断开与数据清理流程
  Future<void> disconnect() async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.remove('comfy_url');
    
    state = ConnectionState();
    ref.read(workflowProvider.notifier).clearList(); // 联动清理工作流
  }

  // 核心连接逻辑
  Future<bool> testAndConnect(String url) async {
    state = state.copyWith(isTesting: true);
    try {
      final uri = Uri.parse('$url/system_stats');
      final response = await http.get(uri).timeout(const Duration(seconds: 3));

      if (response.statusCode == 200) {
        state = state.copyWith(isConnected: true, isTesting: false, comfyUrl: url);
        
        // 统一使用 ref.read 同步读取持久化实例
        final prefs = ref.read(sharedPreferencesProvider);
        await prefs.setString('comfy_url', url);
        
        // 联动其他 Provider：拉列表 + 连 WebSocket
        ref.read(workflowProvider.notifier).fetchRemoteList();
        ref.read(wsProvider.notifier).connect();
        
        return true;
      }
    } catch (e) {
      print('=== 连接失败: $e ===');
    }
    
    state = state.copyWith(isConnected: false, isTesting: false);
    return false;
  }
}

final connectionProvider = NotifierProvider<ConnectionNotifier, ConnectionState>(() {
  return ConnectionNotifier();
});