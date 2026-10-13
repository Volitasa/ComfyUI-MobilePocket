import 'dart:convert';

import '../services/workflow_api_converter.dart';
import 'workflow_entry.dart';

/// UI 工作流的解析缓存。
///
/// 与本地资产（`LocalWorkflow`）的关键区别：**它能从服务器重新得到**。
/// 所以没有「删除」，只有「清除解析缓存」——清除后回到未解析状态，
/// 随时可以再解析一次。
class ParsedWorkflow implements WorkflowEntry {
  /// 由 serverId + filename 推导，同一服务器同一文件永远命中同一条
  @override
  final String id;

  /// 所属服务器连接
  final String serverId;

  /// 服务器上的文件名
  final String filename;

  /// 展示名，跟随服务器文件名（不提供重命名，避免与服务器不一致）
  @override
  final String name;

  /// 解析时 UI JSON 的内容哈希，用于判断服务器是否已更新
  final String sourceHash;

  final int parsedAt;

  /// 解析出的 API 结构（可直接提交 /prompt）
  final Map<String, dynamic> workflowJson;

  ParsedWorkflow({
    required this.id,
    required this.serverId,
    required this.filename,
    required this.name,
    required this.sourceHash,
    required this.parsedAt,
    required this.workflowJson,
  });

  int? _sizeCache;

  /// 占用字节数（按 UTF-8 编码后的实际长度，首次调用后缓存）
  int get sizeBytes =>
      _sizeCache ??= utf8.encode(jsonEncode(workflowJson)).length;

  /// 是否为合法的 API prompt 形态。
  ///
  /// 早期版本取错过 `graphToPrompt` 的字段（把 UI 图当结果存了），
  /// 载入时据此把坏数据过滤掉——重新解析一次即可恢复，无需迁移。
  bool get isApiShaped => WorkflowApiConverter.isApiShape(workflowJson);

  factory ParsedWorkflow.fromJson(Map<String, dynamic> json) {
    return ParsedWorkflow(
      id: json['id'] as String,
      serverId: json['serverId'] as String? ?? '',
      filename: json['filename'] as String? ?? '',
      name: json['name'] as String? ?? '',
      sourceHash: json['sourceHash'] as String? ?? '',
      parsedAt: json['parsedAt'] as int? ?? 0,
      workflowJson: Map<String, dynamic>.from(
        json['workflowJson'] as Map? ?? {},
      ),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'serverId': serverId,
    'filename': filename,
    'name': name,
    'sourceHash': sourceHash,
    'parsedAt': parsedAt,
    'workflowJson': workflowJson,
  };
}
