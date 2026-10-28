import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/workflow_node.dart';
import '../../services/node_role.dart';
import '../../services/workflow_node_parser.dart';
import '../../utils.dart';
import '../widgets/param_config_tile.dart';

/// 配置页与「添加参数」页共用的参数行逻辑。
///
/// 抽出来的原因只有一个：**同一行在两个页面里必须长得一模一样**。
/// 主视图只放已选参数、添加页放全部参数，如果各自实现一遍，
/// 别名框 / 告警 / 摘要迟早会漂移成两套皮肤。
///
/// [nodeLabel] **非 null 即「主视图模式」**：行尾写「节点名 · 当前值」。
/// 那一页的参数是**混着排**的，用户看不出这一行属于哪个节点；
/// 而「类型: 选项」这种信息给不出下一步动作。
/// 传空串表示「这一行不用重复节点名」（别名本身就是节点名），此时只写当前值 ——
/// ⚠️ 不能传回 null 退回类型摘要，否则同一份列表里有的行写节点、有的行写类型。
/// 添加页的卡片本身按节点分组、节点名就在卡片头上，那边保持「类型 · 当前值」。
String paramSummaryText(
  WorkflowNode node,
  AppLocalizations l, {
  String? nodeLabel,
}) {
  final valueStr = _paramValueText(node);

  if (nodeLabel != null) {
    if (nodeLabel.isEmpty) return valueStr;
    return valueStr.isEmpty
        ? nodeLabel
        : l.paramSummaryNodeValue(nodeLabel, valueStr);
  }

  // ⚠️ 有 `control` 时按**控件形态**显示类型名，否则会出现
  // 「摘要写着"文本"，运行页却是个下拉框」的不一致（方案 §8.1 陷阱 3）。
  final control = node.control;
  final String typeName;
  if (control == ParamControl.select) {
    typeName = l.paramTypeEnum;
  } else {
    typeName =
        {
          ParamType.text: l.paramTypeText,
          ParamType.seed: l.paramTypeSeed,
          ParamType.image: l.paramTypeImage,
          ParamType.intType: l.paramTypeInt,
          ParamType.float: l.paramTypeFloat,
          ParamType.boolType: l.paramTypeBool,
          ParamType.enumType: l.paramTypeEnum,
        }[node.paramType] ??
        l.paramTypeDefault;
  }

  return valueStr.isEmpty
      ? l.paramSummaryType(typeName)
      : l.paramSummaryTypeValue(typeName, valueStr);
}

/// 当前值的单行展示：太长就在中间截断（行尾还有一层省略号）。
String _paramValueText(WorkflowNode node) {
  final v = node.value;
  if (v == null) return '';
  var s = v.toString();
  if (s.length > 20) s = '${s.substring(0, 20)}…';
  return s;
}

/// 该参数的行级告警文案；没问题返回 null。
///
/// ⚠️ 只标黄、**不拦** —— 缺参数通常只是服务器节点版本不同，
/// 照旧提交原值比拦下来更有用（方案 §3.7）。拦截逻辑在 C4。
String? paramWarningText(
  WorkflowNode node,
  SpecIssues issues,
  AppLocalizations l,
) {
  if (issues.isNodeMissing(node.classType)) {
    return l.configNodeMissingOnServer(node.classType);
  }
  if (issues.isParamMissing(node.id, node.key)) {
    return l.configParamMissingOnServer;
  }
  return null;
}

/// 节点的**官方名**：工作流里的节点标题优先，取不到就是类名。
///
/// ⚠️ 不翻译、也不自己起名 —— 「K采样器」「加载VAE」都是 ComfyUI 自己的
/// 节点名，我们只是把它读出来。
String nodeLabelOf(WorkflowNode node) {
  final title = node.title.trim();
  return isMeaningfulTitle(title, node.classType) ? title : node.classType;
}

/// 节点分组卡片的头部标签：就是该节点的官方名（见 [nodeLabelOf]）。
String nodeGroupLabel(List<WorkflowNode> params) => nodeLabelOf(params.first);

/// 该节点在图里的位置说明（「连到 K采样器 · positive」「连到 VAE解码 · vae」…）。
///
/// 卡片上这句话只回答一件事：**它的输出接去哪**。接了好几处就写第一处 + 「等 N 处」，
/// 不藏也不硬挑一个当成唯一。没有下游返回空串 —— **没有就别编**。
String nodeRoleText(
  String nodeId,
  Map<String, NodeRole> roles,
  AppLocalizations l,
) {
  final links = roles[nodeId]?.links ?? const <NodeLink>[];
  if (links.isEmpty) return '';
  final first = links.first;
  return links.length == 1
      ? l.roleLinksTo(first.label, first.slot)
      : l.roleLinksToMany(first.label, first.slot, links.length);
}

/// 用途分类的段标题。
String categoryLabel(ParamCategory category, AppLocalizations l) =>
    switch (category) {
      ParamCategory.prompt => l.categoryPrompt,
      ParamCategory.sampling => l.categorySampling,
      ParamCategory.size => l.categorySize,
      ParamCategory.model => l.categoryModel,
      ParamCategory.control => l.categoryControl,
      ParamCategory.other => l.categoryOther,
    };

/// 分段的固定顺序：从「最常改的」到「最不常改的」。
const List<ParamCategory> kCategoryOrder = [
  ParamCategory.prompt,
  ParamCategory.sampling,
  ParamCategory.size,
  ParamCategory.model,
  ParamCategory.control,
  ParamCategory.other,
];

/// 一条参数行：勾选 + 别名编辑 + 类型/当前值摘要。
///
/// [aliasControllers] 由调用方持有（挂在页面 State 上随页面销毁），
/// 这里只按 `nodeParamKey` 取用 / 惰性创建 —— 两个页面共用同一份，
/// 否则在添加页改了别名、回主视图又变回旧的。
///
/// [showCheckbox] 与 [onRemove] 二选一，见 `ParamConfigTile` 上的说明。
///
/// [showNodeInSummary] 为 true 时行尾写「属于哪个节点 · 当前值」（主视图用）。
/// 别名恰好就是节点名时不再重复一遍 —— 那行字本身已经是节点名了。
Widget buildParamConfigRow(
  BuildContext context, {
  required WorkflowNode node,
  required Map<String, TextEditingController> aliasControllers,
  required SpecIssues issues,

  /// 勾选/移出已经改完数据，这个回调只负责让页面重建。
  ///
  /// 数据改动必须发生在调用方的 State 里（`setState`），否则
  /// 受控的 Checkbox 点了没反应。
  required VoidCallback onChanged,
  bool showCheckbox = true,

  /// 行尾是否带上「属于哪个节点」。见 [paramSummaryText]。
  bool showNodeInSummary = false,

  /// 非 null 时行尾出现移除按钮（主视图用它代替勾选框）。
  VoidCallback? onRemove,

  /// 别名框聚焦变化，见 `ParamConfigTile.onFocusChanged`。
  ValueChanged<bool>? onFocusChanged,
}) {
  final l = AppLocalizations.of(context);
  final controllerKey = nodeParamKey(node.id, node.key);
  final controller = aliasControllers.putIfAbsent(
    controllerKey,
    () => TextEditingController(text: node.alias),
  );
  final label = nodeLabelOf(node);
  // 别名本身就是节点名时不重复那一遍，行尾只留当前值
  final nodeInSummary = !showNodeInSummary
      ? null
      : (label.isNotEmpty && controller.text.trim() != label ? label : '');
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: ParamConfigTile(
      summary: paramSummaryText(node, l, nodeLabel: nodeInSummary),
      exposed: node.exposed,
      onChanged: showCheckbox
          ? (val) {
              node.exposed = val ?? false;
              onChanged();
            }
          : null,
      aliasController: controller,
      aliasHint: l.paramAliasHint,
      // 保存时用的是 node.alias，控制器文本必须回写，否则改了不生效
      onAliasChanged: (val) {
        node.alias = val;
        // 主视图行尾要不要带节点名，取决于别名长什么样（见 [paramSummaryText]），
        // 改名后就得重算一次；添加页行尾与别名无关，不必跟着重建。
        if (showNodeInSummary) onChanged();
      },
      warning: paramWarningText(node, issues, l),
      showCheckbox: showCheckbox,
      onRemove: onRemove,
      removeTooltip: onRemove == null ? null : l.configRemoveParam,
      onFocusChanged: onFocusChanged,
    ),
  );
}
