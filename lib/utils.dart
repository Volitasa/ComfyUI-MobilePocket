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
