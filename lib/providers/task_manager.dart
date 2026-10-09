import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http_parser/http_parser.dart';
import '../models/task_history.dart';
import 'connection_provider.dart';

class TaskState {
  final List<TaskHistory> history;
  TaskState({this.history = const []});
}

class TaskManagerNotifier extends Notifier<TaskState> {
  late SharedPreferences _prefs;

  @override
  TaskState build() {
    _prefs = ref.watch(sharedPreferencesProvider);
    _loadHistory();
    return TaskState(history: _loadHistory());
  }

  List<TaskHistory> _loadHistory() {
    final data = _prefs.getString('comfy_task_history');
    if (data == null) return [];
    try {
      final List decoded = jsonDecode(data);
      return decoded.map((e) => TaskHistory.fromJson(e)).toList();
    } catch (e) {
      return [];
    }
  }

  void _saveHistory(List<TaskHistory> newHistory) {
    _prefs.setString('comfy_task_history', jsonEncode(newHistory.map((e) => e.toJson()).toList()));
    state = TaskState(history: newHistory);
  }

  void createNewTask(String promptId, String workflowId) {
    final title = workflowId.replaceAll('_api.json', '');
    final newTask = TaskHistory(promptId: promptId, workflowId: workflowId, title: title);
    
    final updatedList = [newTask, ...state.history];
    if (updatedList.length > 50) {
      updatedList.removeLast(); // 保留最近50条
    }
    _saveHistory(updatedList);
  }

  // HTTP Multipart 上传图片
  Future<String?> uploadImage(List<int> fileBytes, String filename) async {
    final config = ref.read(connectionProvider);
    try {
      final uri = Uri.parse('${config.comfyUrl}/upload/image');
      final request = http.MultipartRequest('POST', uri);
      
      final multipartFile = http.MultipartFile.fromBytes(
        'image',
        fileBytes,
        filename: filename,
        contentType: MediaType('image', 'jpeg'), // 泛用型兜底
      );
      
      request.files.add(multipartFile);
      final response = await request.send();
      
      if (response.statusCode == 200) {
        final respStr = await response.stream.bytesToString();
        final data = jsonDecode(respStr);
        return data['name'];
      }
    } catch (e) {
      // 错误处理
    }
    return null;
  }

  // 提交生成任务
  Future<Map<String, dynamic>?> executeWorkflow(Map<String, dynamic> promptNodes) async {
    final config = ref.read(connectionProvider);
    final payload = {
      'client_id': config.clientId,
      'prompt': promptNodes,
    };

    try {
      final uri = Uri.parse('${config.comfyUrl}/prompt');
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (e) {
      // 错误处理
    }
    return null;
  }

  void removeTask(int index) {
    final updatedList = List<TaskHistory>.from(state.history);
    updatedList.removeAt(index);
    _saveHistory(updatedList);
  }

  // 处理 WebSocket 传来的状态更新
  void updateTaskFromWs(Map<String, dynamic> msg) {
    if (msg['data'] == null || msg['data']['prompt_id'] == null) return;
    
    final promptId = msg['data']['prompt_id'];
    final taskIndex = state.history.indexWhere((t) => t.promptId == promptId);
    if (taskIndex == -1) return;

    final task = state.history[taskIndex];
    final type = msg['type'];
    final data = msg['data'];

    if (type == 'execution_start') {
      task.status = '生成中';
      task.nodeInfo = '🚀 任务开始...';
    } else if (type == 'execution_cached') {
      task.status = '生成中';
      task.nodeInfo = '⚡ 命中缓存...';
    } else if (type == 'progress') {
      task.progressValue = data['value'] ?? 0;
      task.progressMax = data['max'] ?? 0;
      task.nodeInfo = '🔄 处理节点...';
    } else if (type == 'executing') {
      if (data['node'] != null) {
        task.nodeInfo = '执行: ${data['node']}';
      } else {
        task.status = '已完成';
        task.progressValue = task.progressMax;
        task.nodeInfo = '✅ 流程结束';
      }
    } else if (type == 'executed') {
      if (data['output'] != null) {
        if (data['output']['images'] != null) {
          task.images.addAll(List<Map<String, dynamic>>.from(data['output']['images']));
        }
        if (data['output']['gifs'] != null) {
          task.images.addAll(List<Map<String, dynamic>>.from(data['output']['gifs']));
        }
      }
      task.status = '已完成';
      task.nodeInfo = '✅ 生成成功';
    }

    // 触发状态更新并持久化
    final updatedList = List<TaskHistory>.from(state.history);
    updatedList[taskIndex] = task;
    _saveHistory(updatedList);
  }
}

final taskManagerProvider = NotifierProvider<TaskManagerNotifier, TaskState>(() {
  return TaskManagerNotifier();
});