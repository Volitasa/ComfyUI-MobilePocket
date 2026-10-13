import '../utils.dart';
import 'task_status.dart';

class TaskHistory {
  final String promptId;
  final String workflowId;
  final String title;
  TaskStatus status;
  int progressValue;
  int progressMax;

  /// 当前执行阶段（结构化枚举，只存名字）。
  TaskNodePhase nodePhase;

  /// 阶段的动态内容：执行中的节点名，或出错时服务端的错误原文。
  /// 只存原始值，不含任何展示文案。
  String nodeDetail;
  List<Map<String, dynamic>> images;
  final int timestamp;

  /// 任务提交时所属的服务器连接 ID。
  /// 用于切换服务器时区分任务归属：对新服务器的对账不应该
  /// 把旧服务器上正在跑的任务误判为“已中断”。旧数据为空。
  final String? serverId;

  /// 本次运行固化下来的工作流快照 ID。
  /// 用于「再次运行」——凭快照还原当时的表单结构。旧数据为空。
  final String? snapshotId;

  /// 本次运行实际提交的表单值，键为 nodeParamKey(节点id, 参数名)。
  /// 用于「再次运行」时预填。旧数据为空。
  final Map<String, dynamic>? params;

  TaskHistory({
    required this.promptId,
    required this.workflowId,
    required this.title,
    this.status = TaskStatus.queued,
    this.progressValue = 0,
    this.progressMax = 0,
    this.nodePhase = TaskNodePhase.waiting,
    this.nodeDetail = '',
    this.images = const [],
    int? timestamp,
    this.serverId,
    this.snapshotId,
    this.params,
  }) : timestamp = timestamp ?? DateTime.now().millisecondsSinceEpoch;

  factory TaskHistory.fromJson(Map<String, dynamic> json) {
    final status = taskStatusFromStorage(json['status']);
    return TaskHistory(
      promptId: json['promptId'],
      workflowId: json['workflowId'],
      // 旧版本会把「本地导入」这类翻译文案写进 title，这里清洗成空串，
      // 展示层按当前语言重新补上（否则切语言后残留旧语言的名字）
      title: cleanStoredWorkflowName(json['title'] as String?) ?? '',
      status: status,
      progressValue: json['progressValue'] ?? 0,
      progressMax: json['progressMax'] ?? 0,
      nodePhase: _migratePhase(json, status),
      nodeDetail: _migrateDetail(json),
      images: List<Map<String, dynamic>>.from(json['images'] ?? []),
      timestamp: json['timestamp'],
      serverId: json['serverId'],
      snapshotId: json['snapshotId'],
      params: json['params'] is Map
          ? Map<String, dynamic>.from(json['params'] as Map)
          : null,
    );
  }

  /// 旧版本把整句中文写进 nodeInfo（如「❌ 执行出错: xxx」），
  /// 这里尽力还原出阶段：带错误详情的一律算 error，其余按状态推断。
  static TaskNodePhase _migratePhase(
    Map<String, dynamic> json,
    TaskStatus status,
  ) {
    if (json['nodePhase'] != null) {
      return taskPhaseFromStorage(json['nodePhase'], status);
    }
    final legacy = json['nodeInfo']?.toString() ?? '';
    if (legacy.contains(_legacyErrorMarker)) return TaskNodePhase.error;
    return taskPhaseFromStatus(status);
  }

  static const String _legacyErrorMarker = '执行出错: ';

  /// 旧记录的错误详情藏在 nodeInfo 的后半段，切出来继续用；
  /// 拿不到就留空（展示层会退化成不带详情的错误文案）。
  static String _migrateDetail(Map<String, dynamic> json) {
    final detail = json['nodeDetail'];
    if (detail != null) return detail.toString();
    final legacy = json['nodeInfo']?.toString() ?? '';
    final i = legacy.indexOf(_legacyErrorMarker);
    if (i == -1) return '';
    return legacy.substring(i + _legacyErrorMarker.length);
  }

  Map<String, dynamic> toJson() => {
    'promptId': promptId,
    'workflowId': workflowId,
    'title': title,
    'status': status.storageKey,
    'progressValue': progressValue,
    'progressMax': progressMax,
    'nodePhase': nodePhase.storageKey,
    'nodeDetail': nodeDetail,
    'images': images,
    'timestamp': timestamp,
    'serverId': serverId,
    'snapshotId': snapshotId,
    'params': params,
  };
}
