import '../models/workflow_node.dart';
import 'object_info_service.dart';

/// 提交前因为**服务器侧原因**被拦下的一种情况（方案 §3.7）。
///
/// 两个字段互斥：
/// - [classType] 非空 = 服务器缺少这个节点
/// - [alias] 非空 = 这个参数当前选的值服务器上没有
class SubmitBlock {
  const SubmitBlock.missingNode(String this.classType) : alias = null;

  const SubmitBlock.missingOption(String this.alias) : classType = null;

  final String? classType;
  final String? alias;
}

/// 提交前的服务器侧检查。返回 `null` 表示可以提交，否则返回**第一条**该拦下的问题。
///
/// 这里是方案 §3.7 的唯一实现。四种情况必须分开，因为它们对**同一种空响应**
/// 的处理是相反的 —— 混掉任何一个都会二选一错：
///
/// | 情况 | 判据 | 处理 |
/// |---|---|---|
/// | 缺节点 | 取数成功（`status == empty`，即 200 + `{}`） | **拦** |
/// | 缺参数 | 说明书里没这个键 | **放行**（版本差异，配置页已标黄） |
/// | 缺选项 | 下拉当前值不在服务器选项里 | **拦** |
/// | 取数失败 / 没问过 | `status == failure` 或 `null` | **放行**（不知道就别拦） |
///
/// ⚠️ 「缺选项」**只认模型 / 采样器类键**（[kDynamicOptionKeys]）：
/// `type` / `device` / `weight_dtype` 这类在同一台服务器的不同版本上选项就会变，
/// 全拦会大面积误伤正常提交（既有约定）。
///
/// 全部依赖都以回调传入，不碰 provider / 网络，便于单测。
SubmitBlock? checkBeforeSubmit({
  required Iterable<WorkflowNode> config,
  required ObjectInfoFetchStatus? Function(String classType) statusOf,
  required NodeInputSpec? Function(String classType, String key) specOf,
  required ParamControl Function(WorkflowNode node) controlOf,
  required String? Function(WorkflowNode node) currentOf,
}) {
  for (final node in config) {
    final status = statusOf(node.classType);

    // 没问过，或者上次没取到 → 我们不知道服务器认不认识它 → 放行
    if (status == null || status == ObjectInfoFetchStatus.failure) continue;

    // 服务器 200 明确回了 `{}`：这个节点在服务器上不存在
    if (status == ObjectInfoFetchStatus.empty) {
      return SubmitBlock.missingNode(node.classType);
    }

    // 取数成功：只有「下拉 + 模型/采样器类键」才查缺选项
    if (controlOf(node) != ParamControl.select) continue;
    if (!kDynamicOptionKeys.contains(node.key)) continue;

    final spec = specOf(node.classType, node.key);
    // 说明书里没这个键 = 缺参数，放行；没有选项也判断不了缺不缺
    if (spec == null || !spec.hasOptions) continue;
    if (!spec.contains(currentOf(node))) {
      return SubmitBlock.missingOption(node.alias);
    }
  }
  return null;
}
