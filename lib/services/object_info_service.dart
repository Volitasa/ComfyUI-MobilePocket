import 'dart:convert';

import 'package:http/http.dart' as http;

/// 允许向服务器取真实选项的参数名。
///
/// 范围刻意收得很窄：**只有模型节点的模型参数 + 采样器/调度器**。
/// 理由：下拉选项是「服务器此刻有哪些文件/算法」，只有这类参数的选项会随
/// 服务器变动、且用户在手机上真的会在里面挑一个。
///
/// ⚠️ **图片上传参数（`image` / `image_path`）绝不能进来** —— 服务器说明书里
/// `LoadImage.image` 就是一串文件名列表（实测 139 项），一旦当成普通下拉，
/// 用户就再也传不了新图，只能选服务器上已有的文件。上传控件必须保留。
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
  const NodeInputSpec({required this.isCombo, this.options = const []});

  /// 是否是「确实拿到了选项列表的 COMBO」。
  ///
  /// 只有它为 true 时才以服务器选项为准：
  /// - 动态下拉（`COMFY_DYNAMICCOMBO_V3`）静态请求取不到选项，它是 false；
  /// - 声明了 COMBO 却没给 options 的畸形定义，它也是 false。
  /// 为 false 时一律当作「没数据」，退回工作流里的当前值，不做任何校验。
  final bool isCombo;

  /// COMBO 的真实选项。可能为空（服务器上确实一个都没有）。
  final List<String> options;

  bool contains(String? value) =>
      value != null && value.isNotEmpty && options.contains(value);
}

/// 单个节点的全部输入定义（参数名 → 定义）
typedef NodeSpec = Map<String, NodeInputSpec>;

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

    // 形态 A：选项直接就是一个列表 —— ["euler","heun",…]
    if (type is List) {
      return NodeInputSpec(
        isCombo: true,
        options: type
            .map((e) => e?.toString() ?? '')
            .where((e) => e.isNotEmpty)
            .toList(),
      );
    }

    if (type is! String) return null;

    // 形态 B：["COMBO", {"options": [...]}]
    if (type == 'COMBO') {
      final rawOptions = meta is Map ? meta['options'] : null;
      if (rawOptions is! List) {
        // 声明了 COMBO 却没给选项：不猜，当成没数据。
        // 否则空列表会被当成「服务器上一个都没有」，误拦提交。
        return const NodeInputSpec(isCombo: false);
      }
      return NodeInputSpec(
        isCombo: true,
        options: rawOptions
            .map((e) => e?.toString() ?? '')
            .where((e) => e.isNotEmpty)
            .toList(),
      );
    }

    // 形态 C（COMFY_DYNAMICCOMBO_V3）与 INT / FLOAT / STRING / 连线类型等，
    // 一律当作「没有下拉选项」。
    return const NodeInputSpec(isCombo: false);
  }

  /// 向服务器取一个节点的说明书。失败返回空 Map，不抛异常。
  ///
  /// [baseUrl] 是当前生效的服务器地址（主/备中连通的那个）。
  Future<NodeSpec> fetchNodeSpec(String baseUrl, String classType) async {
    if (baseUrl.isEmpty || classType.isEmpty) return const {};
    try {
      final uri = Uri.parse(
        '$baseUrl/object_info/${Uri.encodeComponent(classType)}',
      );
      final response = await client.get(uri).timeout(timeout);
      if (response.statusCode != 200) return const {};
      return parseNodeSpec(response.body, classType);
    } catch (_) {
      // 超时 / 断网 / 服务器没这个节点 —— 都当作「没数据」。
      // 拿不到说明书不能让表单打不开，也不该弹任何错误。
      return const {};
    }
  }
}
