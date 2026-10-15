import 'package:comfyui_mobilepocket/l10n/app_localizations.dart';

import '../models/workflow_node.dart';
import '../utils.dart';

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
/// 每条规则只回答三个问题：认哪些类名、暴露哪些参数、参数各是什么类型。
class NodeRule {
  const NodeRule({
    required this.classTypes,
    this.keys,
    this.forceTypes = const {},
    this.defaultExposedKeys,
  });

  /// 该规则覆盖的 class_type。写多个是为了容纳变体名
  /// （如 `UnetLoaderGGUF`、`LoraLoaderModelOnly`）。
  final Set<String> classTypes;

  /// 要暴露的参数名。为 null 时暴露该节点全部「控件型」参数。
  ///
  /// 只写真正值得在手机上调的那几个 —— 其余保持不可见，
  /// 否则一个节点几十个参数会把运行页淹没。
  final Set<String>? keys;

  /// 强制类型：优先于按值推断，用于纠正 `denoise` 这类误判。
  final Map<String, ParamType> forceTypes;

  /// 默认勾选的参数名。为 null 时 [keys] 全部默认勾选。
  final Set<String>? defaultExposedKeys;

  bool matches(String classType) => classTypes.contains(classType);

  bool exposes(String key) => keys?.contains(key) ?? true;

  bool isDefaultExposed(String key) =>
      defaultExposedKeys?.contains(key) ?? highFreqParams.contains(key);
}

/// 内置规则表。
///
/// 按「用途」分组，而不是按包名/来源 —— 同一个功能（比如加载 LoRA）
/// 在不同机器上装的类名不一样，分组写在一起才好维护。
const List<NodeRule> kDefaultNodeRules = [
  // ── 采样器 ───────────────────────────────────────────────
  NodeRule(classTypes: {'KSampler'}, forceTypes: {'denoise': ParamType.float}),
  NodeRule(
    classTypes: {'KSamplerAdvanced'},
    forceTypes: {'denoise': ParamType.float},
  ),
  NodeRule(
    classTypes: {'SamplerCustom', 'SamplerCustomAdvanced'},
    forceTypes: {'denoise': ParamType.float},
  ),
  NodeRule(
    classTypes: {'BasicScheduler'},
    keys: {'steps', 'scheduler', 'denoise'},
    defaultExposedKeys: {'steps', 'scheduler', 'denoise'},
  ),
  NodeRule(
    classTypes: {'KSamplerSelect'},
    keys: {'sampler_name'},
    defaultExposedKeys: {'sampler_name'},
  ),

  // ── 文本 / 提示词 ──────────────────────────────────────
  NodeRule(
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
    classTypes: {'Text Concatenate'},
    keys: {'delimiter', 'clean_whitespace', 'text_a', 'text_b'},
    defaultExposedKeys: {'delimiter', 'text_a', 'text_b'},
  ),

  // ── 尺寸 / 放大 ──────────────────────────────────────
  NodeRule(classTypes: {'EmptyLatentImage'}),
  NodeRule(classTypes: {'EmptySD3LatentImage', 'EmptyFluxLatentImage'}),
  NodeRule(classTypes: {'LatentUpscale'}),
  NodeRule(classTypes: {'LatentUpscaleBy'}),
  NodeRule(classTypes: {'ImageScaleBy'}),
  NodeRule(classTypes: {'ImageUpscaleWithModel'}),
  NodeRule(classTypes: {'UpscaleModelLoader'}),

  // ── 模型加载 ──────────────────────────────────────────
  NodeRule(classTypes: {'CheckpointLoaderSimple'}),
  NodeRule(
    classTypes: {'UNETLoader', 'UnetLoaderGGUF', 'UnetLoaderGGUFAdvanced'},
  ),
  NodeRule(classTypes: {'CLIPLoader', 'CLIPLoaderGGUF'}),
  NodeRule(classTypes: {'VAELoader'}),
  NodeRule(classTypes: {'CLIPVisionLoader'}),

  // ── LoRA / 补丁加载 ────────────────────────────────────
  NodeRule(
    classTypes: {'LoraLoader', 'LoraLoaderModelOnly', 'ModelPatchLoader'},
    forceTypes: {
      'strength_model': ParamType.float,
      'strength_clip': ParamType.float,
    },
  ),

  // ── ControlNet ──────────────────────────────────────────
  NodeRule(classTypes: {'ControlNetLoader'}),
  NodeRule(
    classTypes: {'ControlNetApplyAdvanced'},
    defaultExposedKeys: {'strength'},
    forceTypes: {
      'strength': ParamType.float,
      'start_percent': ParamType.float,
      'end_percent': ParamType.float,
    },
  ),
  NodeRule(classTypes: {'SetUnionControlNetType'}),

  // ── IPAdapter ──────────────────────────────────────────
  NodeRule(
    classTypes: {'IPAdapter', 'IPAdapterFaceID'},
    defaultExposedKeys: {'weight'},
    forceTypes: {
      'weight': ParamType.float,
      'start_at': ParamType.float,
      'end_at': ParamType.float,
    },
  ),
  NodeRule(
    classTypes: {'IPAdapterNoise'},
    defaultExposedKeys: {'strength'},
    forceTypes: {'strength': ParamType.float},
  ),
  NodeRule(classTypes: {'IPAdapterUnifiedLoaderFaceID'}),
  NodeRule(classTypes: {'IPAdapterInsightFaceLoader'}),

  // ── 换脸 / 人脸 ────────────────────────────────────────
  NodeRule(
    classTypes: {'ReActorFaceSwap'},
    keys: {'enabled', 'swap_model', 'facedetection', 'face_restore_visibility'},
    defaultExposedKeys: {'enabled', 'swap_model'},
  ),

  // ── 去背 / 掩码合成 ────────────────────────────────────
  NodeRule(classTypes: {'RMBG'}, keys: {'model', 'sensitivity', 'process_res'}),
  NodeRule(classTypes: {'FeatherMask'}),
  NodeRule(classTypes: {'ImageCompositeMasked'}),

  // ── ControlNet 预处理器（手机上最常调的是分辨率）──────
  NodeRule(
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

  /// 未命中规则表时的兜底参数名：任意节点只要有这两个、且是字符串，就认。
  static const Set<String> _fallbackKeys = {'text', 'value'};

  /// 内置规则（供测试替换）。
  static List<NodeRule> get defaultRules => kDefaultNodeRules;

  /// 按 class_type 找规则；找不到返回 null。
  static NodeRule? ruleFor(String classType, {List<NodeRule>? rules}) {
    for (final r in rules ?? defaultRules) {
      if (r.matches(classType)) return r;
    }
    return null;
  }

  /// 解析工作流 JSON，得到「可配置参数」列表。
  ///
  /// 口径：
  /// - 命中规则表 → 按规则暴露指定参数（可指定强制类型与默认勾选）；
  /// - 未命中 → 沿用旧兜底：任意节点的 `text` / `value` 字符串参数。
  static List<WorkflowNode> parse(
    Map<String, dynamic> jsonMap, {
    required AppLocalizations l,
    List<NodeRule>? rules,
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

      // 命中规则但没写 keys → 暴露全部控件型参数；未命中 → 只认 text/value。
      final onlyKeys = rule?.keys ?? _fallbackKeys;
      final forceTypes = rule?.forceTypes ?? const <String, ParamType>{};
      final defaultKeys = rule?.defaultExposedKeys ?? _fallbackKeys;

      inputs.forEach((key, rawValue) {
        if (isLinkReference(rawValue)) return; // 连线引用不暴露

        final type = resolveType(key, rawValue, forceTypes);
        if (type == null) return;

        final exposed = onlyKeys == _fallbackKeys
            ? true
            : (defaultKeys.contains(key) ||
                  (rule != null && rule.defaultExposedKeys == null));

        nodes.add(
          WorkflowNode(
            id: nodeId,
            classType: classType,
            key: key,
            alias: defaultAlias(key, title, classType, l),
            title: title,
            exposed: exposed,
            paramType: type,
            options: type == ParamType.enumType
                ? enumOptions(rawValue)
                : const [],
            value: normalizeValue(type, rawValue),
          ),
        );
      });
    });

    return nodes;
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

  /// 默认别名：优先内置别名；文本类用节点标题；都没有时用参数名。
  ///
  /// 最后退回参数名而不是标题 —— 同一节点下有多个参数时，
  /// 标题没法区分它们，参数名至少能。
  static String defaultAlias(
    String key,
    String title,
    String classType,
    AppLocalizations l,
  ) {
    final t = title.trim();
    final isDefaultTitle = !isMeaningfulTitle(title, classType);

    if (key == 'text' || key == 'value') {
      return isDefaultTitle ? l.aliasPrompt : t;
    }

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
    if (!isDefaultTitle) return t;
    return key;
  }
}
