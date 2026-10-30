import 'workflow_node.dart';

/// 一次 AI 任务引用的节点。`key` 为空表示引用整个节点（目前用不到）。
class AiNodeRef {
  const AiNodeRef({required this.nodeId, this.key});

  final String nodeId;
  final String? key;

  String get id => key == null ? nodeId : '$nodeId:$key';

  factory AiNodeRef.fromJson(Map<String, dynamic> json) => AiNodeRef(
    nodeId: (json['nodeId'] ?? '').toString(),
    key: json['key']?.toString(),
  );

  Map<String, dynamic> toJson() => {'nodeId': nodeId, 'key': key};
}

/// AI 返回的一条改写。**只允许写这几种（nodeId + key + 字符串值）**。
class AiPatch {
  const AiPatch({
    required this.node,
    required this.key,
    required this.value,
  });

  final String node;
  final String key;
  final String value;
}

/// 发送给模型时的输入快照（文本或图片）。
///
/// 只带"被引用的节点 + 该参数的值"，不带整份工作流。
class AiContextInput {
  const AiContextInput({
    required this.nodeId,
    required this.title,
    required this.classType,
    required this.key,
    this.text,
    this.image,
  });

  final String nodeId;
  final String title;
  final String classType;
  final String key;

  /// 文本值；图片引用时为 null。
  final String? text;

  /// 图片文件名（相对 ComfyUI 目录）；文本引用时为 null。
  final String? image;

  bool get isImage => image != null;

  Map<String, dynamic> toJson() => {
    'node': nodeId,
    'title': title,
    'class_type': classType,
    'key': key,
    if (text != null) 'text': text,
    if (image != null) 'image': image,
  };
}

/// 输出目标：必须是字面量字符串参数。
class AiOutputTarget {
  const AiOutputTarget({
    required this.nodeId,
    required this.key,
    required this.title,
    required this.current,
  });

  final String nodeId;
  final String key;
  final String title;
  final String current;

  String get paramKey => '$nodeId:$key';

  Map<String, dynamic> toJson() => {
    'node': nodeId,
    'key': key,
    'title': title,
    'current': current,
  };
}

/// 模型资源摘要（只作为上下文，不当作结论）。
class AiModelInfo {
  const AiModelInfo({required this.kind, required this.name});

  final String kind;
  final String name;

  Map<String, dynamic> toJson() => {'kind': kind, 'name': name};
}

/// 一次任务的结果。
class AiTaskResult {
  const AiTaskResult({
    required this.rawText,
    required this.patches,
    this.notes,
    this.structured = false,
  });

  final String rawText;
  final List<AiPatch> patches;
  final String? notes;

  /// 是否解析成了约定的 JSON。false 时仍允许按纯文本写入（单输出无歧义）。
  final bool structured;

  static const AiTaskResult empty = AiTaskResult(
    rawText: '',
    patches: [],
  );
}

/// 从一个已解析的工作流节点判断它能不能作为「文本输出目标」。
///
/// 口径与运行页一致：只有 `ParamType.text` 且控件是文本框的参数可写；
/// 图片、数值、枚举、布尔都不在候选里。
bool isTextTargetNode(WorkflowNode node) {
  if (node.paramType != ParamType.text) return false;
  final control = node.control;
  return control == null || control == ParamControl.text;
}

/// 该参数是否是图片（可以把图当作输入引用）。
bool isImageInputNode(WorkflowNode node) {
  if (node.paramType == ParamType.image) return true;
  return node.control == ParamControl.upload;
}
