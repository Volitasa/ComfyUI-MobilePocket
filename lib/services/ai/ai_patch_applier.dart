import '../../models/ai_task.dart';
import '../../models/workflow_node.dart';

/// 写入失败的原因。UI 负责翻译成文案（不在这里拼字符串）。
enum AiApplyError {
  /// 工作流里找不到这个节点/参数（工作流被改过）
  nodeMissing,

  /// 目标不是字面量文本参数（连线、数值、枚举、图片都不许写）
  notTextParam,

  /// 不在本次 `@输出` 列表里 —— 防止 AI 顺手改别的节点
  notAllowed,

  /// 超过单参数长度上限
  tooLong,
}

/// 单条上限。与项目里其他长文本参数保持一致，不做特殊化。
const int kAiMaxPatchLength = 8000;

class AiApplyCheck {
  const AiApplyCheck(this.error);
  const AiApplyCheck.ok() : error = null;

  final AiApplyError? error;

  bool get ok => error == null;
}

/// 四条校验，缺一条都会出事故（尤其第 3 条：AI 顺手改负向词）。
AiApplyCheck validateAiPatch({
  required AiPatch patch,
  required List<WorkflowNode> nodes,
  required Set<String> allowedParamKeys,
}) {
  WorkflowNode? target;
  for (final node in nodes) {
    if (node.id == patch.node && node.key == patch.key) {
      target = node;
      break;
    }
  }
  if (target == null) return const AiApplyCheck(AiApplyError.nodeMissing);
  if (!isTextTargetNode(target)) {
    return const AiApplyCheck(AiApplyError.notTextParam);
  }
  if (!allowedParamKeys.contains('${patch.node}:${patch.key}')) {
    return const AiApplyCheck(AiApplyError.notAllowed);
  }
  if (patch.value.length > kAiMaxPatchLength) {
    return const AiApplyCheck(AiApplyError.tooLong);
  }
  return const AiApplyCheck.ok();
}
