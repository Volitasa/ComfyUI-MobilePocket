import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'package:comfyui_mobilepocket/l10n/app_localizations.dart';

import '../../providers/connection_provider.dart';
import '../../services/workflow_api_converter.dart';
import '../../theme.dart';
import '../widgets/page_title.dart';

/// 解析 UI 工作流：载入 ComfyUI 前端，调用**它自己的**转换逻辑取回 API 结构。
///
/// 这里刻意让 WebView 可见（被进度遮罩盖住）而不是做无头加载——
/// Android 的 WebView 必须挂进渲染树且尺寸非零，无头方案坑多，
/// 而且可见的情况下失败原因更容易排查。
class WorkflowParseView extends ConsumerStatefulWidget {
  final String displayName;
  final Map<String, dynamic> uiWorkflow;

  const WorkflowParseView({
    super.key,
    required this.displayName,
    required this.uiWorkflow,
  });

  @override
  ConsumerState<WorkflowParseView> createState() => _WorkflowParseViewState();
}

class _WorkflowParseViewState extends ConsumerState<WorkflowParseView> {
  late final WebViewController _controller;
  Timer? _pollTimer;
  Timer? _convertTimer;
  bool _done = false;
  bool _converting = false;
  late String _status;

  /// 初始状态文案是否已取。取文案要读 Localizations，而那是 InheritedWidget，
  /// 在 initState 期间不能依赖（见下面的 didChangeDependencies）。
  bool _statusResolved = false;

  @override
  void initState() {
    super.initState();
    // 这里**不能**取 AppLocalizations：initState 阶段还没挂上 Localizations，
    // 调 dependOnInheritedWidgetOfExactType 会直接抛断言（红屏）。
    // 初始文案统一在 didChangeDependencies 里写。
    final url = ref.read(connectionProvider).comfyUrl;

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..addJavaScriptChannel(
        WorkflowApiConverter.bridgeName,
        onMessageReceived: (msg) {
          _convertTimer?.cancel();
          // WebView 的回调可能在页面已经关掉之后才到，这时再读 context 会崩
          if (!mounted) return;
          _finish(
            WorkflowApiConverter.parsePayload(
              msg.message,
              AppLocalizations.of(context),
            ),
          );
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(onPageFinished: (_) => _startPolling()),
      )
      ..loadRequest(Uri.parse(url));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 首帧取一次初始状态文案。加标记是为了只写这一次：
    // 后续轮询会把 _status 推进成"正在载入/等待就绪"，重复写会把它盖回去。
    if (!_statusResolved) {
      _statusResolved = true;
      _status = AppLocalizations.of(context).parseStatusConnecting;
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _convertTimer?.cancel();
    super.dispose();
  }

  /// 轮询等待前端就绪。
  /// 只等「app 实例出现」是不够的——实例在模块求值阶段就挂上去了，
  /// 那时节点定义还没注册，转换会产出错的结果。
  void _startPolling() {
    if (_done) return;
    final deadline = DateTime.now().add(WorkflowApiConverter.bootTimeout);
    var lastStatus = '';

    _pollTimer?.cancel();
    // 1 秒一次足够：前端加载通常在数秒级，探得再密也只是白跑 JS 调用
    // （原来 400ms，90 秒超时内要探 200 多次）。
    _pollTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (_done) {
        timer.cancel();
        return;
      }
      // 在 await 前取好文案，避免异步 gap 后使用 context
      final l = AppLocalizations.of(context);
      if (DateTime.now().isAfter(deadline)) {
        timer.cancel();
        _finish(ParsedApiResult.fail(l.parseLoadTimeout));
        return;
      }

      try {
        final raw = await _controller.runJavaScriptReturningResult(
          WorkflowApiConverter.readinessProbeScript(),
        );
        final readiness = WorkflowApiConverter.parseReadiness(raw);
        if (readiness == FrontendReadiness.ready) {
          timer.cancel();
          await _runConversion();
          return;
        }
        final next = readiness == FrontendReadiness.missing
            ? l.parseStatusLoadingFrontend
            : l.parseStatusWaitingReady;
        if (next != lastStatus) {
          lastStatus = next;
          if (mounted) setState(() => _status = next);
        }
      } catch (_) {
        // 单次探测失败不致命，继续等下一轮
      }
    });
  }

  Future<void> _runConversion() async {
    if (_done || _converting) return;
    _converting = true;
    // 在 await / 定时器回调前取好文案
    final l = AppLocalizations.of(context);
    if (mounted) {
      setState(() => _status = l.parseStatusConverting);
    }

    _convertTimer?.cancel();
    _convertTimer = Timer(WorkflowApiConverter.convertTimeout, () {
      _finish(ParsedApiResult.fail(l.parseConvertTimeout));
    });

    try {
      await _controller.runJavaScript(
        WorkflowApiConverter.conversionScript(jsonEncode(widget.uiWorkflow)),
      );
    } catch (e) {
      _finish(ParsedApiResult.fail(l.parseConvertFailed(e.toString())));
    }
  }

  void _finish(ParsedApiResult result) {
    if (_done) return;
    _done = true;
    _pollTimer?.cancel();
    _convertTimer?.cancel();
    if (!mounted) return;
    Navigator.pop(context, result);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          AppLocalizations.of(context).parseTitle(widget.displayName),
          style: kSubPageTitleStyle,
        ),
      ),
      body: Stack(
        children: [
          // WebView 必须真实参与布局（尺寸非零），否则 Android 上不会加载
          WebViewWidget(controller: _controller),
          Positioned.fill(
            child: Container(
              // 这层遮罩盖住了 WebView（用户全程只看得到状态文字，看不到
              // ComfyUI 前端），所以它可以跟着主题走，不必迁就前端的浅色
              color: Theme.of(context).colorScheme.surface,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 20),
                      Text(
                        _status,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          color: context.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 推送解析页并等待结果。返回 null 表示用户中途返回。
Future<ParsedApiResult?> startWorkflowParse(
  BuildContext context, {
  required String displayName,
  required Map<String, dynamic> uiWorkflow,
}) {
  return Navigator.push<ParsedApiResult>(
    context,
    MaterialPageRoute(
      builder: (_) =>
          WorkflowParseView(displayName: displayName, uiWorkflow: uiWorkflow),
    ),
  );
}
