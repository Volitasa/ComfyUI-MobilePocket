import 'dart:async';

import 'package:comfyui_mobilepocket/l10n/app_localizations.dart';

import 'models/workflow_entry.dart';
import 'models/workflow_node.dart';
import 'services/object_info_service.dart';

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

/// 这个工作流 ID 是否要额外按服务器区分归属。
///
/// 服务器 API 工作流的 ID **就是文件名本身**（`workflow_api.json`），
/// 两台服务器上有同名文件时，节点配置会共用同一份 —— 在 A 上配好的模型名
/// 会直接套到 B 上，提交必定失败。所以键里必须带上服务器。
///
/// 本地（`local_`）与解析缓存（`parsed_`）不需要：前者的 ID 是内容哈希，
/// 后者的哈希里已经混进了服务器 ID，两者自身就全局唯一。
bool needsServerScope(String workflowId) =>
    !workflowId.startsWith('local_') && !workflowId.startsWith('parsed_');

/// 节点配置的存储键。服务器工作流带服务器归属，其余沿用原键（见 [needsServerScope]）。
///
/// 判定放在这里而不是各调用点：保存与读取必须算出同一个键，
/// 分散判断迟早会有一处漏 —— 那样配置存进去了却读不出来。
String mappingKeyFor(String workflowId, String? serverId) {
  if (serverId == null || serverId.isEmpty || !needsServerScope(workflowId)) {
    return 'mapping_$workflowId';
  }
  return 'mapping_${serverId}_$workflowId';
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

/// 运行页里可以并排两列的成对数值参数：键 → 它的搭档键。
///
/// 只有「同一节点内紧挨着、且都是数值」时才真的并排，窄屏一律回退单列。
const Map<String, String> kPairParamKeys = {
  'width': 'height',
  'steps': 'cfg',
  'strength_model': 'strength_clip',
  // 采样器 / 调度器、CLIP 的 type / device：都是短值，合一行省两行高度
  'sampler_name': 'scheduler',
  'type': 'device',
};

/// 判断某参数是否默认暴露（高频暴露，其余默认不暴露，由用户手动勾选）。
bool isDefaultExposed(String key, String classType) {
  return highFreqParams.contains(key);
}

/// 参数在表单/控制器中的唯一键：同一节点可有多个参数，node.id 会冲突。
String nodeParamKey(String nodeId, String key) => '$nodeId:$key';

/// 配置页向服务器取节点说明书的**整体预算**（方案 §3.1）。
///
/// 超时即定型（已拿到的照常采用），顶部提示降级。说明书是加分项，
/// 不能让配置页一直转圈等网络。
const Duration kConfigSpecBudget = Duration(seconds: 2);

/// 在 [budget] 内等 [task] 完成，返回**是否等到了**。
///
/// ⚠️ 超时**不取消** [task] —— 请求仍在飞，结果回来后照常写进缓存
/// （下次进页面直接命中）。既不会卡住当前页面，也不浪费那次请求。
///
/// ⚠️ 但超时用的 Timer **必须取消**：用 `Future.any([task, delayed])` 的话，
/// task 先完成时那个 2 秒 Timer 还挂着，widget 树销毁后就会被测试框架
/// 判为「Timer is still pending」，把所有含该页面的组件测试一起拖挂。
///
/// 🔴 返回值刻意是 `bool`，**不能写成 `T?`（null = 超时）**：
/// `Future<void>` 成功完成时的值本来就是 `null`，「正常完成」和「超时」
/// 会混成同一个值 —— 配置页因此把所有工作流都标成「未获取到服务器节点信息，
/// 已按参数名推断控件」（2026-10-23 修）。要拿任务结果就别用这个函数。
///
/// 任务抛错也按「没在预算内拿到结果」返回 false：说明书是加分项，
/// 不该把配置页带崩。
Future<bool> waitWithin(Future<void> task, Duration budget) {
  final completer = Completer<bool>();
  final timer = Timer(budget, () {
    if (!completer.isCompleted) completer.complete(false);
  });

  void finish(bool ok) {
    if (completer.isCompleted) return;
    timer.cancel();
    completer.complete(ok);
  }

  task.then(
    (_) => finish(true),
    onError: (Object error, StackTrace stack) => finish(false),
  );

  return completer.future;
}

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

/// 写入磁盘用的工作流名：取不到真实名字时返回 null（调用方存空串）。
///
/// 与 [resolveWorkflowName] 的区别：**绝不返回「本地导入」这类翻译文案**。
/// 翻译一旦落盘，用户切换界面语言后磁盘里仍残留旧语言的名字——
/// 与「任务状态只存枚举名、展示时才翻译」是同一个原则。
String? workflowNameForStorage(List<WorkflowEntry> known, String workflowId) {
  if (workflowId.startsWith('local_') || workflowId.startsWith('parsed_')) {
    for (final w in known) {
      if (w.id == workflowId && w.name.trim().isNotEmpty) return w.name;
    }
    // 本地库里已删除、或解析缓存已清除 → 不猜名字，留空由展示层按语言补
    return null;
  }
  return workflowId.replaceAll('_api.json', '');
}

/// 展示工作流名：磁盘里为空（本地库已删 / 解析缓存已清）时，
/// 按**当前语言**补默认名。翻译不落盘，因此这里永远不会显示旧语言的残留。
String workflowDisplayNameOr(AppLocalizations l, String? name) =>
    (name == null || name.trim().isEmpty) ? l.workflowLocalImport : name;

/// 旧版本曾把「本地导入」/「Local import」直接写进磁盘，
/// 读取时识别并清空，让展示层按当前语言重新补上。
const Set<String> _staleLocalLabels = {'本地导入', 'Local import'};

/// 清洗磁盘里读出的工作流名（历史 title、快照 sourceName 等）。
/// 命中旧版本残留的翻译文案时返回 null，其余原样返回。
String? cleanStoredWorkflowName(String? name) {
  if (name == null) return null;
  final trimmed = name.trim();
  return _staleLocalLabels.contains(trimmed) ? null : name;
}

/// 清洗磁盘里读出的服务器名。
///
/// 旧版本在「用户没填名字」时把当时语言的默认名（「服务器」「Server」、
/// 「服务器 2」「Server 2」…）直接写进了磁盘；这里识别并清空，
/// 让展示层按当前语言重新补上。
final RegExp _staleServerNameRe = RegExp(r'^(服务器|Server)( \d+)?$');

String cleanStoredServerName(String? name) {
  if (name == null) return '';
  final trimmed = name.trim();
  return _staleServerNameRe.hasMatch(trimmed) ? '' : name;
}

String formatSnapshotStamp(int millis) {
  final t = DateTime.fromMillisecondsSinceEpoch(millis);
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
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

/// 把控件的当前状态解析成「要提交给服务器的值」。
///
/// 抽成纯函数是为了能单测：这里最容易出的错是「界面看着改了、提交时没带上」。
///
/// ⚠️ **必须按 [control] 分派，不能看 `node.paramType`**（方案 §3.6）。
/// 两者会打架，而且是静默出错：参数值在工作流里是整数（`paramType == intType`）、
/// 说明书却说是 COMBO 时，运行页渲染成下拉；`select` 不建
/// `TextEditingController`，所以 [text] 恒为空 —— 若还按 `intType` 走
/// `num.tryParse('')`，就会退回 `node.value`，**用户选的新值被丢掉且不报错**
/// （`bit_depth: 8` + 选项 `["auto", 8, 10]`，选 10 提交的还是 8）。
///
/// [widgetValue] 是下拉 / 开关的当前值，[text] 是输入框里的文本。
/// [spec] 只用来把下拉的**显示值**换成**原始值**：`bit_depth` 的
/// `["auto", 8, 10]` 选 8 要提交整数 `8`，而不是字符串 `"8"`。
dynamic resolveParamValue({
  required WorkflowNode node,
  required ParamControl control,
  required String text,
  dynamic widgetValue,
  NodeInputSpec? spec,
}) {
  switch (control) {
    case ParamControl.seed:
      final n = num.tryParse(text);
      return n?.round() ??
          (node.value is num ? (node.value as num).round() : 0);
    case ParamControl.number:
    case ParamControl.slider:
      // 解析不出来时退回工作流原值 —— 返回 null 会被提交给服务器，
      // 而服务端的报错信息完全看不出是这儿出的问题。
      final n = num.tryParse(text);
      if (n == null) return node.value;
      // 小数还是整数沿用推断出的 paramType（与输入框的小键盘、滑块刻度同源）
      return node.paramType == ParamType.float ? n.toDouble() : n.round();
    case ParamControl.toggle:
      return widgetValue ?? false;
    case ParamControl.select:
      // 下拉提交**原始值**：显示的是 `toString()` 后的串，服务器要的是原类型。
      // rawOf 找不到时原样返回显示值，不会把值弄丢。
      return spec?.rawOf(widgetValue?.toString()) ?? widgetValue;
    case ParamControl.upload:
      // 图片另走上传分支（`_handleExecute` 里判 upload）；
      // 走到这儿说明没人重新选图，保留服务器上那个文件名。
      return widgetValue ?? text;
    case ParamControl.text:
      // 有些 text 参数其实是服务器的 COMBO，选中值在 widgetValue 里
      return widgetValue ?? text;
  }
}
