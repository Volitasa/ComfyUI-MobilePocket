import '../utils.dart';

/// 一条下游连线：接到了哪个节点的哪个输入。
///
/// 两个名字都来自工作流本身 —— `label` 取下游节点的 `_meta.title`（ComfyUI
/// 前端给的节点名），取不到退类名；`slot` 取下游节点 `inputs` 里的 key。
typedef NodeLink = ({String label, String slot});

/// 节点在图里的位置：**同一类节点出现好几个时，用来区分谁是谁**。
///
/// 工作流里三个 `CLIPTextEncode` 都叫「CLIP文本编码」，两个 `KSampler` 都叫
/// 「K采样器」—— 光看类名用户没法判断该改哪个。真正的区别在图里：
/// 一个把结果送进采样器的 `positive`、一个送进 `negative`。
///
/// 这里做的就是把**拓扑翻译成一句话**，而不是去画那张图：
/// 手机上画 ComfyUI 的节点图既不现实也没必要（用户的任务是挑参数，不是读拓扑）。
///
/// ⚠️ **卡片上那句话的语义只有一个：这个节点的输出接去哪**（用户 2026-10-26
/// 指出加载类显示模型名是两套口径）。所以加载类也走连线，不再另写「装了什么」——
/// 装的哪个模型，卡片里那行参数本身就写着当前值。
///
/// ⚠️ 名字**只读不造**：不许自己发明概念（曾经的「起始采样 / 精修采样」就是这么
/// 来的，已删），也不许翻译节点名与输入名。
class NodeRole {
  const NodeRole(this.links);

  /// 去重后的下游连线，按工作流里的出现顺序；至少一条。
  final List<NodeLink> links;
}

/// 推断每个节点在图里的位置。没有下游的节点不给（不出现在结果里），**绝不硬猜**。
///
/// 纯函数，便于单测；只读工作流 JSON，不碰服务器。
Map<String, NodeRole> inferNodeRoles(Map<String, dynamic> jsonMap) {
  // 反向索引：某个节点的输出被谁、接到哪个槽位上。
  // 工作流 JSON 里输入是 `[上游节点id, 输出序号]`，顺着扫一遍就能反推。
  final consumers = <String, List<({String id, String slot})>>{};
  jsonMap.forEach((nodeId, nodeData) {
    if (nodeData is! Map) return;
    final inputs = nodeData['inputs'];
    if (inputs is! Map) return;
    inputs.forEach((slot, raw) {
      if (raw is List && raw.isNotEmpty && raw[0] is String) {
        consumers.putIfAbsent(raw[0] as String, () => []).add((
          id: nodeId,
          slot: slot.toString(),
        ));
      }
    });
  });

  final roles = <String, NodeRole>{};
  consumers.forEach((nodeId, list) {
    final links = <NodeLink>[];
    for (final c in list) {
      final label = nodeLabelFromJson(jsonMap[c.id]);
      if (label.isEmpty) continue;
      final link = (label: label, slot: c.slot);
      // 两个同名节点接同一个槽（两个文本编码都吃 `clip`）算同一处 ——
      // 否则「加载CLIP」会写成「等 2 处」，两处却长得一模一样
      if (!links.contains(link)) links.add(link);
    }
    if (links.isEmpty) return;

    // `positive` / `negative` 提到最前面：任务里最容易混淆的就是这一对，
    // 卡片上显示第一处，应该显示出最有用的那处。
    final cond = links.indexWhere((l) => _isConditioningSlot(l.slot));
    if (cond > 0) links.insert(0, links.removeAt(cond));

    roles[nodeId] = NodeRole(links);
  });

  return roles;
}

bool _isConditioningSlot(String slot) {
  final s = slot.toLowerCase();
  return s.contains('positive') || s.contains('negative');
}

/// 节点的官方名：前端给的标题（`_meta.title`）优先，取不到就是类名。
///
/// ⚠️ 这两个都来自工作流本身，**不翻译、也不自己起名** ——
/// 界面上出现「K采样器」「加载VAE」是 ComfyUI 自己的中文节点名，
/// 我们只是把它读出来。
///
/// 公开：参考图列表也要用同一套命名口径（`services/reference_image.dart`），
/// 抄一份私有实现迟早两处漂移。
///
/// 名字带 `FromJson` 是为了和 `param_row_helpers.nodeLabelOf(WorkflowNode)` 区分：
/// 那个吃已解析的模型，这个吃工作流里的原始节点 Map，语义一致、入口不同。
String nodeLabelFromJson(dynamic nodeData) {
  if (nodeData is! Map) return '';
  final classType = nodeData['class_type']?.toString() ?? '';
  final meta = nodeData['_meta'];
  final title = meta is Map ? (meta['title']?.toString() ?? '') : '';
  return isMeaningfulTitle(title, classType) ? title.trim() : classType;
}
