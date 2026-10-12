import 'dart:convert';

import 'workflow_entry.dart';

/// 本地工作流的来源方式。
///
/// 注意区分「来源」与「归属」：无论哪种来源，落到本地库后都是
/// 用户的私有资产——不可再生，因此可重命名、可删除。
enum LocalWorkflowSource {
  /// 用户从本机文件导入
  importFile,

  /// 由服务器工作流「存入本地库」而来
  savedFromRemote,
}

extension LocalWorkflowSourceLabel on LocalWorkflowSource {
  String get label => switch (this) {
        LocalWorkflowSource.importFile => '导入',
        LocalWorkflowSource.savedFromRemote => '另存',
      };
}

/// 本地工作流资产：保存在本机、与服务器无关的完整工作流。
///
/// 与「解析缓存」是两回事：解析缓存能从服务器重新得到，
/// 本地资产删了就没有了，所以它拥有完整的增删改能力。
class LocalWorkflow implements WorkflowEntry {
  /// 唯一键。导入时为 `local_<内容哈希>`（沿用旧规则，便于复用已有配置），
  /// 另存时系统生成。
  @override
  final String id;

  /// 展示名，用户可改
  @override
  String name;

  /// 保存时间（毫秒）
  final int createdAt;

  final LocalWorkflowSource sourceKind;

  /// 来源追溯：原文件名 / 原服务器工作流名
  final String? originName;

  /// 归一化后的工作流节点结构
  final Map<String, dynamic> workflowJson;

  LocalWorkflow({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.sourceKind,
    this.originName,
    required this.workflowJson,
  });

  int? _sizeCache;

  /// 占用字节数（按 UTF-8 编码后的实际长度计算，首次调用后缓存）
  int get sizeBytes => _sizeCache ??= utf8.encode(jsonEncode(workflowJson)).length;

  factory LocalWorkflow.fromJson(Map<String, dynamic> json) {
    return LocalWorkflow(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      createdAt: json['createdAt'] as int? ?? 0,
      sourceKind: _sourceFromName(json['sourceKind']),
      originName: json['originName'] as String?,
      workflowJson: Map<String, dynamic>.from(json['workflowJson'] as Map? ?? {}),
    );
  }

  static LocalWorkflowSource _sourceFromName(dynamic name) {
    return LocalWorkflowSource.values.firstWhere(
      (s) => s.name == name,
      orElse: () => LocalWorkflowSource.importFile,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'createdAt': createdAt,
        'sourceKind': sourceKind.name,
        'originName': originName,
        'workflowJson': workflowJson,
      };
}
