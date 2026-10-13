import 'models/workflow_entry.dart';
import 'models/workflow_node.dart';

// 通用工具函数

/// 由工作流 ID 得到用于界面展示的名称。
/// 本地导入的工作流使用内容哈希作为 ID（形如 local_x1a2b3），
/// 统一展示为传入的 [localLabel]（由调用方按当前语言给出）。
String workflowDisplayName(String workflowId, {required String localLabel}) {
  if (workflowId.startsWith('local_')) return localLabel;
  return workflowId.replaceAll('_api.json', '');
}

/// UI 工作流（`*.json`）的展示名：只去掉 .json 后缀
String uiWorkflowTitle(String filename) =>
    filename.replaceAll(RegExp(r'\.json$'), '');

/// 稳定的字符串哈希（31 位截断，Web 平台下也不会溢出）。
/// 用于为本地导入的工作流生成确定性 ID，同一文件重复导入可命中同一份配置。
int stableHash(String input) {
  var hash = 0;
  for (final unit in input.codeUnits) {
    hash = (hash * 31 + unit) & 0x3FFFFFFF;
  }
  return hash;
}

bool _looksLikeNodeMap(Map map) =>
    map.values.any((v) => v is Map && v.containsKey('class_type'));

/// 归一化工作流数据：兼容 {"prompt": {...节点...}, "extra_data": ...}
/// 包装格式，统一展开为扁平的节点 Map；若顶层本身即节点结构则原样返回。
Map<String, dynamic> normalizeWorkflowJson(Map<String, dynamic> json) {
  final prompt = json['prompt'];
  if (prompt is Map && _looksLikeNodeMap(prompt) && !_looksLikeNodeMap(json)) {
    return Map<String, dynamic>.from(prompt);
  }
  return json;
}

/// 判断一个参数值是否属于「连线引用」（形如 ["节点id", 输出索引]），
/// 这类值不该暴露成表单控件。
bool isLinkReference(dynamic value) {
  if (value is! List) return false;
  if (value.length != 2) return false;
  return value[0] is String && value[1] is num;
}

/// 由参数名推断其语义类型（用于决定控件形态与默认暴露与否）。
/// 无法归类的返回 null，调用方据此决定是否跳过。
ParamType? inferParamType(String key, dynamic value) {
  if (isLinkReference(value)) return null;
  if (value is bool) return ParamType.boolType;
  if (value is int) return ParamType.intType;
  if (value is double) return ParamType.float;
  if (value is List) {
    // 枚举型下拉：元素均为字符串或数字
    if (value.isNotEmpty && value.every((e) => e is String || e is num)) {
      return ParamType.enumType;
    }
    return null;
  }
  if (value is String) {
    // 文本
    return ParamType.text;
  }
  return null;
}

/// 高频参数集合：这些参数默认在配置面板勾选暴露。
const Set<String> highFreqParams = {
  'seed',
  'noise_seed',
  'text',
  'value',
  'image',
  'steps',
  'cfg',
  'sampler_name',
  'scheduler',
  // EmptyLatentImage 的尺寸与生成数量
  'width',
  'height',
  'batch_size',
  // 模型加载参数（默认暴露，便于切换模型）
  'ckpt_name',
  'unet_name',
  'clip_name',
  'vae_name',
  'lora_name',
};

/// 已知枚举型参数名：这些参数的值在 API JSON 里是字符串（当前选中项），
/// 但实际语义是下拉选项。识别为下拉框，选项暂取当前值。
const Set<String> knownEnumParams = {
  'sampler_name',
  'scheduler',
  'ckpt_name',
  'lora_name',
  'vae_name',
  'unet_name',
  'clip_name',
  'control_net_name',
  'upscale_model',
};

/// 判断某参数是否默认暴露（高频暴露，其余默认不暴露，由用户手动勾选）。
bool isDefaultExposed(String key, String classType) {
  return highFreqParams.contains(key);
}

/// 参数在表单/控制器中的唯一键：同一节点可有多个参数，node.id 会冲突。
String nodeParamKey(String nodeId, String key) => '$nodeId:$key';

/// 把「会修改 provider 的动作」推到下一个事件再执行。
///
/// Riverpod 禁止在构建期（build / initState / dispose…）修改状态，
/// 直接写会抛「Tried to modify a provider while the widget tree was building」。
/// `Future.microtask` 仍可能落在同一帧里，必须走事件队列（普通 `Future`）。
///
/// 可以 await：await 后续阶段就能保证缓存已写入。
Future<void> scheduleProviderWrite(void Function() action) =>
    Future<void>(action);

/// 工作流展示名：本地资产与解析缓存取库里保存的名称（后者跟随服务器文件名），
/// 其余沿用「文件名去掉 _api.json」的旧规则。
///
/// 收 [WorkflowEntry] 列表而不是 ref —— WidgetRef 不继承 Ref，
/// UI 与 Notifier 拿到的都是列表，因此可以共用同一个函数。
String resolveWorkflowName(
  List<WorkflowEntry> known,
  String workflowId, {
  required String localLabel,
}) {
  if (workflowId.startsWith('local_') || workflowId.startsWith('parsed_')) {
    for (final w in known) {
      if (w.id == workflowId && w.name.trim().isNotEmpty) return w.name;
    }
  }
  return workflowDisplayName(workflowId, localLabel: localLabel);
}

/// 字节数格式化（工作流占用、快照大小等共用同一口径）
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  return '${(bytes / 1024).toStringAsFixed(1)} KB';
}

/// 判断节点标题是否为“有效自定义标题”（用户手动改过、有辨识度）。
/// 无效标题：空串 / 等于类名 / 自动生成的 "Node X"。
bool isMeaningfulTitle(String title, String classType) {
  final t = title.trim();
  return t.isNotEmpty && t != classType && !t.startsWith('Node ');
}
