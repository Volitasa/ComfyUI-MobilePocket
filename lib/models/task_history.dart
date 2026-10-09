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
      };
}