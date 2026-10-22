import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http_parser/http_parser.dart';

import '../models/task_history.dart';
import '../models/task_status.dart';
import '../services/gallery_store.dart';
import '../utils.dart';
import 'connection_provider.dart';
import 'local_workflow_provider.dart';
import 'workflow_provider.dart';

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
    _prefs.setString(
      'comfy_task_history',
      jsonEncode(newHistory.map((e) => e.toJson()).toList()),
    );
    state = TaskState(history: newHistory);
  }

  void createNewTask(
    String promptId,
    String workflowId, {
    String? snapshotId,
    Map<String, dynamic>? params,
  }) {
    // 记住任务所属的服务器连接，切换服务器时不会把旧服务器的任务误判
    final config = ref.read(connectionProvider);
    // 本地资产用库里的名称、解析缓存用文件名，否则记录里全是「本地导入」无法分辨。
    // 取不到真实名字时留空：展示层按当前语言补默认名（翻译不落盘，避免切语言残留）。
    final title = workflowNameForStorage(
      ref.read(knownWorkflowEntriesProvider),
      workflowId,
    );
    final newTask = TaskHistory(
      promptId: promptId,
      workflowId: workflowId,
      title: title ?? '',
      serverId: config.activeServerId,
      snapshotId: snapshotId,
      params: params,
    );

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

      // 按文件扩展名推断正确的 Content-Type，避免 PNG 被误标为 jpeg
      final ext = filename.split('.').last.toLowerCase();
      final contentType = switch (ext) {
        'png' => MediaType('image', 'png'),
        'webp' => MediaType('image', 'webp'),
        'gif' => MediaType('image', 'gif'),
        'bmp' => MediaType('image', 'bmp'),
        _ => MediaType('image', 'jpeg'),
      };

      final multipartFile = http.MultipartFile.fromBytes(
        'image',
        fileBytes,
        filename: filename,
        contentType: contentType,
      );

      request.files.add(multipartFile);
      final response = await request.send().timeout(
        const Duration(seconds: 60),
      );

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
  Future<Map<String, dynamic>?> executeWorkflow(
    Map<String, dynamic> promptNodes,
  ) async {
    final config = ref.read(connectionProvider);
    final payload = {'client_id': config.clientId, 'prompt': promptNodes};

    try {
      final uri = Uri.parse('${config.comfyUrl}/prompt');
      final response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 30));

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
  // deleteLocalImages=true 时连带删除该任务已下载到画廊的本地图片
  Future<void> removeTask(
    String promptId, {
    bool deleteLocalImages = false,
  }) async {
    if (deleteLocalImages) {
      final idx = state.history.indexWhere((t) => t.promptId == promptId);
      if (idx != -1) {
        final task = state.history[idx];
        for (final img in task.images) {
          final localPath = img['localPath'];
          if (localPath is String && localPath.isNotEmpty) {
            // 等删完再移除记录：画廊页靠「记录变少」判断要刷新，
            // 不等的话会刷在文件删除完成之前
            await GalleryStore.instance.deleteFile(localPath);
          }
        }
      }
    }
    final updatedList = List<TaskHistory>.from(state.history)
      ..removeWhere((t) => t.promptId == promptId);
    _saveHistory(updatedList);
  }

  // 从 executed/history 的 outputs 结构里提取媒体条目
  List<Map<String, dynamic>> _extractOutputs(dynamic outputs) {
    final media = <Map<String, dynamic>>[];
    if (outputs is Map) {
      for (final nodeOut in outputs.values) {
        if (nodeOut is! Map) continue;
        if (nodeOut['images'] is List) {
          media.addAll(
            (nodeOut['images'] as List).map(
              (e) => Map<String, dynamic>.from(e),
            ),
          );
        }
        if (nodeOut['gifs'] is List) {
          media.addAll(
            (nodeOut['gifs'] as List).map((e) => Map<String, dynamic>.from(e)),
          );
        }
      }
    }
    return media;
  }

  /// 对账未终结任务：App 崩溃/重启或断线期间错过的终态事件无法通过 WS 补收，
  /// 这里主动向 ComfyUI 的 /history 与 /queue 查询，纠正卡在"排队中/生成中"的任务。
  Future<void> reconcilePendingTasks() async {
    final currentServerId = ref.read(connectionProvider).activeServerId;
    final pending = state.history
        .where((t) => t.status.isPending)
        // 只处理属于当前服务器（或旧数据无归属）的任务：
        // 其它服务器上正在跑的任务在新服务器上查不到，
        // 不能据此判定为中断，否则会污染本地已有记录
        .where((t) => t.serverId == null || t.serverId == currentServerId)
        .toList();
    if (pending.isEmpty) return;

    final config = ref.read(connectionProvider);
    if (!config.isConnected) return;

    // 1. 拉取服务端历史（含已完成任务及其输出）
    Map<String, dynamic> historyData = {};
    try {
      final resp = await http
          .get(Uri.parse('${config.comfyUrl}/history'))
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) return;
      final decoded = jsonDecode(resp.body);
      if (decoded is Map) historyData = Map<String, dynamic>.from(decoded);
    } catch (_) {
      return; // 拉取失败则不动状态，避免误判
    }

    // 2. 拉取队列（区分仍在运行/仍在排队）
    final running = <String>{};
    final queued = <String>{};
    try {
      final q = await http
          .get(Uri.parse('${config.comfyUrl}/queue'))
          .timeout(const Duration(seconds: 15));
      if (q.statusCode == 200) {
        final data = jsonDecode(q.body);
        if (data is Map) {
          for (final item in (data['queue_running'] as List? ?? [])) {
            if (item is List && item.length > 1) {
              running.add(item[1].toString());
            }
          }
          for (final item in (data['queue_pending'] as List? ?? [])) {
            if (item is List && item.length > 1) {
              queued.add(item[1].toString());
            }
          }
        }
      }
    } catch (_) {
      // 队列拉取失败不影响历史对账
    }

    var changed = false;
    final toLocalize = <String, List<Map<String, dynamic>>>{};

    for (final task in pending) {
      final entry = historyData[task.promptId];
      if (entry is Map) {
        // 服务端已有该任务的终态记录
        final status = entry['status'];
        final statusStr = status is Map
            ? status['status_str']?.toString()
            : null;
        final messages = status is Map ? status['messages'] : null;
        final interrupted =
            messages is List &&
            messages.any(
              (m) =>
                  m is List &&
                  m.isNotEmpty &&
                  m.first == 'execution_interrupted',
            );

        if (interrupted) {
          task.status = TaskStatus.interrupted;
          task.nodePhase = TaskNodePhase.interrupted;
          task.nodeDetail = '';
        } else if (statusStr == 'success') {
          final media = _extractOutputs(entry['outputs']);
          if (media.isNotEmpty) {
            final existing = task.images.map((m) => m['filename']).toSet();
            final fresh = media
                .where((m) => !existing.contains(m['filename']))
                .toList();
            if (fresh.isNotEmpty) {
              task.images = [...task.images, ...fresh];
              toLocalize[task.promptId] = fresh;
            }
          }
          task.status = TaskStatus.completed;
          task.progressValue = task.progressMax;
          task.nodePhase = TaskNodePhase.done;
          task.nodeDetail = '';
        } else {
          // 服务端记录的非成功终态，没有错误详情可展示
          task.status = TaskStatus.failed;
          task.nodePhase = TaskNodePhase.error;
          task.nodeDetail = '';
        }
        changed = true;
      } else if (running.contains(task.promptId)) {
        task.status = TaskStatus.running;
        changed = true;
      } else if (queued.contains(task.promptId)) {
        task.status = TaskStatus.queued;
        task.nodePhase = TaskNodePhase.waiting;
        task.nodeDetail = '';
        changed = true;
      } else {
        // 既不在历史也不在队列：服务端已重启或任务丢失，终结避免永久卡住
        task.status = TaskStatus.interrupted;
        task.nodePhase = TaskNodePhase.lost;
        task.nodeDetail = '';
        changed = true;
      }
    }

    if (changed) {
      _saveHistory(List<TaskHistory>.from(state.history));
    }
    for (final e in toLocalize.entries) {
      unawaited(_localizeMedia(e.key, e.value));
    }
  }

  // 节点 ID → 可读名称：优先用工作流映射里保存的节点标题，无则回退"类名(ID)"
  //
  // [serverId] 是这条任务当时跑在哪台服务器上：服务器工作流的配置按服务器分开存，
  // 拿错了就取不到标题（会退化成"类名(ID)"），但绝不会串到别的服务器的配置上。
  String _nodeLabel(String workflowId, String? serverId, dynamic nodeId) {
    final idStr = nodeId?.toString() ?? '';
    final config = ref
        .read(workflowProvider.notifier)
        .getMappingConfig(workflowId, serverId: serverId);
    if (config != null) {
      for (final n in config) {
        if (n.id == idStr) {
          return isMeaningfulTitle(n.title, n.classType)
              ? n.title
              : '${n.classType}($idStr)';
        }
      }
    }
    return idStr;
  }

  // 组装媒体文件的下载 URL
  String _mediaUrl(Map<String, dynamic> media) {
    final config = ref.read(connectionProvider);
    final filename = Uri.encodeComponent(media['filename'] ?? '');
    final subfolder = Uri.encodeComponent(media['subfolder'] ?? '');
    final type = Uri.encodeComponent(media['type'] ?? 'output');
    return '${config.comfyUrl}/view?filename=$filename&subfolder=$subfolder&type=$type';
  }

  // 异步下载新生成的媒体到本地画廊，成功后回填 localPath 并持久化
  Future<void> _localizeMedia(
    String promptId,
    List<Map<String, dynamic>> newMedia,
  ) async {
    final downloaded = <Map<String, dynamic>>[];
    for (final media in newMedia) {
      try {
        final url = _mediaUrl(media);
        final resp = await http
            .get(Uri.parse(url))
            .timeout(const Duration(seconds: 60));
        if (resp.statusCode == 200 && resp.bodyBytes.isNotEmpty) {
          final name = media['filename']?.toString() ?? 'image.png';
          final localPath = await GalleryStore.instance.saveBytes(
            resp.bodyBytes,
            name,
          );
          downloaded.add({...media, 'localPath': localPath});
        } else {
          downloaded.add(media);
        }
      } catch (_) {
        downloaded.add(media); // 下载失败则保留原样，仍走服务器 URL
      }
    }

    if (downloaded.isEmpty) return;

    // 回填 localPath 到任务历史并持久化
    final idx = state.history.indexWhere((t) => t.promptId == promptId);
    if (idx == -1) return;
    final task = state.history[idx];
    // 按 filename 匹配回填（下载顺序与原顺序一致）
    final updatedImages = task.images.map((m) {
      for (final d in downloaded) {
        if (d['localPath'] != null && d['filename'] == m['filename']) {
          return {...m, 'localPath': d['localPath']};
        }
      }
      return m;
    }).toList();
    task.images = updatedImages;
    _saveHistory(List<TaskHistory>.from(state.history));
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
      task.status = TaskStatus.running;
      task.nodePhase = TaskNodePhase.started;
      task.nodeDetail = '';
    } else if (type == 'execution_cached') {
      task.status = TaskStatus.running;
      task.nodePhase = TaskNodePhase.cached;
      task.nodeDetail = '';
    } else if (type == 'progress') {
      // 任何执行活动都意味着任务已不在排队（execution_start 可能因竞态被错过）
      task.status = TaskStatus.running;
      task.nodePhase = TaskNodePhase.running;
      task.progressValue = data['value'] ?? 0;
      task.progressMax = data['max'] ?? 0;
      // 节点名已由 executing 事件写进 nodeDetail，这里只更新进度
    } else if (type == 'executing') {
      if (data['node'] != null) {
        // 用节点标题代替裸节点 ID，存进 nodeDetail 供进度展示拼接。
        // 旧记录没有 serverId（那时还没记归属），退回到当前连着的这台。
        final label = _nodeLabel(
          task.workflowId,
          task.serverId ?? ref.read(connectionProvider).activeServerId,
          data['node'],
        );
        task.status = TaskStatus.running;
        task.nodePhase = TaskNodePhase.running;
        task.nodeDetail = label;
      } else {
        // executing(node=null) 是执行结束的收尾信号，正常完成与中断/出错后都会发。
        // 已中断/已失败是终态，不能被它覆盖成“已完成”
        if (!task.status.isTerminal) {
          task.status = TaskStatus.completed;
          task.progressValue = task.progressMax;
          task.nodePhase = TaskNodePhase.done;
          task.nodeDetail = '';
        }
      }
    } else if (type == 'execution_error') {
      // 服务端执行出错：必须终结任务状态，否则 UI 会永远停留在“生成中”
      task.status = TaskStatus.failed;
      task.nodePhase = TaskNodePhase.error;
      // 详情留空时展示层只说“执行出错”，不编造内容
      task.nodeDetail =
          (data['exception_message'] ?? data['exception_type'])?.toString() ??
          '';
    } else if (type == 'execution_interrupted') {
      task.status = TaskStatus.interrupted;
      task.nodePhase = TaskNodePhase.interrupted;
      task.nodeDetail = '';
    } else if (type == 'executed') {
      try {
        final output = data['output'];
        final newMedia = <Map<String, dynamic>>[];

        // 1. 安全提取新生成的媒体数据
        if (output != null) {
          if (output['images'] != null) {
            newMedia.addAll(
              (output['images'] as List).map(
                (e) => Map<String, dynamic>.from(e),
              ),
            );
          }
          if (output['gifs'] != null) {
            newMedia.addAll(
              (output['gifs'] as List).map((e) => Map<String, dynamic>.from(e)),
            );
          }
        }

        // 2. 合并旧图和新图
        final combinedImages = [...task.images, ...newMedia];

        // 3. 赋值（注：如果未来发现 UI 不刷新，需将 TaskHistory 改造为 copyWith 模式）
        task.images = combinedImages;
        task.status = TaskStatus.completed;
        task.nodePhase = TaskNodePhase.done;
        task.nodeDetail = '';

        // 4. 异步把新图下载到本地画廊（保留原图元数据，可拖回 ComfyUI 复现）
        final newMediaCopy = List<Map<String, dynamic>>.from(newMedia);
        unawaited(_localizeMedia(promptId, newMediaCopy));
      } catch (e) {
        task.status = TaskStatus.failed;
        task.nodePhase = TaskNodePhase.parseFailed;
        task.nodeDetail = '';
      }
    }

    // 触发状态更新并持久化
    final updatedList = List<TaskHistory>.from(state.history);
    updatedList[taskIndex] = task;
    _saveHistory(updatedList);
  }
}

final taskManagerProvider = NotifierProvider<TaskManagerNotifier, TaskState>(
  () {
    return TaskManagerNotifier();
  },
);
