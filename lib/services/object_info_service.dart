import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/workflow_node.dart';

/// 允许向服务器取真实选项的参数名。
///
/// 范围刻意收得很窄：**只有模型节点的模型参数 + 采样器/调度器**。
/// 理由：下拉选项是「服务器此刻有哪些文件/算法」，只有这类参数的选项会随
/// 服务器变动、且用户在手机上真的会在里面挑一个。
///
/// ⚠️ **图片上传参数（`image` / `image_path`）绝不能进来** —— 服务器说明书里
/// `LoadImage.image` 就是一串文件名列表（实测 139 项），一旦当成普通下拉，
/// 用户就再也传不了新图，只能选服务器上已有的文件。上传控件必须保留。
/// 需要向服务器问数值约束的参数名。
///
/// 只有这些键会触发「为了拿 min/max 而去取说明书」，避免为每个节点都发一次
/// 请求。范围同样只放内存，不落盘。
const Set<String> kRangeParamKeys = {
  'steps',
  'cfg',
  'denoise',
  'strength_model',
  'strength_clip',
  'width',
  'height',
  'batch_size',
  'upscale_by',
};

/// 服务端是 COMBO、但工作流 JSON 里只存了一个字符串的参数。
///
/// 光看「值」推断不出它们是枚举（`"lumina2"` 和普通文本长得一样），
/// 所以要为它们所在的节点问一次说明书，把控件渲染成下拉。
/// ⚠️ 它们**不参与**「服务器上没有这个值就拦提交」的判断 —— 那套只认
/// [kDynamicOptionKeys]（模型 / 采样器），否则服务器版本不同就会误拦。
const Set<String> kExtraComboKeys = {'type', 'device', 'weight_dtype'};

/// 档位数上限：`(max - min) / step` 超过它就画数值输入框而不是滑块。
///
/// 见方案 §3.4 第 4 条。种子这类 max 是天文数字的参数，
/// 画成滑块没有意义（拖一格跳几亿）。
const int kSliderMaxDivisions = 100;

const Set<String> kDynamicOptionKeys = {
  // 模型加载
  'ckpt_name',
  'unet_name',
  'clip_name',
  'vae_name',
  'lora_name',
  'control_net_name',
  'upscale_model',
  // 采样
  'sampler_name',
  'scheduler',
};

/// 一个下拉框当前该怎么显示。**纯函数的结果，便于单测。**
class EnumOptionView {
  const EnumOptionView({
    required this.options,
    required this.selected,
    required this.fromServer,
  });

  /// 下拉里实际展示的选项
  final List<String> options;

  /// 当前选中的值；null 表示一项都没选中
  final String? selected;

  /// 选项是否以服务器为准（false = 用的是工作流里的当前值）
  final bool fromServer;

  /// 服务器上没有这个值：「确实拿到了服务器选项」且「当前值不在里面」。
  ///
  /// 没拿到数据时**不算缺失** —— 那只是我们不知道，不是服务器上没有。
  bool get missingOnServer => fromServer && selected == null;
}

/// 决定下拉显示什么。
///
/// 三条兜底规则都收在这里：
/// 1. 没拿到服务器数据 → 用工作流里的当前值，跟以前一模一样，不做任何判定；
/// 2. 拿到了 → 下拉里**只有**服务器的真实选项，不再把工作流当前值塞进去；
/// 3. 拿到了但当前值不在里面 → 不选中（用户自己看得出来），并标记缺失。
EnumOptionView resolveEnumOptions({
  required bool hasServerData,
  required List<String> serverOptions,
  required String? currentValue,
  required List<String> fallbackOptions,
}) {
  if (!hasServerData) {
    final fallback = fallbackOptions.isNotEmpty
        ? fallbackOptions
        : (currentValue != null ? <String>[currentValue] : const <String>[]);
    final selected = fallback.contains(currentValue)
        ? currentValue
        : (fallback.isNotEmpty ? fallback.first : null);
    return EnumOptionView(
      options: fallback,
      selected: selected,
      fromServer: false,
    );
  }

  final selected = serverOptions.contains(currentValue) ? currentValue : null;
  return EnumOptionView(
    options: serverOptions,
    selected: selected,
    fromServer: true,
  );
}

/// 服务器说明书里，单个参数的定义。
///
/// 只留用得上的两个字段 —— 一期只解决「下拉里该有哪些选项」，
/// min/max/step 这些数值约束没进来（用了就得连带把输入框改成滑块）。
class NodeInputSpec {
  const NodeInputSpec({
    required this.isCombo,
    this.options = const [],
    this.rawOptions = const [],
    this.min,
    this.max,
    this.step,
    this.declaredType,
    this.advanced = false,
  });

  /// 是否是「确实拿到了选项列表的 COMBO」。
  ///
  /// 只有它为 true 时才以服务器选项为准：
  /// - 动态下拉（`COMFY_DYNAMICCOMBO_V3`）静态请求取不到选项，它是 false；
  /// - 声明了 COMBO 却没给 options 的畸形定义，它也是 false。
  /// 为 false 时一律当作「没数据」，退回工作流里的当前值，不做任何校验。
  final bool isCombo;

  /// 是否**拿到了可用的选项列表**（`options` 非空）。
  ///
  /// 与 [isCombo] 判据相同，说的是「有没有选项」而不是「服务器是不是声明成了
  /// COMBO」—— 运行页判断「能不能以服务器选项为准」时用的是这一条，
  /// 这样运行页里就不需要出现 `isCombo`（方案 §11 约束 7）。
  bool get hasOptions => options.isNotEmpty;

  /// COMBO 的选项（**显示用字符串**）。可能为空（服务器上确实一个都没有）。
  final List<String> options;

  /// COMBO 的**原始**选项，保留服务器返回的类型。
  ///
  /// ⚠️ 与 [options] **一一对应**（同下标）。提交时用它 —— 例如
  /// `["auto", 8, 10]` 选 8，提交的是整数 `8` 而不是 `"8"`。
  /// 缺失（旧数据 / 解析前）时由 [rawOf] 退回 [options] 的对应项。
  final List<dynamic> rawOptions;

  /// 说明书里声明的类型名（`'COMBO'` / `'INT'` / `'FLOAT'` / `'STRING'` /
  /// `'BOOLEAN'` / `'COMFY_DYNAMICCOMBO_V3'` …）。连线类型与无法识别时为 null。
  final String? declaredType;

  /// 是否被服务器标为高级参数（解析 `meta['advanced']`，optional 段里常见）。
  ///
  /// ⚠️ 只用于**展示**（折叠 / 弱化），**不参与**默认勾选判定（方案 §4）。
  final bool advanced;

  /// 数值下限（INT / FLOAT 的元数据）。没给就是 null。
  final double? min;

  /// 数值上限。⚠️ 实测 `KSampler` 的 max 是字符串
  /// `"18446744073709551615"`（超出 int64），只能按 double 处理。
  final double? max;

  /// 步进。拿不到时由调用方按类型兜底（整数 1、小数 0.01）。
  final double? step;

  /// 能否用于**校验**：上下限都在、有限、且 max > min。
  bool get hasBounds =>
      min != null &&
      max != null &&
      min!.isFinite &&
      max!.isFinite &&
      max! > min!;

  /// 能否用于**滑块**：有些节点的 max 是天文数字（种子类），画成滑块没有意义，
  /// 这类只有上下限、不画滑块。
  bool get hasSliderRange =>
      hasBounds && max!.abs() <= 1e9 && min!.abs() <= 1e9;

  /// 档位数：`(max - min) / step`。拿不到可靠范围时返回 null。
  ///
  /// ⚠️ 只在**配置页定型**时算一次，用来判断「滑块还是输入框」（§3.4 第 4 条）。
  /// 运行页**不许**再用它决定形态 —— 运行时刷新的 bounds 只用于越界提示与滑块刻度，
  /// 否则档位数跨过阈值就会 number ↔ slider 跳变（违反 §1.1 原则 2）。
  int? divisionsFor({required bool decimal}) {
    if (!hasBounds) return null;
    final s = (step != null && step! > 0) ? step! : (decimal ? 0.01 : 1);
    if (s <= 0) return null;
    final d = ((max! - min!) / s).round();
    return d > 0 ? d : null;
  }

  /// 转成可落盘的 [ParamBounds]；没有可依据的范围时返回 null。
  ///
  /// ⚠️ `step` 原样保留（可能为 null）—— 兜底值由消费方按「是否小数」决定，
  /// 不在这里把「没给 step」固化成一个猜测值。
  ParamBounds? toBounds() =>
      hasBounds ? ParamBounds(min: min, max: max, step: step) : null;

  /// 由显示值取**原始值**（保留 int / bool 等类型）；找不到时原样返回 [display]。
  ///
  /// ⚠️ 这是「下拉提交原始类型」的唯一入口 —— 不能用 [options] 里的字符串去提交
  /// （例如 `bit_depth` 的 `["auto", 8, 10]` 会变成 `"8"`）。见方案 §3.6。
  dynamic rawOf(String? display) {
    if (display == null) return null;
    final i = options.indexOf(display);
    if (i < 0 || i >= rawOptions.length) return display;
    return rawOptions[i];
  }

  bool contains(String? value) =>
      value != null && value.isNotEmpty && options.contains(value);
}

/// 数值输入的问题（用于输入框的红字提示）。
enum NumberIssue { notANumber, outOfRange }

/// 校验一段文本是否落在服务器的 min/max 之内。**纯函数，便于单测。**
///
/// 返回 null 表示「没问题」或「没有可依据的范围」——
/// 拿不到说明书时不算错，只是我们不知道边界。
NumberIssue? checkNumberAgainstSpec({
  required NodeInputSpec? spec,
  required String text,
}) {
  if (spec == null || !spec.hasBounds) return null;
  final trimmed = text.trim();
  if (trimmed.isEmpty) return null; // 空值交给提交侧处理，不在这里报
  final v = num.tryParse(trimmed);
  if (v == null) return NumberIssue.notANumber;
  if (v < spec.min! || v > spec.max!) return NumberIssue.outOfRange;
  return null;
}

/// 单个节点的全部输入定义（参数名 → 定义）
typedef NodeSpec = Map<String, NodeInputSpec>;

/// 取一个节点说明书的**结果状态**。
enum ObjectInfoFetchStatus {
  /// 请求没成功（超时 / 断网 / 非 200 / 解析失败）—— 我们对服务器一无所知。
  failure,

  /// 请求成功，但服务器回了 `{}` —— 它**确实不认识**这个节点。
  empty,

  /// 请求成功且拿到了定义。
  ok,
}

/// 取说明书的结果。**三态**：区分「我们不知道」与「服务器上确实没有」。
///
/// 之所以不能有「空 Map 代表没数据」这一个状态，是因为方案 §3.7 的两条规则
/// 要求相反的行为：
/// - `failure`（没取到）→ **不拦**，让服务器报错，比误拦好；
/// - `empty`（服务器不认识这个节点）→ **拦**，提示"服务器缺少节点：<类名>"。
///
/// 本机 ComfyUI 实测：未知节点返回 **HTTP 200 + `{}`**，与网络失败混淆不得。
class ObjectInfoFetchResult {
  const ObjectInfoFetchResult._(this.status, this.spec);

  /// 请求失败：拿不到任何信息，不能据此判断服务器认不认识这个节点。
  const ObjectInfoFetchResult.failure()
    : this._(ObjectInfoFetchStatus.failure, const {});

  /// 服务器明确回应"没有这个节点"（200 + `{}`）。
  const ObjectInfoFetchResult.empty()
    : this._(ObjectInfoFetchStatus.empty, const {});

  /// 拿到了定义。
  const ObjectInfoFetchResult.ok(NodeSpec spec)
    : this._(ObjectInfoFetchStatus.ok, spec);

  final ObjectInfoFetchStatus status;

  /// 参数定义；[status] 不是 `ok` 时为空 Map。
  final NodeSpec spec;

  /// 请求是否失败（等价于"我们不知道"）。
  bool get isFailure => status == ObjectInfoFetchStatus.failure;

  /// 服务器是否明确说"不认识这个节点"。
  ///
  /// ⚠️ 与 [isFailure] 是两回事：只有**确实问到了**才算缺失。
  bool get isMissingOnServer => status == ObjectInfoFetchStatus.empty;

  /// 是否拿到了定义。
  bool get hasSpec => status == ObjectInfoFetchStatus.ok;

  @override
  String toString() => 'ObjectInfoFetchResult(${status.name}, ${spec.length})';
}

/// 取服务器上的节点说明书（ComfyUI 的 `/object_info`）。
///
/// 解析部分是纯函数（不联网），IO 部分单独一个方法，便于单测。
class ObjectInfoService {
  ObjectInfoService._();

  static final ObjectInfoService instance = ObjectInfoService._();

  /// 网络客户端。做成可替换字段是为了单测能注入假客户端
  /// （与 UpdateService.client 同一套路）。
  http.Client client = http.Client();

  /// 单次请求的超时。
  ///
  /// 解析页面有 90 秒预算，但说明书是「锦上添花」的东西：拿不到就退回
  /// 原样，绝不能拖慢打开表单。5 秒拿不到就当没有。
  static const Duration timeout = Duration(seconds: 5);

  /// 解析单个节点的说明书响应。**纯函数，永不抛异常**。
  ///
  /// 响应结构是 `{"<类名>": {"input": {"required": {...}, "optional": {...}}}}`。
  /// 任何结构异常都返回空 Map —— 调用方拿到空就是「没数据」，行为与
  /// 请求失败完全一致，不会把用户带到错误的路上。
  static NodeSpec parseNodeSpec(String body, String classType) {
    final spec = <String, NodeInputSpec>{};
    if (body.isEmpty) return spec;

    dynamic decoded;
    try {
      decoded = jsonDecode(body);
    } catch (_) {
      return spec;
    }
    if (decoded is! Map) return spec;

    // 端点按类名做顶层键。请求的类名取不到时（版本差异）容错取第一个值，
    // 但必须是 Map 才认 —— 取到别的形状宁可当作没数据。
    dynamic nodeDef = decoded[classType];
    if (nodeDef is! Map) {
      nodeDef = decoded.values.whereType<Map>().isEmpty
          ? null
          : decoded.values.whereType<Map>().first;
    }
    if (nodeDef is! Map) return spec;

    final input = nodeDef['input'];
    if (input is! Map) return spec;

    // ⚠️ 只读 required 与 optional，绝不读 hidden。
    // hidden 里是 PROMPT / EXTRA_PNGINFO 这类内部字段（SaveImage 就有），
    // 误读会把它们当普通参数提交给服务器，直接报错。
    for (final section in const ['required', 'optional']) {
      final params = input[section];
      if (params is! Map) continue;
      params.forEach((key, raw) {
        if (key is! String) return;
        if (spec.containsKey(key)) return;
        final parsed = _parseInput(raw);
        if (parsed != null) spec[key] = parsed;
      });
    }

    return spec;
  }

  /// 解析单个参数的定义。
  ///
  /// 说明书里参数定义是一个数组，第 0 位是类型，第 1 位是元数据（可能没有，
  /// 实测有 1387 个参数只有 `[TYPE]` 一项）。
  static NodeInputSpec? _parseInput(dynamic raw) {
    if (raw is! List || raw.isEmpty) return null;
    final type = raw[0];
    final meta = raw.length > 1 ? raw[1] : null;
    final advanced = _isAdvanced(meta);

    // 把服务器给的原始选项转成「(显示串, 原始值)」对。
    // ⚠️ 必须同步过滤空串，否则 options 与 rawOptions 的下标会错位。
    final pairs = <({String display, dynamic raw})>[];
    void collect(List<dynamic> list) {
      for (final e in list) {
        final display = e?.toString() ?? '';
        if (display.isEmpty) continue;
        pairs.add((display: display, raw: e));
      }
    }

    // 形态 A：选项直接就是一个列表 —— ["euler","heun",…]
    if (type is List) {
      collect(type);
      return NodeInputSpec(
        isCombo: true,
        declaredType: 'COMBO',
        advanced: advanced,
        options: pairs.map((p) => p.display).toList(),
        rawOptions: pairs.map((p) => p.raw).toList(),
      );
    }

    if (type is! String) return null;

    // 形态 B：["COMBO", {"options": [...]}]
    if (type == 'COMBO') {
      final rawOptions = meta is Map ? meta['options'] : null;
      if (rawOptions is! List) {
        // 声明了 COMBO 却没给选项：不猜，当成没数据。
        // 否则空列表会被当成「服务器上一个都没有」，误拦提交。
        return NodeInputSpec(isCombo: false, declaredType: type);
      }
      collect(rawOptions);
      return NodeInputSpec(
        isCombo: true,
        declaredType: type,
        advanced: advanced,
        options: pairs.map((p) => p.display).toList(),
        rawOptions: pairs.map((p) => p.raw).toList(),
      );
    }

    // INT / FLOAT：元数据里可能有 min / max / step
    if (type == 'INT' || type == 'FLOAT') {
      return NodeInputSpec(
        isCombo: false,
        declaredType: type,
        advanced: advanced,
        min: _asDouble(meta?['min']),
        max: _asDouble(meta?['max']),
        step: _asDouble(meta?['step']),
      );
    }

    // 形态 C（COMFY_DYNAMICCOMBO_V3）与 STRING / 连线类型等，
    // 一律当作「没有下拉选项」。
    return NodeInputSpec(
      isCombo: false,
      declaredType: type,
      advanced: advanced,
    );
  }

  /// 解析 `meta['advanced']`。说明书里它是 bool，宽松起见也认字符串 `'true'`。
  ///
  /// ⚠️ 只影响展示（如把高级参数折叠起来），**不参与**默认勾选判定（方案 §4）。
  static bool _isAdvanced(dynamic meta) {
    if (meta is! Map) return false;
    final v = meta['advanced'];
    return v == true || v == 'true';
  }

  /// 说明书里的数字可能是数字，也可能是字符串（实测 `max` 就有超 int64 的
  /// 字符串），统一按 double 读；读不出来就当没给。
  static double? _asDouble(dynamic raw) {
    if (raw == null) return null;
    if (raw is num) return raw.toDouble();
    final v = double.tryParse(raw.toString());
    return v == null || !v.isFinite ? null : v;
  }

  /// 向服务器取一个节点的说明书。**永不抛异常**。
  ///
  /// 返回三态（[ObjectInfoFetchResult]）：
  /// - `failure` 请求没成功 —— 不知道服务器认不认识这个节点；
  /// - `empty`   服务器 200 回了 `{}` —— **确实不认识**；
  /// - `ok`      拿到了定义。
  ///
  /// ⚠️ 这三种状态不能合并。合并了，§3.7 的「缺节点拦 / 取数失败不拦」
  /// 就只剩二选一，必然有一条是错的（详见 [ObjectInfoFetchResult] 注释）。
  ///
  /// [baseUrl] 是当前生效的服务器地址（主/备中连通的那个）。
  Future<ObjectInfoFetchResult> fetchNodeSpec(
    String baseUrl,
    String classType,
  ) async {
    if (baseUrl.isEmpty || classType.isEmpty) {
      return const ObjectInfoFetchResult.failure();
    }
    try {
      final uri = Uri.parse(
        '$baseUrl/object_info/${Uri.encodeComponent(classType)}',
      );
      final response = await client.get(uri).timeout(timeout);
      if (response.statusCode != 200) {
        return const ObjectInfoFetchResult.failure();
      }
      final spec = parseNodeSpec(response.body, classType);
      return spec.isEmpty
          ? const ObjectInfoFetchResult.empty()
          : ObjectInfoFetchResult.ok(spec);
    } catch (_) {
      // 超时 / 断网 / 服务器异常 —— 一律当作「没取到」。
      // 拿不到说明书不能让表单打不开，也不该弹任何错误。
      return const ObjectInfoFetchResult.failure();
    }
  }
}
