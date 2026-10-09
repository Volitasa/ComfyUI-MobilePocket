import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/workflow_node.dart';
import '../utils.dart';
import 'connection_provider.dart';

class WorkflowState {
  final List<String> workflowList;
  final bool isLoading;
  final Map<String, dynamic>? currentWorkflowData;

  WorkflowState({
    this.workflowList = const [],
    this.isLoading = false,
    this.currentWorkflowData,
  });

  WorkflowState copyWith({
    List<String>? workflowList,
    bool? isLoading,
    Map<String, dynamic>? currentWorkflowData,
  }) {
    return WorkflowState(
      workflowList: workflowList ?? this.workflowList,
      isLoading: isLoading ?? this.isLoading,
      currentWorkflowData: currentWorkflowData ?? this.currentWorkflowData,
    );
  }
}

class WorkflowNotifier extends Notifier<WorkflowState> {
  late SharedPreferences _prefs;

  @override
  WorkflowState build() {
    _prefs = ref.watch(sharedPreferencesProvider);
    return WorkflowState();
  }

  // 获取线上列表
  Future<void> fetchRemoteList() async {
    final config = ref.read(connectionProvider);
    if (!config.isConnected) return;

    state = state.copyWith(isLoading: true);
    try {
      final uri = Uri.parse('${config.comfyUrl}/userdata?dir=workflows');
      final response =
          await http.get(uri).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        List<dynamic> filesRaw = decoded is List ? decoded : (decoded['files'] ?? []);
        
        final files = filesRaw
            .map((e) => e.toString())
            .where((name) => name.endsWith('_api.json'))
            .toList();
            
        state = state.copyWith(workflowList: files);
      }
    } catch (e) {
      // 生产环境可接入日志
    } finally {
      state = state.copyWith(isLoading: false);
    }
  }

  // 获取单个工作流 JSON 内容（载入时统一归一化，兼容 prompt 包装格式）
  Future<bool> fetchWorkflowContent(String filename) async {
    final config = ref.read(connectionProvider);
    try {
      final fileParam = Uri.encodeComponent('workflows/$filename');
      final uri = Uri.parse('${config.comfyUrl}/userdata/$fileParam');
      final response =
          await http.get(uri).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = Map<String, dynamic>.from(jsonDecode(response.body));
        state = state.copyWith(currentWorkflowData: normalizeWorkflowJson(data));
        return true;
      }
    } catch (e) {
      // 生产环境可接入日志
    }
    return false;
  }

  // 设置本地导入的 JSON 数据（同样做归一化，保证与线上工作流结构一致）
  void setLocalWorkflowData(Map<String, dynamic> data) {
    state = state.copyWith(currentWorkflowData: normalizeWorkflowJson(data));
  }

  // 保存节点配置
  Future<void> saveMappingConfig(String workflowId, List<WorkflowNode> config) async {
    final jsonList = config.map((e) => e.toJson()).toList();
    await _prefs.setString('mapping_$workflowId', jsonEncode(jsonList));
  }

  // 获取已保存的节点配置
  List<WorkflowNode>? getMappingConfig(String workflowId) {
    final dataString = _prefs.getString('mapping_$workflowId');
    if (dataString == null) return null;
    
    try {
      final List<dynamic> decoded = jsonDecode(dataString);
      return decoded.map((e) => WorkflowNode.fromJson(e)).toList();
    } catch (e) {
      return null;
    }
  }
  // 断开连接/切换服务器时清空列表和选中的缓存数据。
  // 直接构造新 state：copyWith 对 null 参数做合并，无法把字段置回 null。
  void clearList() {
    state = WorkflowState(workflowList: [], currentWorkflowData: null);
  }
}

final workflowProvider = NotifierProvider<WorkflowNotifier, WorkflowState>(() {
  return WorkflowNotifier();
});