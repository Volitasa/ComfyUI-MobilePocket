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

/// 运行页该用**哪种控件**画这个参数。
///
/// 取值只在**配置页**算一次，随后写进 `mapping_<id>`（判定顺序见
/// `动态节点信息方案.md` §3.4，第 0 条是自定义卡，优先级最高）。
///
/// ⚠️ 运行页只管照着画 —— **永不因请求回来的数据改变形态**。
/// 与 [ParamType] 是两件事：这里管控件大类，那边管整数 / 小数细分。
enum ParamControl {
  text, // 单行 / 多行文本
  number, // 数值输入框
  slider, // 滑块 + 数值框（两列布局时降级为 number）
  toggle, // 开关
  select, // 下拉
  upload, // 图片上传
  seed, // 种子（含随机按钮）
}

/// 数值参数的取值范围。
///
/// 只有两个用途：**越界红字提示**、**滑块刻度**。
///
/// ⚠️ **不参与「滑块还是输入框」的判定** —— 那是 [ParamControl] 的职责。
/// 若让运行时刷新的 bounds 参与形态判定，档位数跨过 100 就会
/// number ↔ slider 来回跳，直接违反「运行页形态不变」的红线。
class ParamBounds {
  const ParamBounds({this.min, this.max, this.step});

  final double? min;
  final double? max;
  final double? step;

  /// 能否用于**校验**：上下限都在、有限、且 max > min。
  bool get hasBounds =>
      min != null &&
      max != null &&
      min!.isFinite &&
      max!.isFinite &&
      max! > min!;

  /// 能否用于**滑块**：有些参数的 max 是天文数字（种子类），画成滑块没有意义，
  /// 这类只有上下限、不画滑块。
  ///
  /// 运行页画滑块用的是**落盘的** bounds（离线也要画得出来），所以这条判据
  /// 落在 [ParamBounds] 上；`NodeInputSpec` 里原来有一份一样的实现，已删掉 ——
  /// 两处必须同步的东西迟早会漂移。
  bool get hasSliderRange =>
      hasBounds && max!.abs() <= 1e9 && min!.abs() <= 1e9;

  factory ParamBounds.fromJson(Map<String, dynamic> json) {
    double? asDoubleOrNull(dynamic raw) => (raw as num?)?.toDouble();
    return ParamBounds(
      min: asDoubleOrNull(json['min']),
      max: asDoubleOrNull(json['max']),
      step: asDoubleOrNull(json['step']),
    );
  }

  Map<String, dynamic> toJson() => {
    if (min != null) 'min': min,
    if (max != null) 'max': max,
    if (step != null) 'step': step,
  };
}

class WorkflowNode {
  final String id;
  final String classType;
  final String key;
  String alias;
  bool exposed;

  /// 节点标题（工作流 _meta.title），用于分组展示时识别节点身份。
  /// 旧配置无此字段，反序列化时兜底为空串。
  final String title;

  /// 参数类型（旧配置无此字段，反序列化时兜底为 [ParamType.text]）
  final ParamType paramType;

  /// 枚举选项；枚举型参数取工作流里的当前值作为唯一下拉项（后续可接入接口动态获取）
  final List<String> options;

  /// 工作流里该参数的当前值，解析后直接作为表单初值带入
  final dynamic value;

  /// 控件形态。**null = 本次没取到服务器说明书，运行页按 [paramType] 推断。**
  ///
  /// 由配置页算好写进 `mapping_<id>`；运行页只读不写。
  final ParamControl? control;

  /// 数值范围（min / max / step）。**null = 没有可依据的范围。**
  ///
  /// 只用于越界红字与滑块刻度，不参与形态判定（见 [ParamBounds] 注释）。
  final ParamBounds? bounds;

  WorkflowNode({
    required this.id,
    required this.classType,
    required this.key,
    required this.alias,
    this.exposed = false,
    this.title = '',
    this.paramType = ParamType.text,
    this.options = const [],
    this.value,
    this.control,
    this.bounds,
  });

  /// 拷贝并覆盖部分字段。
  ///
  /// ⚠️ 配置页合并旧配置时**必须用它**（或手工带上全部新字段）——
  /// 直接 `WorkflowNode(...)` 只传旧字段会静默清空 `control` / `bounds`，
  /// 表现为「功能完全没生效」。见方案 §8.1 陷阱 1。
  WorkflowNode copyWith({
    String? id,
    String? classType,
    String? key,
    String? alias,
    bool? exposed,
    String? title,
    ParamType? paramType,
    List<String>? options,
    dynamic value,
    ParamControl? control,
    ParamBounds? bounds,
  }) {
    return WorkflowNode(
      id: id ?? this.id,
      classType: classType ?? this.classType,
      key: key ?? this.key,
      alias: alias ?? this.alias,
      exposed: exposed ?? this.exposed,
      title: title ?? this.title,
      paramType: paramType ?? this.paramType,
      options: options ?? this.options,
      value: value ?? this.value,
      control: control ?? this.control,
      bounds: bounds ?? this.bounds,
    );
  }

  factory WorkflowNode.fromJson(Map<String, dynamic> json) {
    return WorkflowNode(
      id: json['id'],
      classType: json['classType'] ?? '',
      key: json['key'],
      alias: json['alias'] ?? '',
      exposed: json['exposed'] ?? false,
      title: json['title'] ?? '',
      paramType: json['paramType'] != null
          ? _paramTypeFromName(json['paramType'])
          : _paramTypeFromKey(json['key']),
      options:
          (json['options'] as List?)?.map((e) => e.toString()).toList() ??
          const [],
      value: json['value'],
      // 旧配置没有这两个字段 → 都是 null → 运行页按 paramType 推断，不报错。
      control: _controlFromName(json['control']),
      bounds: json['bounds'] is Map
          ? ParamBounds.fromJson(
              Map<String, dynamic>.from(json['bounds'] as Map),
            )
          : null,
    );
  }

  /// 由名字还原控件形态；认不出来（含旧配置缺失）返回 null。
  static ParamControl? _controlFromName(dynamic name) {
    if (name is! String) return null;
    for (final c in ParamControl.values) {
      if (c.name == name) return c;
    }
    return null;
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
    'title': title,
    'paramType': paramType.name,
    'options': options,
    'value': value,
    // 只在有值时写，旧配置格式保持零变化
    if (control != null) 'control': control!.name,
    if (bounds != null) 'bounds': bounds!.toJson(),
  };
}
