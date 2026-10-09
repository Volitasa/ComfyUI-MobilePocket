import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http_parser/http_parser.dart';
import '../models/task_history.dart';
import '../utils.dart';
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
    final title = workflowDisplayName(workflowId);
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
      final response =
          await request.send().timeout(const Duration(seconds: 60));

      if (response.statusCode == 200) {
        final respStr = await response.stream.bytesToString();
        final data = jsonDecode(respStr);
        return data['name'];
      }
    } catch (e) {
      // 上传失败时返回 null，由调用方给出错误提示
    }
    return null;
  }

  // 提交生成任务。
  // 返回值约定：200 → 服务端原始响应（含 prompt_id）；
  // 非 200 → {'_http_error': 状态码, '_body': 服务端错误详情}，供 UI 透出；
  // 网络异常/超时 → null。
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
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      dynamic body;
      try {
        body = jsonDecode(response.body);
      } catch (_) {
        body = null;
      }
      return {'_http_error': response.statusCode, '_body': body};
    } catch (e) {
      return null;
    }
  }

  // 按 promptId 删除任务，避免列表在渲染与点击之间发生变化时删错条目
  void removeTask(String promptId) {
    final updatedList = List<TaskHistory>.from(state.history)
      ..removeWhere((t) => t.promptId == promptId);
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
        // 防止流程结束的提示覆盖掉成功的提示
        if (task.nodeInfo != '✅ 生成成功') {
          task.nodeInfo = '✅ 流程结束';
        }
      }
    } else if (type == 'execution_error') {
      // 服务端执行出错：必须终结任务状态，否则 UI 会永远停留在“生成中”
      task.status = '已失败';
      final errMsg = data['exception_message'] ?? data['exception_type'] ?? '未知错误';
      task.nodeInfo = '❌ 执行出错: $errMsg';
    } else if (type == 'execution_interrupted') {
      task.status = '已中断';
      task.nodeInfo = '⏹️ 任务已被中断';
    } else if (type == 'executed') {
      try {
        final output = data['output'];
        final newMedia = <Map<String, dynamic>>[];

        // 1. 安全提取新生成的媒体数据
        if (output != null) {
          if (output['images'] != null) {
            newMedia.addAll((output['images'] as List).map((e) => Map<String, dynamic>.from(e)));
          }
          if (output['gifs'] != null) {
            newMedia.addAll((output['gifs'] as List).map((e) => Map<String, dynamic>.from(e)));
          }
        }

        // 2. 合并旧图和新图
        final combinedImages = [...task.images, ...newMedia];

        // 3. 赋值（注：如果未来发现 UI 不刷新，需将 TaskHistory 改造为 copyWith 模式）
        task.images = combinedImages;
        task.status = '已完成';
        task.nodeInfo = '✅ 生成成功';
      } catch (e) {
        task.status = '已失败';
        task.nodeInfo = '❌ 结果数据解析失败';
      }
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
