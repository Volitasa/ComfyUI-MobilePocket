import '../models/workflow_node.dart';
import '../utils.dart';

/// 配置页「已放进表单」的参数怎么分段、段怎么排序 —— 纯逻辑，不碰 UI。
///
/// **段 = 同一个节点的全部已选参数**。配置页按段渲染，运行页按节点分卡，
/// 两边都是「按 node.id 分组、保持首次出现顺序」，所以配置页的段顺序
/// 就是运行页的卡片顺序，不需要任何换算（方案 v3 §3）。
class ParamSection {
  const ParamSection(this.nodeId, this.params)
    : assert(params.length > 0);

  final String nodeId;

  /// 该节点的已选参数，顺序沿用列表里的相对顺序。
  final List<WorkflowNode> params;
}

/// 按节点分组。[nodes] 应当已经过滤成「已放进表单」的那批。
///
/// 同一节点的参数在列表里**可以是不连续的**（历史上被移出过、或旧数据），
/// 分组会把它们拉到一起 —— 这与运行页 `putIfAbsent` 的行为一致。
List<ParamSection> buildParamSections(Iterable<WorkflowNode> nodes) {
  final groups = <String, List<WorkflowNode>>{};
  for (final n in nodes) {
    groups.putIfAbsent(n.id, () => <WorkflowNode>[]).add(n);
  }
  return [
    for (final entry in groups.entries) ParamSection(entry.key, entry.value),
  ];
}

/// 段重新排好后摊平回一条列表，供落盘 / 写回槽位。
List<WorkflowNode> flattenSections(List<ParamSection> sections) => [
  for (final s in sections) ...s.params,
];

/// 把重排后的已选序列写回原列表，未暴露的参数**原地不动**。
///
/// 为什么不能简单地把已选项排完塞到前面：那样未暴露的参数会被全部挤到末尾，
/// 「添加参数」页的节点顺序跟着乱掉。这里只回写已选项原本占据的下标槽位。
///
/// 调用方拿到的是新列表（不原地改 [all]），方便测试与 `setState` 比较。
List<WorkflowNode> withExposedOrder(
  List<WorkflowNode> all,
  List<WorkflowNode> ordered,
) {
  final slots = <int>[];
  for (var i = 0; i < all.length; i++) {
    if (all[i].exposed) slots.add(i);
  }
  final out = List<WorkflowNode>.of(all);
  for (var i = 0; i < slots.length && i < ordered.length; i++) {
    out[slots[i]] = ordered[i];
  }
  return out;
}

/// 新解析出的参数按**旧配置的节点块顺序**重排，保住用户排过的段顺序。
///
/// 排序键：
/// - 主键：该节点在旧配置里首次出现的下标；旧配置里没有的节点排到末尾。
/// - 次级：参数在旧配置里的下标；旧配置里没有的参数插到**自己节点块的末尾**
///   （`块末位 + 0.5`），而不是整表末尾 —— 服务器新增参数时它属于哪个节点就留在哪个节点旁边。
/// - 兜底：解析顺序。**必须显式写** —— Dart 的 `List.sort` 不稳定。
///
/// ⚠️ 不看 `exposed`：未暴露的参数也要跟着走，否则下次勾选回来时顺序是乱的。
List<WorkflowNode> orderLikeSavedConfig(
  List<WorkflowNode> nodes,
  List<WorkflowNode> saved,
) {
  if (saved.isEmpty) return nodes;

  final paramIndex = <String, double>{};
  final nodeLast = <String, double>{};
  for (var i = 0; i < saved.length; i++) {
    paramIndex.putIfAbsent(
      nodeParamKey(saved[i].id, saved[i].key),
      () => i.toDouble(),
    );
    nodeLast[saved[i].id] = i.toDouble();
  }
  final tail = saved.length.toDouble();

  final keyed = <({double order, int index, WorkflowNode node})>[];
  for (var i = 0; i < nodes.length; i++) {
    final n = nodes[i];
    final savedIdx = paramIndex[nodeParamKey(n.id, n.key)];
    final order = savedIdx ?? (nodeLast[n.id] ?? tail) + 0.5;
    keyed.add((order: order, index: i, node: n));
  }

  keyed.sort((a, b) {
    final byOrder = a.order.compareTo(b.order);
    if (byOrder != 0) return byOrder;
    return a.index.compareTo(b.index);
  });
  return [for (final k in keyed) k.node];
}
