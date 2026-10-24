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
String paramSummaryText(WorkflowNode node, AppLocalizations l) {
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

  final v = node.value;
  String valueStr = '';
  if (v != null) {
    valueStr = v.toString();
    if (valueStr.length > 20) valueStr = '${valueStr.substring(0, 20)}…';
  }
  return valueStr.isEmpty
      ? l.paramSummaryType(typeName)
      : l.paramSummaryTypeValue(typeName, valueStr);
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

/// 节点分组卡片的头部标签：优先展示节点标题（有辨识度），无有效标题回退类名。
String nodeGroupLabel(List<WorkflowNode> params, AppLocalizations l) {
  final classType = params.first.classType;
  final title = params.first.title;
  if (isMeaningfulTitle(title, classType)) {
    return title;
  }
  return classType;
}

/// 该节点在图里的角色说明（「正向条件」「起始采样」「胶片颗粒」…）。
///
/// 认不出来返回空串 —— **没有就别编**，宁可让用户只看类名，
/// 也好过贴一个猜错的角色（猜错的标签比没有标签更误导）。
String nodeRoleText(
  String nodeId,
  Map<String, NodeRole> roles,
  AppLocalizations l,
) {
  final role = roles[nodeId];
  if (role == null) return '';
  return switch (role.kind) {
    NodeRoleKind.positive => l.rolePositive,
    NodeRoleKind.negative => l.roleNegative,
    NodeRoleKind.baseSampler => l.roleBaseSampler,
    NodeRoleKind.refinerSampler => l.roleRefinerSampler,
    // 资源名不翻译：模型 / LoRA 是用户自己的文件
    NodeRoleKind.asset => role.assetName ?? '',
  };
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

  /// 非 null 时行尾出现移除按钮（主视图用它代替勾选框）。
  VoidCallback? onRemove,
}) {
  final l = AppLocalizations.of(context);
  final controllerKey = nodeParamKey(node.id, node.key);
  final controller = aliasControllers.putIfAbsent(
    controllerKey,
    () => TextEditingController(text: node.alias),
  );
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: ParamConfigTile(
      summary: paramSummaryText(node, l),
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
      onAliasChanged: (val) => node.alias = val,
      warning: paramWarningText(node, issues, l),
      showCheckbox: showCheckbox,
      onRemove: onRemove,
      removeTooltip: onRemove == null ? null : l.configRemoveParam,
    ),
  );
}
