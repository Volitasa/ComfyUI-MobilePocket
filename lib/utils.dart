import 'models/workflow_node.dart';

// 通用工具函数

/// 由工作流 ID 得到用于界面展示的名称。
/// 本地导入的工作流使用内容哈希作为 ID（形如 local_x1a2b3），
/// 统一展示为“本地导入”。
String workflowDisplayName(String workflowId) {
  if (workflowId.startsWith('local_')) return '本地导入';
  return workflowId.replaceAll('_api.json', '');
}

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
};

/// 判断某参数是否默认暴露（高频暴露，其余默认不暴露，由用户手动勾选）。
bool isDefaultExposed(String key, String classType) {
  return highFreqParams.contains(key);
}
