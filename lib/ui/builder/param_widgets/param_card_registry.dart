import '../../../models/workflow_node.dart';

/// 运行页里「按节点定制」的卡片种类。
enum ParamCardKind { latentSize }

/// 一个节点组匹配到的自定义卡。
class ParamCardMatch {
  const ParamCardMatch(this.kind, this.params);

  final ParamCardKind kind;

  /// 该节点**实际暴露**的参数（配置页勾了哪些，这里就是哪些）
  final List<WorkflowNode> params;
}

/// 会生成 latent 的节点类名。
const Set<String> kLatentClassTypes = {
  'EmptyLatentImage',
  'EmptySD3LatentImage',
  'EmptyFluxLatentImage',
  'EmptyLatentImagePresets',
};

/// 判断这个节点组该用哪张自定义卡；匹配不上就返回 null，走通用渲染。
///
/// 两条硬条件：
/// 1. 类名要对得上（不同 latent 变体的参数键不一样，只能按类名认）；
/// 2. 参数键要真的存在 —— **只勾了 batch_size 就只有张数，只勾了 width
///    （没有 height）则完全不匹配**，不做半吊子适配。
ParamCardMatch? matchParamCard(List<WorkflowNode> params) {
  if (params.isEmpty) return null;

  final classType = params.first.classType;
  final keys = params.map((n) => n.key).toSet();

  if (kLatentClassTypes.contains(classType)) {
    final hasSize = keys.contains('width') && keys.contains('height');
    final hasBatch = keys.contains('batch_size');
    if (hasSize || hasBatch) {
      return ParamCardMatch(ParamCardKind.latentSize, params);
    }
  }

  // 其余节点：KSampler / LoRA / 图片 / 提示词等，后续按需在这里加分支
  return null;
}
