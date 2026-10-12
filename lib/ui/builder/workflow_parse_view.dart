import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../providers/connection_provider.dart';
import '../../services/workflow_api_converter.dart';

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
  String _status = '正在连接服务器…';

  @override
  void initState() {
    super.initState();
    final url = ref.read(connectionProvider).comfyUrl;

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..addJavaScriptChannel(
        WorkflowApiConverter.bridgeName,
        onMessageReceived: (msg) {
          _convertTimer?.cancel();
          _finish(WorkflowApiConverter.parsePayload(msg.message));
        },
      )
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) => _startPolling(),
      ))
      ..loadRequest(Uri.parse(url));
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
    final deadline =
        DateTime.now().add(WorkflowApiConverter.bootTimeout);
    var lastStatus = '';

    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(milliseconds: 400), (timer) async {
      if (_done) {
        timer.cancel();
        return;
      }
      if (DateTime.now().isAfter(deadline)) {
        timer.cancel();
        _finish(const ParsedApiResult.fail('加载 ComfyUI 前端超时，请检查服务器连接'));
        return;
      }

      try {
        final raw =
            await _controller.runJavaScriptReturningResult(WorkflowApiConverter.readinessProbeScript());
        final readiness = WorkflowApiConverter.parseReadiness(raw);
        if (readiness == FrontendReadiness.ready) {
          timer.cancel();
          await _runConversion();
          return;
        }
        final next = readiness == FrontendReadiness.missing
            ? '正在加载 ComfyUI 前端…'
            : '正在等待前端就绪…';
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
    if (mounted) setState(() => _status = '正在转换工作流…');

    _convertTimer?.cancel();
    _convertTimer = Timer(WorkflowApiConverter.convertTimeout, () {
      _finish(const ParsedApiResult.fail('转换超时，工作流可能包含不支持的节点'));
    });

    try {
      await _controller.runJavaScript(
        WorkflowApiConverter.conversionScript(jsonEncode(widget.uiWorkflow)),
      );
    } catch (e) {
      _finish(ParsedApiResult.fail('调用前端转换失败：${e.toString()}'));
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
        title: Text('解析: ${widget.displayName}', style: const TextStyle(fontSize: 16)),
      ),
      body: Stack(
        children: [
          // WebView 必须真实参与布局（尺寸非零），否则 Android 上不会加载
          WebViewWidget(controller: _controller),
          Positioned.fill(
            child: Container(
              color: Colors.white,
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
                        style: const TextStyle(fontSize: 14, color: Colors.black54),
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
      builder: (_) => WorkflowParseView(
        displayName: displayName,
        uiWorkflow: uiWorkflow,
      ),
    ),
  );
}
