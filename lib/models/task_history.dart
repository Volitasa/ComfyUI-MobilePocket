class TaskHistory {
  final String promptId;
  final String workflowId;
  final String title;
  String status;
  int progressValue;
  int progressMax;
  String nodeInfo;
  List<Map<String, dynamic>> images;
  final int timestamp;
  /// 任务提交时所属的服务器连接 ID。
  /// 用于切换服务器时区分任务归属：对新服务器的对账不应该
  /// 把旧服务器上正在跑的任务误判为“已中断”。旧数据为空。
  final String? serverId;

  TaskHistory({
    required this.promptId,
    required this.workflowId,
    required this.title,
    this.status = '排队中',
    this.progressValue = 0,
    this.progressMax = 0,
    this.nodeInfo = '等待执行...',
    this.images = const [],
    int? timestamp,
    this.serverId,
  }) : timestamp = timestamp ?? DateTime.now().millisecondsSinceEpoch;

  factory TaskHistory.fromJson(Map<String, dynamic> json) {
    return TaskHistory(
      promptId: json['promptId'],
      workflowId: json['workflowId'],
      title: json['title'],
      status: json['status'] ?? '排队中',
      progressValue: json['progressValue'] ?? 0,
      progressMax: json['progressMax'] ?? 0,
      nodeInfo: json['nodeInfo'] ?? '',
      images: List<Map<String, dynamic>>.from(json['images'] ?? []),
      timestamp: json['timestamp'],
      serverId: json['serverId'],
    );
  }

  Map<String, dynamic> toJson() => {
        'promptId': promptId,
        'workflowId': workflowId,
        'title': title,
        'status': status,
        'progressValue': progressValue,
        'progressMax': progressMax,
        'nodeInfo': nodeInfo,
        'images': images,
        'timestamp': timestamp,
        'serverId': serverId,
      };
}