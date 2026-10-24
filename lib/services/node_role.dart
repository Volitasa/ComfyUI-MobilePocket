/// 节点在图里的角色：**同一类节点出现好几个时，用来区分谁是谁**。
///
/// 工作流里三个 `CLIPTextEncode` 都叫「CLIP文本编码」，两个 `KSampler` 都叫
/// 「KSampler」—— 光看类名用户没法判断该改哪个。真正的区别在图里：
/// 一个连到采样器的 positive、一个连到 negative；一个从空画布起手、一个接着上一阶段精修。
///
/// 这里做的就是把**拓扑翻译成一句话**，而不是去画那张图：
/// 手机上画 ComfyUI 的节点图既不现实也没必要（用户的任务是挑参数，不是读拓扑）。
enum NodeRoleKind {
  /// 连到采样器的正向条件（CLIPTextEncode → positive）
  positive,

  /// 连到采样器的负向条件（CLIPTextEncode → negative）
  negative,

  /// 从空 latent 起手的采样器
  baseSampler,

  /// 接着上一阶段继续采样的采样器（高分辨率精修那类）
  refinerSampler,

  /// 加载类节点：装了哪个模型 / LoRA / ControlNet
  asset,
}

class NodeRole {
  const NodeRole(this.kind, {this.assetName});

  final NodeRoleKind kind;

  /// [NodeRoleKind.asset] 时的资源名（已去掉扩展名）。其余为 null。
  ///
  /// 不翻译：模型名 / LoRA 名本来就是用户自己的文件，属于「不译」那一类。
  final String? assetName;
}

/// 会输出「条件（conditioning）」的节点类型。
const Set<String> kConditioningClassTypes = {
  'CLIPTextEncode',
  'CLIPTextEncodeFlux',
  'CLIPTextEncodeSDXL',
  'TextEncodeQwenImageEdit',
  'TextEncode Flux',
};

/// 采样器类节点。
const Set<String> kSamplerClassTypes = {
  'KSampler',
  'KSamplerAdvanced',
  'SamplerCustom',
  'SamplerCustomAdvanced',
};

/// 加载类节点里「装了什么」的参数名，按顺序取第一个有值的。
///
/// ⚠️ 只认**字符串值**：`model` 这类常常是连线引用（`["4", 0]`），
/// 拿来当名字会得到一串无意义的数字。
const List<String> kAssetNameKeys = <String>[
  'ckpt_name',
  'lora_name',
  'unet_name',
  'vae_name',
  'clip_name',
  'control_net_name',
  'upscale_model',
  'swap_model',
];

/// 推断每个节点在图里的角色。认不出来就不给（返回 null），**绝不硬猜**。
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
  jsonMap.forEach((nodeId, nodeData) {
    if (nodeData is! Map) return;
    final classType = nodeData['class_type']?.toString() ?? '';
    final inputs = nodeData['inputs'];
    if (inputs is! Map) return;

    // 1) 条件节点：看它接到了采样器的哪个槽
    if (kConditioningClassTypes.contains(classType)) {
      for (final c in consumers[nodeId] ?? const []) {
        final slot = c.slot.toLowerCase();
        if (slot.contains('positive')) {
          roles[nodeId] = const NodeRole(NodeRoleKind.positive);
          return;
        }
        if (slot.contains('negative')) {
          roles[nodeId] = const NodeRole(NodeRoleKind.negative);
          return;
        }
      }
      return;
    }

    // 2) 采样器：看它的 latent 是不是从空画布来的
    if (kSamplerClassTypes.contains(classType)) {
      final latent = inputs['latent_image'];
      if (latent is List && latent.isNotEmpty && latent[0] is String) {
        final src = jsonMap[latent[0] as String];
        final srcType = src is Map ? src['class_type']?.toString() ?? '' : '';
        roles[nodeId] = NodeRole(
          srcType.startsWith('EmptyLatent')
              ? NodeRoleKind.baseSampler
              : NodeRoleKind.refinerSampler,
        );
        return;
      }
    }

    // 3) 加载类：装了什么就叫什么
    for (final key in kAssetNameKeys) {
      final v = inputs[key];
      if (v is String && v.trim().isNotEmpty) {
        roles[nodeId] = NodeRole(NodeRoleKind.asset, assetName: _assetLabel(v));
        return;
      }
    }
  });

  return roles;
}

/// 资源名去路径与扩展名：`a/b/film_grain.safetensors` → `film_grain`。
String _assetLabel(String raw) {
  var name = raw.trim().replaceAll(r'\', '/');
  final slash = name.lastIndexOf('/');
  if (slash >= 0) name = name.substring(slash + 1);
  final dot = name.lastIndexOf('.');
  if (dot > 0) name = name.substring(0, dot);
  return name;
}
