import 'package:comfyui_mobilepocket/l10n/app_localizations.dart';

import '../models/workflow_node.dart';
import '../utils.dart';
import 'object_info_service.dart';

/// 语义上一定是**小数**的参数名。
///
/// 存在的理由：工作流 JSON 里只有值、没有类型。`{"denoise": 1}` 会被
/// 按值推断成整数，于是运行页给了不带小数点的键盘，用户想填 0.5 打不进去；
/// 就算想办法填了，`int.tryParse` 也会返回 null，然后把 null 提交给服务器。
const Set<String> kFloatParamKeys = {
  'denoise',
  'strength',
  'strength_model',
  'strength_clip',
  'weight',
  'weight_faceidv2',
  'upscale_by',
  'sensitivity',
  'bridge_noise_sigma',
  'mask_blur',
  'mask_offset',
  'blur',
  'start_percent',
  'end_percent',
  'start_at',
  'end_at',
  'codeformer_weight',
  'face_restore_visibility',
};

/// 语义上一定是**整数**的参数名。
const Set<String> kIntParamKeys = {
  'steps',
  'width',
  'height',
  'batch_size',
  'resolution',
  'grow_mask_by',
  'left',
  'top',
  'right',
  'bottom',
  'force_rate',
  'custom_width',
  'custom_height',
  'frame_load_cap',
  'skip_first_frames',
  'select_every_nth',
  'loop_count',
  'frame_rate',
  'pyrUp_iters',
  'low_threshold',
  'high_threshold',
  'detect_hand',
  'detect_body',
  'detect_face',
};

/// 语义上是随机种子的参数名。
///
/// 更可靠的做法是用服务器说明书里的 `control_after_generate` 标记来认，
/// 这张表只是没有说明书时的兜底（见 [WorkflowNodeParser] 说明）。
const Set<String> kSeedParamKeys = {'seed', 'noise_seed', 'rand_seed'};

/// 语义上是「图片上传框」的参数名。
///
/// ⚠️ 不能靠类型判断：服务器说明书里 `LoadImage.image` 就是一串文件名列表，
/// 类型上跟普通下拉框没区别。上传框只能在这里点名。
const Set<String> kImageParamKeys = {'image', 'image_path'};

/// 单个节点类型的解析规则。
///
/// 之所以是「手写一张表」而不是继续靠猜：
/// - 工作流 JSON 里只有值没有类型，按值推断会判错；
/// - 社区节点的类名五花八门，靠枚举类名必然漏，但
///   「某一类节点该暴露哪几个参数」是稳定的，适合写死。
///
/// 参数的用途分类。**只用于界面分段**，不影响收录与默认勾选。
///
/// 规则表刻意不裁剪识别范围（见 [NodeRule.keys]），所以分类不是过滤器 ——
/// 它只是给已经列出来的参数找一个好找的位置：提示词归提示词、采样归采样。
/// 认不出来的落进 [other]，照样出现在列表末尾，一个都不少。
enum ParamCategory {
  prompt, // 提示词 / 文本
  sampling, // 采样器、调度器
  size, // 画布尺寸、放大
  model, // 模型 / LoRA / 权重加载
  control, // ControlNet、IPAdapter、换脸、去背等附加控制
  other,
}

/// 每条规则只回答四个问题：认哪些类名、暴露哪些参数、参数各是什么类型、
/// 以及它们归到哪个用途段。
class NodeRule {
  const NodeRule({
    required this.classTypes,
    this.keys,
    this.forceTypes = const {},
    this.defaultExposedKeys,
    this.category = ParamCategory.other,
  });

  /// 该规则覆盖的 class_type。写多个是为了容纳变体名
  /// （如 `UnetLoaderGGUF`、`LoraLoaderModelOnly`）。
  final Set<String> classTypes;

  /// 该节点「值得在手机上调」的参数名。
  ///
  /// ⚠️ **不限制列表**，只参与默认勾选的判定：没写在这里的参数照样出现在
  /// 配置页，只是默认不勾。这是刻意的 —— 10-15 实测 1500 多种节点类型里
  /// 上千种本身带可调参数，按名单把没收录的参数过滤掉，用户就彻底拿不到了
  /// （「减少识别范围」在这项目里已被判定为反向优化）。少勾几项用户能自己
  /// 补上，参数压根不出现就没得补。
  ///
  /// 为 null 时该节点全部参数默认勾选（此时 [defaultExposedKeys] 不生效）。
  final Set<String>? keys;

  /// 强制类型：优先于按值推断，用于纠正 `denoise` 这类误判。
  final Map<String, ParamType> forceTypes;

  /// 默认勾选的参数名。为 null 时全部默认勾选（见 [keys]）。
  final Set<String>? defaultExposedKeys;

  /// 用途分类。见 [ParamCategory]：只决定在界面上摆在哪一段。
  final ParamCategory category;

  bool matches(String classType) => classTypes.contains(classType);
}

/// 工作流与服务器说明书的「对不上」情况。**只在内存里，不落盘**（方案 §3.2）。
///
/// 存在的意义是配置页标黄：让用户知道某参数在服务器上可能不存在，
/// 但**不阻止**勾选与提交（方案 §3.7：缺参数只标黄、不拦）。
class SpecIssues {
  const SpecIssues({
    this.missingNodeTypes = const {},
    this.missingParamKeys = const {},
  });

  /// 服务器不认识的节点类名（问到了，但响应是 `{}`）。
  final Set<String> missingNodeTypes;

  /// 说明书里找不到的参数，键为 `nodeParamKey(id, key)`。
  final Set<String> missingParamKeys;

  bool get isEmpty => missingNodeTypes.isEmpty && missingParamKeys.isEmpty;
  bool get isNotEmpty => !isEmpty;

  /// 该节点是否整个在服务器上不存在。
  bool isNodeMissing(String classType) => missingNodeTypes.contains(classType);

  /// 该参数是否在说明书里找不到。
  bool isParamMissing(String nodeId, String key) =>
      missingParamKeys.contains(nodeParamKey(nodeId, key));
}

/// 内置规则表。
///
/// 按「用途」分组，而不是按包名/来源 —— 同一个功能（比如加载 LoRA）
/// 在不同机器上装的类名不一样，分组写在一起才好维护。
const List<NodeRule> kDefaultNodeRules = [
  // ── 采样器 ───────────────────────────────────────────────
  NodeRule(
    category: ParamCategory.sampling,
    classTypes: {'KSampler'},
    forceTypes: {'denoise': ParamType.float},
  ),
  NodeRule(
    category: ParamCategory.sampling,
    classTypes: {'KSamplerAdvanced'},
    forceTypes: {'denoise': ParamType.float},
  ),
  NodeRule(
    category: ParamCategory.sampling,
    classTypes: {'SamplerCustom', 'SamplerCustomAdvanced'},
    forceTypes: {'denoise': ParamType.float},
  ),
  NodeRule(
    category: ParamCategory.sampling,
    classTypes: {'BasicScheduler'},
    keys: {'steps', 'scheduler', 'denoise'},
    defaultExposedKeys: {'steps', 'scheduler', 'denoise'},
  ),
  NodeRule(
    category: ParamCategory.sampling,
    classTypes: {'KSamplerSelect'},
    keys: {'sampler_name'},
    defaultExposedKeys: {'sampler_name'},
  ),

  // ── 文本 / 提示词 ──────────────────────────────────────
  NodeRule(
    category: ParamCategory.prompt,
    classTypes: {
      'CLIPTextEncode',
      'Text Multiline',
      'Text box',
      'String Input',
      'Text Input',
      'PrimitiveStringMultiline',
    },
  ),
  NodeRule(
    category: ParamCategory.prompt,
    classTypes: {'Text Concatenate'},
    keys: {'delimiter', 'clean_whitespace', 'text_a', 'text_b'},
    defaultExposedKeys: {'delimiter', 'text_a', 'text_b'},
  ),

  // ── 尺寸 / 放大 ──────────────────────────────────────
  NodeRule(category: ParamCategory.size, classTypes: {'EmptyLatentImage'}),
  NodeRule(
    category: ParamCategory.size,
    classTypes: {'EmptySD3LatentImage', 'EmptyFluxLatentImage'},
  ),
  NodeRule(category: ParamCategory.size, classTypes: {'LatentUpscale'}),
  NodeRule(category: ParamCategory.size, classTypes: {'LatentUpscaleBy'}),
  NodeRule(category: ParamCategory.size, classTypes: {'ImageScaleBy'}),
  NodeRule(category: ParamCategory.size, classTypes: {'ImageUpscaleWithModel'}),
  NodeRule(category: ParamCategory.size, classTypes: {'UpscaleModelLoader'}),

  // ── 模型加载 ──────────────────────────────────────────
  NodeRule(
    category: ParamCategory.model,
    classTypes: {'CheckpointLoaderSimple'},
  ),
  NodeRule(
    category: ParamCategory.model,
    classTypes: {'UNETLoader', 'UnetLoaderGGUF', 'UnetLoaderGGUFAdvanced'},
  ),
  NodeRule(
    category: ParamCategory.model,
    classTypes: {'CLIPLoader', 'CLIPLoaderGGUF'},
  ),
  NodeRule(category: ParamCategory.model, classTypes: {'VAELoader'}),
  NodeRule(category: ParamCategory.model, classTypes: {'CLIPVisionLoader'}),

  // ── LoRA / 补丁加载 ────────────────────────────────────
  NodeRule(
    category: ParamCategory.model,
    classTypes: {'LoraLoader', 'LoraLoaderModelOnly', 'ModelPatchLoader'},
    forceTypes: {
      'strength_model': ParamType.float,
      'strength_clip': ParamType.float,
    },
  ),

  // ── ControlNet ──────────────────────────────────────────
  NodeRule(category: ParamCategory.control, classTypes: {'ControlNetLoader'}),
  NodeRule(
    category: ParamCategory.control,
    classTypes: {'ControlNetApplyAdvanced'},
    defaultExposedKeys: {'strength'},
    forceTypes: {
      'strength': ParamType.float,
      'start_percent': ParamType.float,
      'end_percent': ParamType.float,
    },
  ),
  NodeRule(
    category: ParamCategory.control,
    classTypes: {'SetUnionControlNetType'},
  ),

  // ── IPAdapter ──────────────────────────────────────────
  NodeRule(
    category: ParamCategory.control,
    classTypes: {'IPAdapter', 'IPAdapterFaceID'},
    defaultExposedKeys: {'weight'},
    forceTypes: {
      'weight': ParamType.float,
      'start_at': ParamType.float,
      'end_at': ParamType.float,
    },
  ),
  NodeRule(
    category: ParamCategory.control,
    classTypes: {'IPAdapterNoise'},
    defaultExposedKeys: {'strength'},
    forceTypes: {'strength': ParamType.float},
  ),
  NodeRule(
    category: ParamCategory.control,
    classTypes: {'IPAdapterUnifiedLoaderFaceID'},
  ),
  NodeRule(
    category: ParamCategory.control,
    classTypes: {'IPAdapterInsightFaceLoader'},
  ),

  // ── 换脸 / 人脸 ────────────────────────────────────────
  NodeRule(
    category: ParamCategory.control,
    classTypes: {'ReActorFaceSwap'},
    keys: {'enabled', 'swap_model', 'facedetection', 'face_restore_visibility'},
    defaultExposedKeys: {'enabled', 'swap_model'},
  ),

  // ── 去背 / 掩码合成 ────────────────────────────────────
  NodeRule(
    category: ParamCategory.control,
    classTypes: {'RMBG'},
    keys: {'model', 'sensitivity', 'process_res'},
  ),
  NodeRule(category: ParamCategory.control, classTypes: {'FeatherMask'}),
  NodeRule(
    category: ParamCategory.control,
    classTypes: {'ImageCompositeMasked'},
  ),

  // ── ControlNet 预处理器（手机上最常调的是分辨率）──────
  NodeRule(
    category: ParamCategory.control,
    classTypes: {
      'DWPreprocessor',
      'DepthAnythingV2Preprocessor',
      'DensePosePreprocessor',
      'CannyEdgePreprocessor',
      'TilePreprocessor',
      'HEDPreprocessor',
    },
    keys: {'resolution'},
  ),
];

/// 工作流 → 可配置节点列表的解析器（纯函数，便于单测）。
class WorkflowNodeParser {
  const WorkflowNodeParser._();

  /// 内置规则（供测试替换）。
  static List<NodeRule> get defaultRules => kDefaultNodeRules;

  /// 按 class_type 找规则；找不到返回 null。
  static NodeRule? ruleFor(String classType, {List<NodeRule>? rules}) {
    for (final r in rules ?? defaultRules) {
      if (r.matches(classType)) return r;
    }
    return null;
  }

  /// 该节点类型在界面上归到哪个用途段；认不出来归 [ParamCategory.other]。
  ///
  /// 不落盘：分类随时能从 class_type 重算，存一份只会多一处要同步的东西。
  static ParamCategory categoryFor(String classType, {List<NodeRule>? rules}) =>
      ruleFor(classType, rules: rules)?.category ?? ParamCategory.other;

  /// 解析工作流 JSON，得到「可配置参数」列表。
  ///
  /// 口径：
  /// - 命中规则表 → 按规则决定默认勾选（可指定强制类型）；
  /// - 未命中 → 可填参数全部列出来，但只默认勾选高频参数（见 [_defaultExposed]）。
  static List<WorkflowNode> parse(
    Map<String, dynamic> jsonMap, {
    required AppLocalizations l,
    List<NodeRule>? rules,
    Map<String, NodeSpec>? specs,
  }) {
    final nodes = <WorkflowNode>[];

    jsonMap.forEach((nodeId, nodeData) {
      if (nodeData is! Map) return;

      final classType = nodeData['class_type'] as String?;
      final inputs = nodeData['inputs'] as Map<String, dynamic>?;
      final meta = nodeData['_meta'] as Map<String, dynamic>?;

      if (classType == null || inputs == null) return;

      final title = meta?['title'] as String? ?? 'Node $nodeId';
      final rule = ruleFor(classType, rules: rules);

      final forceTypes = rule?.forceTypes ?? const <String, ParamType>{};

      // 先收出「这个节点真正会生成参数的键」，再确定每个键的类型。
      // 需要这个数量是为了别名回退：节点标题只有在一个参数时才有区分度。
      final resolved = <String, ParamType>{};
      inputs.forEach((key, rawValue) {
        if (isLinkReference(rawValue)) return; // 连线引用不暴露
        final type = resolveType(key, rawValue, forceTypes);
        if (type != null) resolved[key] = type;
      });

      resolved.forEach((key, type) {
        final rawValue = inputs[key];
        final spec = specs?[classType]?[key];
        nodes.add(
          WorkflowNode(
            id: nodeId,
            classType: classType,
            key: key,
            alias: defaultAlias(
              key,
              title,
              classType,
              l,
              onlyParam: resolved.length == 1,
            ),
            title: title,
            exposed: _defaultExposed(rule, key),
            paramType: type,
            options: type == ParamType.enumType
                ? enumOptions(rawValue)
                : const [],
            value: normalizeValue(type, rawValue),
            control: resolveControl(
              key: key,
              rawValue: rawValue,
              paramType: type,
              spec: spec,
            ),
            bounds: spec?.toBounds(),
          ),
        );
      });
    });

    return nodes;
  }

  /// 该参数是否默认勾选。
  ///
  /// 命中规则：按规则来 —— 规则没指定默认勾选集合时全部勾上（能进规则表的
  /// 都值得在手机上调），指定了就只勾指定的那几个。
  ///
  /// 未命中规则：只勾高频参数，其余保持可见但不勾。
  /// 之所以不退回「没收录就只认 text/value」：那样过滤掉的从来不是噪音，
  /// 而是大量真实可调的社区节点参数（理由见 [NodeRule.keys]）。
  static bool _defaultExposed(NodeRule? rule, String key) {
    if (rule != null) {
      // 节点规则：指定了集合就只勾集合内的；两个集合都没指定才全勾。
      // ⚠️ 这里修掉了一个既存缺陷：原写法
      // `if (rule.keys == null || rule.defaultExposedKeys == null) return true;`
      // 会把「只给了 defaultExposedKeys、没给 keys」的规则短路成「全勾」，
      // 与规则字面意思相反（ControlNetApplyAdvanced / IPAdapter /
      // IPAdapterFaceID / IPAdapterNoise 四条规则中招）。
      final defaults = rule.defaultExposedKeys ?? rule.keys;
      if (defaults != null) return defaults.contains(key);
      return true;
    }
    // 参数规则（任意节点通用）
    return highFreqParams.contains(key);
  }

  /// 扫一遍工作流，收集出现过的**全部** `class_type`（去重、保持出现顺序）。
  ///
  /// 配置页用它决定「要向服务器问哪些节点的说明书」。
  /// 口径与 [parse] 一致（只认带 `inputs` 的条目），避免问到解析时本就会跳过的东西。
  static List<String> collectClassTypes(Map<String, dynamic> jsonMap) {
    final types = <String>[];
    final seen = <String>{};
    jsonMap.forEach((_, nodeData) {
      if (nodeData is! Map) return;
      final classType = nodeData['class_type'] as String?;
      final inputs = nodeData['inputs'] as Map<String, dynamic>?;
      if (classType == null || inputs == null) return;
      if (seen.add(classType)) types.add(classType);
    });
    return types;
  }

  /// 由「说明书声明 + 当前值 + 强制类型」决定这个参数该用什么控件（§3.4）。
  ///
  /// 判定顺序（**第 0 条自定义卡由调用方 `matchParamCard` 先行拦截**）：
  /// 1. 图片参数 → [ParamControl.upload]（高于说明书结论，服务器说它是选择题也不听）
  /// 2. `COMBO`   → [ParamControl.select]
  /// 3. `BOOLEAN` → [ParamControl.toggle]
  /// 4. `INT` / `FLOAT` 且档位 ≤ [kSliderMaxDivisions] → [ParamControl.slider]
  /// 5. `INT` / `FLOAT` → [ParamControl.number]
  /// 6. `STRING` → [ParamControl.text]
  /// 7. 没有说明书 → 由 [ParamType] 推断
  ///
  /// ⚠️ 只在**配置页**调用一次；运行页只读落盘的 `control`，因此
  /// 运行页的控件形态不会随网络结果变化（§1.1 原则 1 / 2）。
  ///
  /// ⚠️ 这里**不接收**「是否允许滑块」这类布局参数：两列布局的降级是
  /// 运行期渲染才知道的事，由运行页 `_controlFor(paired:)` 处理。
  /// 原来有个 `sliderAllowed` 入参，lib 里零调用（只有测试在用），已删。
  static ParamControl? resolveControl({
    required String key,
    required dynamic rawValue,
    required ParamType? paramType,
    NodeInputSpec? spec,
  }) {
    // 1) 图片上传：永远优先于说明书结论
    if (kImageParamKeys.contains(key) && rawValue is String) {
      return ParamControl.upload;
    }

    switch (spec?.declaredType) {
      case 'COMBO':
        // 声明了 COMBO 却没给选项 → 不当下拉，落到第 7 条按 paramType 推断
        if (spec!.isCombo) return ParamControl.select;
        break;
      case 'BOOLEAN':
        return ParamControl.toggle;
      case 'INT':
      case 'FLOAT':
        final d = spec!.divisionsFor(decimal: paramType == ParamType.float);
        // 档位够少才画滑块；两列布局的降级由运行页 _controlFor(paired:) 负责
        if (d != null && d <= kSliderMaxDivisions) return ParamControl.slider;
        return ParamControl.number;
    }

    // 7) 没有说明书（或声明无法识别）→ 按推断的类型给控件
    return _controlFromParamType(paramType);
  }

  /// 由推断出的 [ParamType] 给出控件形态。
  static ParamControl? _controlFromParamType(ParamType? type) {
    switch (type) {
      case ParamType.text:
        return ParamControl.text;
      case ParamType.seed:
        return ParamControl.seed;
      case ParamType.image:
        return ParamControl.upload;
      case ParamType.intType:
      case ParamType.float:
        return ParamControl.number;
      case ParamType.boolType:
        return ParamControl.toggle;
      case ParamType.enumType:
        return ParamControl.select;
      case null:
        return null;
    }
  }

  /// 计算「服务器说明书里缺了什么」，供配置页标黄用（方案 §3.7）。
  ///
  /// ⚠️ **不落盘** —— 每次打开都能现算，存着还要管过期（方案 §3.2）。
  /// 只统计**确实问到了**的情况：取数失败的一律不算缺失。
  static SpecIssues computeIssues(
    List<WorkflowNode> nodes,
    Map<String, NodeSpec> specs,
  ) {
    final missingNodes = <String>{};
    final missingParams = <String>{};

    for (final n in nodes) {
      final spec = specs[n.classType];
      if (spec == null) continue; // 没问到 → 不知道，不算缺失
      if (spec.isEmpty) {
        missingNodes.add(n.classType); // 问到了但服务器不认识这个节点
        continue;
      }
      if (!spec.containsKey(n.key)) {
        missingParams.add(nodeParamKey(n.id, n.key));
      }
    }

    return SpecIssues(
      missingNodeTypes: missingNodes,
      missingParamKeys: missingParams,
    );
  }

  /// 参数类型判定优先级：强制类型 > 种子 > 上传框 > 按值推断。
  static ParamType? resolveType(
    String key,
    dynamic rawValue,
    Map<String, ParamType> forceTypes, {
    List<NodeRule>? rules,
  }) {
    final forced = forceTypes[key];
    if (forced != null) return forced;

    if (kSeedParamKeys.contains(key) && rawValue is! List) {
      return ParamType.seed;
    }
    if (kImageParamKeys.contains(key) && rawValue is String) {
      return ParamType.image;
    }
    if (kFloatParamKeys.contains(key)) return ParamType.float;
    if (kIntParamKeys.contains(key)) return ParamType.intType;

    final inferred = inferParamType(key, rawValue);
    if (inferred == null) return null;

    // 已知枚举参数名：JSON 里是字符串，但语义是下拉选项。
    return (inferred == ParamType.text && knownEnumParams.contains(key))
        ? ParamType.enumType
        : inferred;
  }

  /// 枚举选项：当前只取工作流里的当前值作为唯一下拉项。
  static List<String> enumOptions(dynamic value) {
    if (value is List) {
      return value.map((e) => e.toString()).toList();
    }
    if (value is String) return [value];
    if (value != null) return [value.toString()];
    return const [];
  }

  /// 把值规整为可序列化、可回填的形态。
  static dynamic normalizeValue(ParamType type, dynamic rawValue) {
    switch (type) {
      case ParamType.enumType:
        return rawValue is List
            ? (rawValue.isNotEmpty ? rawValue.first : null)
            : rawValue;
      default:
        return rawValue;
    }
  }

  /// 默认别名：内置别名表 → **单参数节点**的标题 → 真实参数名（key）。
  ///
  /// 节点标题只在「这个节点只有一个参数」时才有区分度：
  /// 提示词节点叫「正向提示词」很合适，但 CLIPLoader 上三个参数全叫「加载CLIP」
  /// 就是纯噪音（用户看不出哪个是 type、哪个是 device）。
  /// 多参数节点一律回退到服务端的真实参数名，与「服务端叫什么就显示什么」一致。
  static String defaultAlias(
    String key,
    String title,
    String classType,
    AppLocalizations l, {
    bool onlyParam = false,
  }) {
    final t = title.trim();

    final alias = <String, String>{
      'seed': l.aliasSeed,
      'noise_seed': l.aliasSeed,
      'image': l.aliasImage,
      'steps': l.aliasSteps,
      'cfg': l.aliasCfg,
      'sampler_name': l.aliasSampler,
      'scheduler': l.aliasScheduler,
      'denoise': l.aliasDenoise,
      'width': l.aliasWidth,
      'height': l.aliasHeight,
      'batch_size': l.aliasBatchSize,
      'positive': l.aliasPositive,
      'negative': l.aliasNegative,
      'ckpt_name': l.aliasCkpt,
      'unet_name': l.aliasUnet,
      'clip_name': l.aliasClip,
      'vae_name': l.aliasVae,
      'lora_name': l.aliasLora,
      'control_net_name': l.aliasControlNet,
      'upscale_model': l.aliasUpscaleModel,
    }[key];

    if (alias != null) return alias;
    if (onlyParam && isMeaningfulTitle(title, classType)) return t;
    return key;
  }
}
