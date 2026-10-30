import 'image_ref.dart';
import 'node_role.dart';
import 'workflow_node_parser.dart';
import '../utils.dart';

/// 一次生成"喂进去"的一张图。
///
/// 不是所有工作流都有参考图（文生图没有），也不是每张都能取回来
/// （服务器 input 目录里的文件可能已被清理）。这里只负责**认出有哪些**，
/// 取图与展示由界面负责。
///
/// ⚠️ **只读工作流与已落盘的参数，不猜**（数据来源红线）：
/// 判定口径与配置页画"图片上传卡"用的是同一个 —— [kImageParamKeys]。
/// 不用类名白名单（custom 节点必然漏），也不按值猜扩展名
/// （实测 31 个工作流里按值判定额外命中 0 条，只会带来误判）。
class ReferenceImage {
  const ReferenceImage({
    required this.nodeId,
    required this.classType,
    required this.label,
    required this.paramKey,
    required this.ref,
    required this.fromParams,
    this.mergeCount = 1,
  });

  final String nodeId;

  /// 节点的 `class_type`。没有快照时为空串。
  final String classType;

  /// 节点官方名：`_meta.title` 优先，取不到退 `class_type`；两者都缺时退参数名。
  /// **不翻译、不自造**（与配置页 / 节点卡片同一口径）。
  final String label;

  /// `image` / `image_path`
  final String paramKey;

  /// 解析后的服务器图片位置（filename / subfolder / type）。
  final ImageRef ref;

  /// true = 本次实际提交的值（来自 `task.params`）；false = 工作流自带的值。
  final bool fromParams;

  /// 同一张图被几个节点共用。>1 时界面写「节点名 · 等 N 处」。
  final int mergeCount;

  /// 去重键：同一张图被两个节点用（图生图 + ControlNet 很常见）只留一条。
  String get dedupeKey => '${ref.type}|${ref.subfolder}|${ref.filename}';

  ReferenceImage _merged() => ReferenceImage(
    nodeId: nodeId,
    classType: classType,
    label: label,
    paramKey: paramKey,
    ref: ref,
    fromParams: fromParams,
    mergeCount: mergeCount + 1,
  );

  @override
  String toString() => 'ReferenceImage($label $paramKey -> ${ref.value})';
}

/// 从工作流 + 本次参数里收集参考图。
///
/// 取值优先级（逐条）：
/// 1. 遍历 [workflowJson] 每个节点的 `inputs`，**只取键 ∈ [kImageParamKeys]**；
/// 2. 值必须是字符串且非空，连线引用（`["节点id", 槽位]`）一律跳过 —— 那是上游输出，不是文件名；
/// 3. 过 [parseImageRef] 与 [isImageFilename]：挡掉 `example` 这种没有扩展名的占位值；
/// 4. [params] 里有同名键（本次实际提交的值）就**覆盖**工作流原值，标 `fromParams = true`；
/// 5. 按 [ReferenceImage.dedupeKey] 去重，重复的只累加 [ReferenceImage.mergeCount]。
///
/// [workflowJson] 为 null（极老记录没有快照）时退化成只扫 [params]：
/// 此时不知道节点的 `_meta.title`，[labelFallback] 给不到就用参数名，**不编节点名**。
///
/// 纯函数，只读传入的数据、不碰网络与磁盘，便于单测。
List<ReferenceImage> collectReferenceImages({
  required Map<String, dynamic>? workflowJson,
  Map<String, dynamic>? params,
  String Function(String nodeId)? labelFallback,
}) {
  final result = <ReferenceImage>[];
  final indexByName = <String, int>{};

  void add({
    required String nodeId,
    required String classType,
    required String label,
    required String paramKey,
    required String rawValue,
  }) {
    final ref = parseImageRef(rawValue);
    if (ref == null) return;
    // 只认真实图片文件名：`example` 这类占位值（ComfyUI 默认工作流里的）
    // 没有扩展名，显示出来就是一张注定 404 的破图
    if (!isImageFilename(ref.filename)) return;

    final item = ReferenceImage(
      nodeId: nodeId,
      classType: classType,
      label: label,
      paramKey: paramKey,
      ref: ref,
      fromParams: _paramValueOf(params, nodeId, paramKey) != null,
    );

    final existing = indexByName[item.dedupeKey];
    if (existing != null) {
      result[existing] = result[existing]._merged();
      return;
    }
    indexByName[item.dedupeKey] = result.length;
    result.add(item);
  }

  final workflow = workflowJson == null ? null : normalizeWorkflowJson(workflowJson);

  if (workflow != null) {
    workflow.forEach((nodeId, nodeData) {
      if (nodeData is! Map) return;
      final inputs = nodeData['inputs'];
      if (inputs is! Map) return;

      for (final key in kImageParamKeys) {
        // 值以 params 为准：用户本次改过图，工作流里那条就是过期信息
        final value = _paramValueOf(params, nodeId, key) ?? inputs[key];
        if (value is! String || value.trim().isEmpty) continue;

        final label = nodeLabelFromJson(nodeData);
        add(
          nodeId: nodeId,
          classType: nodeData['class_type']?.toString() ?? '',
          label: label.isEmpty
              ? (labelFallback?.call(nodeId) ?? key)
              : label,
          paramKey: key,
          rawValue: value,
        );
      }
    });
    return result;
  }

  // 没有快照：只能从已落盘的参数反推「哪个节点用了哪张图」。
  // 键形如 `<节点id>:image`，参数名里不可能出现冒号，切最后一个就够。
  if (params != null) {
    params.forEach((key, value) {
      if (value is! String || value.trim().isEmpty) return;
      final sep = key.lastIndexOf(':');
      if (sep <= 0) return;
      final paramKey = key.substring(sep + 1);
      if (!kImageParamKeys.contains(paramKey)) return;
      final nodeId = key.substring(0, sep);

      final fallback = labelFallback?.call(nodeId);
      add(
        nodeId: nodeId,
        classType: '',
        label: (fallback == null || fallback.isEmpty) ? paramKey : fallback,
        paramKey: paramKey,
        rawValue: value,
      );
    });
  }
  return result;
}

/// 只在 `params` 里能解析成图片位置时才算数；不能解析就当没给，让调用方回退工作流原值。
String? _paramValueOf(
  Map<String, dynamic>? params,
  String nodeId,
  String paramKey,
) {
  final value = params?[nodeParamKey(nodeId, paramKey)];
  if (value is! String || value.trim().isEmpty) return null;
  return value;
}
