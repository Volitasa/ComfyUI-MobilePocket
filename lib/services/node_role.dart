import '../utils.dart';

/// 节点在图里的位置：**同一类节点出现好几个时，用来区分谁是谁**。
///
/// 工作流里三个 `CLIPTextEncode` 都叫「CLIP文本编码」，两个 `KSampler` 都叫
/// 「K采样器」—— 光看类名用户没法判断该改哪个。真正的区别在图里：
/// 一个把结果送进采样器的 `positive`、一个送进 `negative`；
/// 一个装的是这个模型、一个装的是那个 LoRA。
///
/// 这里做的就是把**拓扑翻译成一句话**，而不是去画那张图：
/// 手机上画 ComfyUI 的节点图既不现实也没必要（用户的任务是挑参数，不是读拓扑）。
///
/// ⚠️ **角色里出现的每个名字都必须来自官方数据**（用户 2026-10-25 定的红线）：
/// - 下游节点名 → 工作流里的 `_meta.title`（ComfyUI 前端给的节点名），取不到退类名；
/// - 槽位名 → 下游节点 `inputs` 里的 key（`positive` / `samples` …）；
/// - 资源名 → 参数值里的文件名。
/// **不许自己发明概念**（曾经的「起始采样 / 精修采样」就是这么来的，已删）。
class NodeRole {
  /// 这个节点的输出接到了某个节点的某个输入。
  const NodeRole.link({required this.targetLabel, required this.slot})
    : assetName = null;

  /// 加载类节点：装的是哪个资源。
  const NodeRole.asset(this.assetName)
    : targetLabel = null,
      slot = null;

  /// 下游节点的官方名（`_meta.title`，取不到就是类名）。
  final String? targetLabel;

  /// 下游节点接过去的官方输入名（`inputs` 里的 key，如 `positive`）。
  final String? slot;

  /// [NodeRole.asset] 时的资源名（已去掉路径与扩展名）。其余为 null。
  ///
  /// 不翻译：模型名 / LoRA 名本来就是用户自己的文件，属于「不译」那一类。
  final String? assetName;

  bool get isLink => targetLabel != null && slot != null;
}

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

/// 推断每个节点在图里的位置。认不出来就不给（返回 null），**绝不硬猜**。
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

    // 1) 加载类：「装的是哪个文件」比「它接去哪」更值得占这一行
    final inputs = nodeData['inputs'];
    if (inputs is Map) {
      for (final key in kAssetNameKeys) {
        final v = inputs[key];
        if (v is String && v.trim().isNotEmpty) {
          roles[nodeId] = NodeRole.asset(_assetLabel(v));
          return;
        }
      }
    }

    // 2) 其余节点：顺着连线说清它把结果送进了哪个节点的哪个参数
    final picked = _pickLink(consumers[nodeId] ?? const []);
    if (picked == null) return;
    roles[nodeId] = NodeRole.link(
      targetLabel: _nodeLabel(jsonMap[picked.id]),
      slot: picked.slot,
    );
  });

  return roles;
}

/// 在若干个下游里挑一个**能说清楚**的：
///
/// - `positive` / `negative` 优先 —— 槽位名本身就说清了用途，
///   而这恰好是最容易混淆的一对（两个同名的文本编码）；
/// - 只有一个下游时就用它；
/// - 多个下游、又没有明确槽位 → 返回 null。**说不清就不说**，
///   挑一个显示会让人以为只连了那一个。
({String id, String slot})? _pickLink(List<({String id, String slot})> list) {
  for (final c in list) {
    final slot = c.slot.toLowerCase();
    if (slot.contains('positive') || slot.contains('negative')) return c;
  }
  return list.length == 1 ? list.first : null;
}

/// 节点的官方名：前端给的标题（`_meta.title`）优先，取不到就是类名。
///
/// ⚠️ 这两个都来自工作流本身，**不翻译、也不自己起名** ——
/// 界面上出现「K采样器」「加载VAE」是 ComfyUI 自己的中文节点名，
/// 我们只是把它读出来。
String _nodeLabel(dynamic nodeData) {
  if (nodeData is! Map) return '';
  final classType = nodeData['class_type']?.toString() ?? '';
  final meta = nodeData['_meta'];
  final title = meta is Map ? (meta['title']?.toString() ?? '') : '';
  return isMeaningfulTitle(title, classType) ? title.trim() : classType;
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
