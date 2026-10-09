class WorkflowNode {
  final String id;
  final String classType;
  final String key;
  String alias;
  bool exposed;

  WorkflowNode({
    required this.id,
    required this.classType,
    required this.key,
    required this.alias,
    this.exposed = false,
  });

  factory WorkflowNode.fromJson(Map<String, dynamic> json) {
    return WorkflowNode(
      id: json['id'],
      classType: json['classType'] ?? '',
      key: json['key'],
      alias: json['alias'] ?? '',
      exposed: json['exposed'] ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'classType': classType,
        'key': key,
        'alias': alias,
        'exposed': exposed,
      };
}