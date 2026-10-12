import 'dart:convert';

import '../utils.dart';

/// 前端就绪状态
enum FrontendReadiness {
  /// app 实例尚未暴露（前端还没开始执行到暴露点）
  missing,

  /// 实例已有，但启动遮罩还在——节点定义可能尚未注册完
  loading,

  /// 可以转换
  ready,

  /// 探测结果无法识别
  unknown,
}

/// UI → API 的转换结果。
/// 失败时带一条能直接展示给用户的原因。
class ParsedApiResult {
  final Map<String, dynamic>? workflow;
  final String? error;

  const ParsedApiResult.ok(this.workflow) : error = null;
  const ParsedApiResult.fail(this.error) : workflow = null;

  bool get ok => error == null;
}

/// 复用 ComfyUI 前端完成 UI → API 转换所需的脚本与结果解析。
///
/// 转换逻辑本身由前端提供（`app.loadGraphData` + `app.graphToPrompt`），
/// 这里只负责拼脚本和读结果。**刻意不自己实现转换**：
/// 前端的转换规则跟着节点定义演化，重写一份只会静默产出错的 prompt。
///
/// 本文件全部是纯函数，可单测；WebView 管道本身只能在真机验证。
class WorkflowApiConverter {
  WorkflowApiConverter._();

  /// JS 回传结果的通道名，需与 WebView 注册的一致
  static const String bridgeName = 'ComfyParseBridge';

  /// 等待前端启动的超时（前端约 12 MB，慢设备上可能要十几秒）
  static const Duration bootTimeout = Duration(seconds: 90);

  /// 单次转换的超时
  static const Duration convertTimeout = Duration(seconds: 60);

  /// 前端就绪探测脚本。
  ///
  /// 判定条件有两层：
  /// 1. `window.comfyAPI.app.app` 已暴露 —— 模块已执行到这里；
  /// 2. `#splash-loader` 已从 DOM 移除 —— 启动遮罩收起，
  ///    说明 `registerNodes()`（拉取 /object_info）已完成。
  ///
  /// 只看第 1 条是不够的：实例在模块求值阶段就被挂上去，
  /// 此时节点定义还没注册，`graphToPrompt` 会产出错误结果。
  static String readinessProbeScript() =>
      '(function(){'
      'var a=window.comfyAPI&&window.comfyAPI.app&&window.comfyAPI.app.app;'
      'if(!a)return "no-app";'
      'if(document.getElementById("splash-loader"))return "loading";'
      'return "ready";'
      '})()';

  /// 转换脚本：载入 UI 结构后调用前端自己的转换，结果经通道回传。
  ///
  /// [uiWorkflowJson] 必须是已序列化的 JSON 文本。
  ///
  /// `loadGraphData` 的第二个参数是 restore：非 false 时会去 `canvas.setGraph`
  /// 并 `clean()` 现有画布。我们只要转换结果、不需要重绘画布，
  /// 传 false 可以少一层副作用。
  ///
  /// **取 `r.output` 而不是 `r.workflow`**：前端实现是
  /// `a[id] = {inputs, class_type, _meta}` 然后 `return {workflow: r, output: a}`，
  /// `output` 才是 API prompt 结构，`workflow` 是 UI 图。
  /// （真机踩过：取错字段会"解析成功"却提取不出任何参数。）
  static String conversionScript(String uiWorkflowJson) {
    final literal = _jsSingleQuoted(uiWorkflowJson);
    return '(function(){'
        'function post(m){$bridgeName.postMessage(JSON.stringify(m));}'
        'try{'
        'var a=window.comfyAPI&&window.comfyAPI.app&&window.comfyAPI.app.app;'
        'if(!a){post({ok:false,error:"no-app"});return;}'
        'var g=JSON.parse($literal);'
        'a.loadGraphData(g,false,true).then(function(){return a.graphToPrompt();})'
        '.then(function(r){post({ok:true,workflow:r.output});})'
        '.catch(function(e){post({ok:false,error:String((e&&e.message)||e)});});'
        '}catch(e){post({ok:false,error:String((e&&e.message)||e)});}'
        '})()';
  }

  /// 把 JSON 文本包成 JS 单引号字符串字面量的内容。
  ///
  /// jsonEncode 不会转义 U+2028/U+2029，而它们在旧版 JS 字面量里是非法换行，
  /// 必须显式转义，否则整个脚本会语法错误。
  static String _jsSingleQuoted(String jsonText) =>
      "'${jsonText.replaceAll('\\', '\\\\').replaceAll("'", "\\'").replaceAll('\u2028', '\\u2028').replaceAll('\u2029', '\\u2029')}'";

  /// 归一化 WebView 返回的 JS 值（不同平台可能带多余引号）
  static String normalizeJsValue(Object? value) {
    var s = value?.toString() ?? '';
    if (s.length >= 2 && s.startsWith('"') && s.endsWith('"')) {
      s = s.substring(1, s.length - 1);
    }
    return s.trim();
  }

  static FrontendReadiness parseReadiness(Object? raw) {
    switch (normalizeJsValue(raw)) {
      case 'ready':
        return FrontendReadiness.ready;
      case 'loading':
        return FrontendReadiness.loading;
      case 'no-app':
        return FrontendReadiness.missing;
      default:
        return FrontendReadiness.unknown;
    }
  }

  /// 解析通道回传的 JSON。任何异常都收敛成一条可读的失败原因，
  /// 不让 WebView 的脏数据冒泡成崩溃。
  ///
  /// 同时校验结果的**结构形态**：必须是 API prompt（节点 id → {class_type, inputs}）。
  /// 前端若返回 UI 图（顶层 nodes/links 数组）会在这里被拦下，
  /// 而不是流到配置页变成"没有可动态修改的参数"。
  static ParsedApiResult parsePayload(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const ParsedApiResult.fail('前端返回了无法识别的数据');

      if (decoded['ok'] == true) {
        final wf = decoded['workflow'];
        if (wf is! Map) return const ParsedApiResult.fail('前端未返回工作流结构');
        final prompt = Map<String, dynamic>.from(wf);
        final problem = apiShapeProblem(prompt);
        if (problem != null) return ParsedApiResult.fail(problem);
        return ParsedApiResult.ok(prompt);
      }
      final err = decoded['error']?.toString() ?? '';
      return ParsedApiResult.fail(err.isEmpty ? '解析失败' : err);
    } catch (_) {
      return const ParsedApiResult.fail('解析结果无法读取');
    }
  }

  /// 检查是否为 API prompt 形态。返回 null 表示合格，否则给出可读原因。
  ///
  /// API prompt：每项都是含 class_type 的 Map；UI 图特征是顶层 nodes/links 数组。
  /// 严格按形态判断而不是按字段名猜，前端未来改字段名时宁可误报也不静默放行。
  static String? apiShapeProblem(Map<String, dynamic> prompt) {
    if (prompt.isEmpty) return '转换结果为空（工作流可能没有可运行的节点）';
    if (prompt['nodes'] is List || prompt['links'] is List) {
      return '前端返回了 UI 结构而非 API 结构';
    }
    for (final entry in prompt.entries) {
      final v = entry.value;
      if (v is! Map || v['class_type'] is! String) {
        return '转换结果第 ${entry.key} 项不是有效的 API 节点';
      }
    }
    return null;
  }

  /// UI 工作流内容指纹：基于原始 JSON 文本，用于判断服务器是否已更新。
  ///
  /// 刻意不做归一化——UI 结构与 API 结构的顶层形态不同，
  /// 归一化函数对它不起作用，直接对文本取哈希最稳妥。
  static String sourceHashOf(String jsonText) => stableHash(jsonText).toRadixString(36);
}
