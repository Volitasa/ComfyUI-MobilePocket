import '../utils.dart';

/// 参数类型：决定运行页用哪种控件渲染、提交时如何做类型转换
enum ParamType {
  text, // 多行文本（提示词等）
  seed, // 整数种子（含随机按钮）
  image, // 图片上传
  intType, // 整数（steps、width/height 等）
  float, // 小数（cfg、denoise 等）
  boolType, // 开关
  enumType, // 下拉枚举（sampler_name、scheduler 等）
}

class WorkflowNode {
  final String id;
  final String classType;
  final String key;
  String alias;
  bool exposed;

  /// 参数类型（旧配置无此字段，反序列化时兜底为 [ParamType.text]）
  final ParamType paramType;

  /// 枚举选项；枚举型参数取工作流里的当前值作为唯一下拉项（后续可接入接口动态获取）
  final List<String> options;

  /// 工作流里该参数的当前值，解析后直接作为表单初值带入
  final dynamic value;

  WorkflowNode({
    required this.id,
    required this.classType,
    required this.key,
    required this.alias,
    this.exposed = false,
    this.paramType = ParamType.text,
    this.options = const [],
    this.value,
  });

  factory WorkflowNode.fromJson(Map<String, dynamic> json) {
    return WorkflowNode(
      id: json['id'],
      classType: json['classType'] ?? '',
      key: json['key'],
      alias: json['alias'] ?? '',
      exposed: json['exposed'] ?? false,
      paramType: json['paramType'] != null
          ? _paramTypeFromName(json['paramType'])
          : _paramTypeFromKey(json['key']),
      options: (json['options'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      value: json['value'],
    );
  }

  // 旧版配置没有 paramType 字段：按参数名推断，避免 seed 等被兜底成 text
  static ParamType _paramTypeFromKey(String key) {
    switch (key) {
      case 'seed':
      case 'noise_seed':
        return ParamType.seed;
      case 'image':
        return ParamType.image;
      default:
        if (knownEnumParams.contains(key)) return ParamType.enumType;
        return ParamType.text;
    }
  }

  static ParamType _paramTypeFromName(dynamic name) {
    return ParamType.values.firstWhere(
      (t) => t.name == name,
      orElse: () => ParamType.text,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'classType': classType,
        'key': key,
        'alias': alias,
        'exposed': exposed,
        'paramType': paramType.name,
        'options': options,
        'value': value,
      };
}
