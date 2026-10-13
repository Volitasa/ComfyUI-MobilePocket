import 'package:comfyui_mobilepocket/l10n/app_localizations.dart';

import '../utils.dart';
import 'workflow_node.dart';

/// 工作流快照：某次运行时固化下来的「工作流 JSON + 节点暴露配置」。
///
/// 与线上工作流解耦：即便服务端那份文件被删除或被改动，
/// 生成记录依然可以凭快照「再次运行」。
class WorkflowSnapshot {
  /// 唯一键，由工作流 JSON 内容哈希决定（不含节点配置）。
  ///
  /// 刻意不含 mappingConfig —— 用户调整暴露节点后快照 id 必须保持不变，
  /// 否则已存在的生成记录会指向一个失效的快照。
  final String id;

  /// 展示名：来源名 + 固化时间。**仅用于显示**，可能重名，不能当键用。
  ///
  /// 刻意不落盘：它由 [sourceName] 与时间戳推导，固化进磁盘会把当时的
  /// 语言与时间格式一起写死（切语言后残留旧文案）。按当前语言实时生成。
  String displayName(AppLocalizations l) =>
      '${workflowDisplayNameOr(l, sourceName)} · ${formatSnapshotStamp(createdAt)}';

  /// 来源工作流名（已去掉 _api.json 后缀）。
  ///
  /// 本地库里已删除、或解析缓存已清除时为空串，展示层按当前语言补默认名。
  final String sourceName;

  /// 首次固化的时间戳（毫秒）
  final int createdAt;

  /// 固化时所属的服务器 ID，用于再次运行时提示环境差异
  final String? serverId;

  /// 原始工作流 JSON（未填参），供再次解析／重新配置暴露节点
  final Map<String, dynamic> workflowJson;

  /// 快照私有的节点暴露配置。修改后只写回这里，不写线上 mapping_。
  final List<WorkflowNode> mappingConfig;

  const WorkflowSnapshot({
    required this.id,
    required this.sourceName,
    required this.createdAt,
    this.serverId,
    required this.workflowJson,
    required this.mappingConfig,
  });

  /// 快照占用的大致字节数（用于设置页展示）
  int get sizeBytes => workflowJson.length * 64 + mappingConfig.length * 128;

  factory WorkflowSnapshot.fromJson(Map<String, dynamic> json) {
    final rawConfig = json['mappingConfig'];
    return WorkflowSnapshot(
      id: json['id'] as String,
      // 旧版本曾把「本地导入」等翻译文案写进 sourceName，这里一并清洗
      sourceName: cleanStoredWorkflowName(json['sourceName'] as String?) ?? '',
      createdAt: json['createdAt'] as int? ?? 0,
      serverId: json['serverId'] as String?,
      workflowJson: Map<String, dynamic>.from(
        json['workflowJson'] as Map? ?? {},
      ),
      mappingConfig: rawConfig is List
          ? rawConfig
                .map(
                  (e) => WorkflowNode.fromJson(
                    Map<String, dynamic>.from(e as Map),
                  ),
                )
                .toList()
          : const [],
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'sourceName': sourceName,
    'createdAt': createdAt,
    'serverId': serverId,
    'workflowJson': workflowJson,
    'mappingConfig': mappingConfig.map((e) => e.toJson()).toList(),
  };
}
