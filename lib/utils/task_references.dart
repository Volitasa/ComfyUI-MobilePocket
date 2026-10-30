import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/task_history.dart';
import '../models/workflow_node.dart';
import '../providers/connection_provider.dart';
import '../providers/snapshot_provider.dart';
import '../providers/workflow_provider.dart';
import '../services/reference_image.dart';
import '../utils.dart';

/// 一条生成记录**这次实际喂进去的参考图**。
///
/// 两路合并（缺一路就会漏最常见的图生图场景）：
/// - `task.params`：本次真正提交的值（用户换过图就在这里）；
/// - `snapshot.workflowJson`：兜住"没暴露图片节点、但工作流自带一张图"的情况。
///
/// 生成记录页与画廊页共用这一份，别各写一遍 —— 两处口径一旦分叉，
/// 同一张图在两个页面会显示成不同的东西。
List<ReferenceImage> referenceImagesOf(WidgetRef ref, TaskHistory task) {
  final snapshotId = task.snapshotId;
  final snapshot = snapshotId == null
      ? null
      : ref.read(snapshotProvider.notifier).byId(snapshotId);

  // 没有快照时才需要它：名字从当前工作流配置里补，取不到就留空
  // （collector 会退回参数名，绝不自己编节点名）
  List<WorkflowNode>? config;
  String labelFallback(String nodeId) {
    config ??= ref
        .read(workflowProvider.notifier)
        .getMappingConfig(task.workflowId, serverId: task.serverId);
    for (final n in config ?? const <WorkflowNode>[]) {
      if (n.id != nodeId) continue;
      return isMeaningfulTitle(n.title, n.classType) ? n.title : n.classType;
    }
    return '';
  }

  return collectReferenceImages(
    workflowJson: snapshot?.workflowJson,
    params: task.params,
    labelFallback: labelFallback,
  );
}

/// 拼参考图地址该用哪台服务器。
///
/// 必须按**记录自己的** `serverId` 取，不能用当前连接：换了服务器之后
/// 那个文件名在对面根本不存在，拼出来的地址必然 404，看起来像图丢了。
///
/// 返回 null = 那台服务器已被移除（界面给占位，不要静默空白）。
String? baseUrlForServer(WidgetRef ref, String? serverId) {
  final config = ref.read(connectionProvider);
  if (serverId == null || serverId == config.activeServerId) {
    return config.comfyUrl;
  }
  for (final s in config.servers) {
    if (s.id == serverId) return s.primaryUrl;
  }
  return null;
}
