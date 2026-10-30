import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/ai_task.dart';
import '../../../models/workflow_node.dart';
import '../../../providers/ai_settings_provider.dart';
import '../../../services/ai/ai_client.dart';
import '../../../services/ai/ai_patch_applier.dart';
import '../../../services/ai/ai_payload_builder.dart';
import '../../../services/ai/ai_response_parser.dart';
import '../../../services/ai/original_image_fetcher.dart';
import '../../../services/image_ref.dart';
import '../../../theme.dart';
import '../../settings/ai_service_view.dart';
import 'ai_node_picker.dart';
import 'ai_result_card.dart';

/// 模板。
///
/// `custom` 是默认项：不预填任何要求，只把用户写的句子 + 已选引用发给模型，
/// 适合「一句话就想让它改改」的场景。其余模板只是预填一句话的快捷方式。
enum AiTemplate { custom, imageToPrompt, rewrite }

/// 抽屉需要宿主（运行页）提供的一切。抽出来是为了组件测试能直接构造。
class AiSheetArgs {
  const AiSheetArgs({
    required this.workflowKey,
    required this.serverId,
    required this.baseUrl,
    required this.nodes,
    required this.textOf,
    required this.imageValueOf,
    required this.localBytesOf,
    required this.controllerOf,
    required this.scrollController,
    required this.sheetController,
    this.initialParam,
    this.client,
    this.fetcher,
  });

  final String workflowKey;
  final String? serverId;
  final String baseUrl;
  final List<WorkflowNode> nodes;
  final String Function(WorkflowNode node) textOf;
  final String? Function(WorkflowNode node) imageValueOf;
  final Uint8List? Function(WorkflowNode node) localBytesOf;
  final TextEditingController? Function(WorkflowNode node) controllerOf;
  final ScrollController scrollController;

  /// 用来把抽屉从 0.5 抬到 0.72（结果到达时）。可为 null（测试里不需要）。
  final DraggableScrollableController? sheetController;

  /// 长按别名行进入时预填的参数：文本参数当输出目标，其它当输入引用。
  final WorkflowNode? initialParam;

  /// 测试注入；为 null 时用真实实现。
  final AiClient? client;
  final OriginalImageFetcher? fetcher;
}

class AiSheet extends ConsumerStatefulWidget {
  const AiSheet({super.key, required this.args});

  final AiSheetArgs args;

  @override
  ConsumerState<AiSheet> createState() => _AiSheetState();
}

enum _Mode { compose, pickInput, pickOutput }

class _AiSheetState extends ConsumerState<AiSheet> {
  _Mode _mode = _Mode.compose;
  late Set<String> _inputIds = {};
  String? _outputId;
  AiTemplate? _template = AiTemplate.custom;
  final TextEditingController _instruction = TextEditingController();
  final FocusNode _instructionFocus = FocusNode();

  /// 结果卡的位置：出结果后把它滚进可视区，避免底部按钮被抽屉footer盖住。
  final GlobalKey _resultKey = GlobalKey();

  bool _running = false;
  bool _written = false;
  String _buffer = '';
  String? _status;
  AiTaskResult? _result;
  AiException? _error;
  bool _canceled = false;
  bool _expanded = false;
  String? _hint;

  /// 供应商回报的实际模型名（`deepseek-chat` 这类别名由服务端解析，客户端只能事后得知）。
  String? _servedModel;
  String? _previousText;
  AiApplyError? _applyError;

  StreamSubscription<String>? _sub;
  OriginalImageFetcher? _fetcher;
  DateTime _lastFollow = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    final initial = widget.args.initialParam;
    if (initial != null) {
      if (isTextTargetNode(initial)) {
        _outputId = _idOf(initial);
      } else {
        _inputIds = {_idOf(initial)};
      }
    }
    _instruction.text = _defaultInstruction(AiTemplate.custom);
    _instructionFocus.addListener(_onFocusChanged);
  }

  /// 键盘弹起时把抽屉拉到最高（否则输入框在键盘上方只剩一条缝）；
  /// 收起后再落回「有结果看结果、没结果看表单」的高度。
  /// 从选择器回到表单：收起键盘并把抽屉落回常规高度。
  /// 不这么做的话，选完输出目标抽屉会一直停在满高、把运行页整页盖住。
  void _backToCompose() {
    _instructionFocus.unfocus();
    setState(() => _mode = _Mode.compose);
    final controller = widget.args.sheetController;
    if (controller == null || !controller.isAttached) return;
    controller.animateTo(
      (_result != null || _running) ? 0.92 : 0.56,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  void _onFocusChanged() {
    final controller = widget.args.sheetController;
    if (controller == null || !controller.isAttached) return;
    if (_instructionFocus.hasFocus) {
      // 键盘还没弹完就先占满：否则「0.56 高度 - 键盘」会把输入区压成一条缝
      controller.jumpTo(1);
      return;
    }
    controller.animateTo(
      (_result != null || _running) ? 0.92 : 0.56,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    _instructionFocus.dispose();
    _instruction.dispose();
    super.dispose();
  }

  static String _idOf(WorkflowNode n) => '${n.id}:${n.key}';

  String _titleOf(WorkflowNode n) =>
      n.title.trim().isEmpty ? n.classType : n.title;

  String _summaryOf(WorkflowNode n) {
    if (isImageInputNode(n)) return widget.args.imageValueOf(n) ?? '';
    final t = widget.args.textOf(n).replaceAll('\n', ' ');
    return t.length > 48 ? '${t.substring(0, 48)}…' : t;
  }

  List<WorkflowNode> get _allNodes => widget.args.nodes;

  WorkflowNode? get _outputNode {
    final id = _outputId;
    if (id == null) return null;
    for (final n in _allNodes) {
      if (_idOf(n) == id) return n;
    }
    return null;
  }

  List<WorkflowNode> get _selectedInputNodes {
    final out = <WorkflowNode>[];
    for (final n in _allNodes) {
      if (_inputIds.contains(_idOf(n))) out.add(n);
    }
    return out;
  }

  List<WorkflowNode> get _imageNodes =>
      _selectedInputNodes.where(isImageInputNode).toList();

  /// 切模板时预填的要求。自定义项**留空**——让用户自己写，避免他先删一遍。
  String _defaultInstruction(AiTemplate t) => switch (t) {
    AiTemplate.custom => '',
    AiTemplate.imageToPrompt => '根据这些参考图写一段可直接使用的提示词。',
    AiTemplate.rewrite => '把这段改写成一段更连贯的提示词。',
  };

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final settings = ref.watch(aiSettingsProvider);
    final ready = settings.isReady;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(top: BorderSide(color: context.borderColor)),
      ),
      child: Column(
        children: [
          Container(
            width: 34,
            height: 4,
            margin: const EdgeInsets.only(top: 8, bottom: 2),
            decoration: BoxDecoration(
              color: context.borderColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          _header(l),
          Expanded(child: _body(l, ready)),
          if (_mode == _Mode.compose) _footer(l, ready),
        ],
      ),
    );
  }

  Widget _header(AppLocalizations l) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 8, 6),
      child: Row(
        children: [
          Icon(Icons.auto_awesome, size: 18, color: context.accent),
          const SizedBox(width: 6),
          Text(
            l.aiSheetTitle,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          ),
          const Spacer(),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(
              Icons.settings_outlined,
              size: 19,
              color: context.textSecondary,
            ),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AiServiceView()),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.close, size: 20, color: context.textSecondary),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _body(AppLocalizations l, bool ready) {
    if (_mode == _Mode.pickInput) {
      return AiNodePicker(
        nodes: _allNodes,
        initialSelected: _inputIds,
        multi: true,
        summaryOf: _summaryOf,
        scrollController: widget.args.scrollController,
        onBack: _backToCompose,
        onConfirm: (ids) {
          _inputIds = ids;
          _backToCompose();
        },
      );
    }
    if (_mode == _Mode.pickOutput) {
      return AiNodePicker(
        nodes: _allNodes.where(isTextTargetNode).toList(),
        initialSelected: _outputId == null ? {} : {_outputId!},
        multi: false,
        summaryOf: _summaryOf,
        scrollController: widget.args.scrollController,
        onBack: _backToCompose,
        onConfirm: (ids) {
          _outputId = ids.isEmpty ? null : ids.first;
          _backToCompose();
        },
      );
    }
    return ListView(
      controller: widget.args.scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      // 拖动列表就收键盘：用户往上看结果时不该再被键盘占着半屏
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 16),
      children: [
        if (!ready) _noProvider(l),
        if (_written) _writtenBanner(l),
        _section(l.aiInputLabel, _inputChips(l)),
        const SizedBox(height: 10),
        _section(l.aiOutputLabel, _outputChip(l)),
        const SizedBox(height: 10),
        _templates(l),
        const SizedBox(height: 10),
        TextField(
          controller: _instruction,
          focusNode: _instructionFocus,
          minLines: 2,
          maxLines: 4,
          style: const TextStyle(fontSize: 13),
          decoration: InputDecoration(
            hintText: l.aiInstructionHint,
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        if (_hint != null) ...[
          const SizedBox(height: 8),
          Text(
            _hint!,
            style: TextStyle(fontSize: 12, color: context.stateDanger),
          ),
        ],
        if (_status != null) ...[
          const SizedBox(height: 8),
          Text(
            _status!,
            style: TextStyle(fontSize: 11, color: context.textSecondary),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 10),
          _errorBox(l, _error!),
        ],
        if (_applyError != null) ...[
          const SizedBox(height: 8),
          Text(
            l.aiCannotWrite(_applyErrorText(l, _applyError!)),
            style: TextStyle(fontSize: 12, color: context.stateDanger),
          ),
        ],
        if (_running || (_result != null && _result!.rawText.isNotEmpty)) ...[
          const SizedBox(height: 10),
          KeyedSubtree(
            key: _resultKey,
            child: AiResultCard(
              text: _running ? _buffer : _displayText,
              beforeLength: _outputNode == null
                  ? 0
                  : widget.args.textOf(_outputNode!).length,
              structured: _result?.structured ?? false,
              streaming: _running,
              written: _written,
              servedModel: _servedModel,
              onWrite: _applyResult,
              onCopy: _copyResult,
            ),
          ),
        ],
        if (_canceled && !_running)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              l.aiCanceled,
              style: TextStyle(fontSize: 11, color: context.textSecondary),
            ),
          ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _section(String label, Widget child) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 11, color: context.textSecondary),
        ),
        const SizedBox(height: 6),
        child,
      ],
    );
  }

  Widget _noProvider(AppLocalizations l) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: context.containerFill,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 16, color: context.stateWarning),
          const SizedBox(width: 8),
          Expanded(
            child: Text(l.aiNoProvider, style: const TextStyle(fontSize: 12)),
          ),
          TextButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AiServiceView()),
            ),
            child: Text(l.aiOpenSettings),
          ),
        ],
      ),
    );
  }

  Widget _writtenBanner(AppLocalizations l) {
    final node = _outputNode;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: context.containerFill,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: context.borderColor),
      ),
      child: Row(
        children: [
          Icon(Icons.check, size: 15, color: context.accent),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              l.aiWrittenBanner(node == null ? '' : _titleOf(node)),
              style: const TextStyle(fontSize: 12),
            ),
          ),
          TextButton(
            onPressed: _undo,
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 6),
            ),
            child: Text(l.aiUndo),
          ),
        ],
      ),
    );
  }

  Widget _inputChips(AppLocalizations l) {
    final nodes = _selectedInputNodes;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final n in nodes)
          _chip(
            icon: isImageInputNode(n)
                ? Icons.image_outlined
                : Icons.text_fields,
            label: _chipLabel(n),
            onRemove: () => setState(() => _inputIds.remove(_idOf(n))),
          ),
        _addChip(l.aiAddInput, () => setState(() => _mode = _Mode.pickInput)),
      ],
    );
  }

  Widget _outputChip(AppLocalizations l) {
    final node = _outputNode;
    return Wrap(
      spacing: 6,
      children: [
        if (node != null)
          _chip(
            icon: Icons.text_fields,
            label: '${_titleOf(node)} · ${node.key}',
            onRemove: () => setState(() => _outputId = null),
          )
        else
          _addChip(
            l.aiAddOutput,
            () => setState(() => _mode = _Mode.pickOutput),
          ),
      ],
    );
  }

  String _chipLabel(WorkflowNode n) {
    if (isImageInputNode(n)) {
      final v = widget.args.imageValueOf(n) ?? '';
      if (v.isEmpty) return _titleOf(n);
      return v.length > 18 ? '${v.substring(0, 18)}…' : v;
    }
    return '${_titleOf(n)} · ${n.key}';
  }

  Widget _chip({
    required IconData icon,
    required String label,
    required VoidCallback onRemove,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 5, 4, 5),
      decoration: BoxDecoration(
        color: context.containerFill,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: context.accent),
          const SizedBox(width: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 150),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
          ),
          GestureDetector(
            onTap: onRemove,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(Icons.close, size: 13, color: context.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _addChip(String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: context.borderColor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add, size: 13, color: context.textSecondary),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(fontSize: 12, color: context.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _templates(AppLocalizations l) {
    Widget chip(String label, AiTemplate t) {
      final on = _template == t;
      return GestureDetector(
        onTap: () => setState(() {
          _template = t;
          _instruction.text = _defaultInstruction(t);
        }),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: on ? context.containerFill : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: on ? context.accent : context.borderColor,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: on
                  ? Theme.of(context).colorScheme.onSurface
                  : context.textSecondary,
              fontWeight: on ? FontWeight.w500 : FontWeight.w400,
            ),
          ),
        ),
      );
    }

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        chip(l.aiTemplateCustom, AiTemplate.custom),
        chip(l.aiTemplateImage, AiTemplate.imageToPrompt),
        chip(l.aiTemplateRewrite, AiTemplate.rewrite),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Text(
            l.aiTemplateMore,
            style: TextStyle(
              fontSize: 12,
              color: context.textSecondary.withValues(alpha: 0.5),
            ),
          ),
        ),
      ],
    );
  }

  Widget _errorBox(AppLocalizations l, AiException e) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: context.containerFill,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.error_outline, size: 15, color: context.stateDanger),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _errorText(l, e),
                  style: TextStyle(fontSize: 12, color: context.stateDanger),
                ),
              ),
              TextButton(
                onPressed: _running ? null : _generate,
                child: Text(l.aiRetry),
              ),
            ],
          ),
          if (e.detail.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                e.detail.length > 160
                    ? '${e.detail.substring(0, 160)}…'
                    : e.detail,
                style: TextStyle(fontSize: 10, color: context.textSecondary),
              ),
            ),
        ],
      ),
    );
  }

  Widget _footer(AppLocalizations l, bool ready) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
        child: SizedBox(
          width: double.infinity,
          child: _running
              ? OutlinedButton(
                  onPressed: _stop,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(46),
                  ),
                  child: Text(l.aiStop),
                )
              : FilledButton(
                  onPressed: ready ? _generate : null,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(46),
                    backgroundColor: context.accent,
                    foregroundColor: context.onAccent,
                  ),
                  child: Text(l.aiGenerate),
                ),
        ),
      ),
    );
  }

  // ── 发送 ───────────────────────────────────────────────

  Future<void> _generate() async {
    final l = AppLocalizations.of(context);
    final provider = ref.read(aiSettingsProvider).active;
    // 校验提示必须内联：SnackBar 会被底部抽屉挡住，用户什么也看不到。
    String? problem;
    if (provider == null || !provider.isConfigured) {
      problem = l.aiNoProvider;
    } else if (_outputNode == null) {
      problem = l.aiNeedOutput;
    } else if (_template == AiTemplate.imageToPrompt && _imageNodes.isEmpty) {
      problem = l.aiNeedImage;
    } else if (_instruction.text.trim().isEmpty) {
      problem = l.aiNeedInstruction;
    }
    if (problem != null) {
      setState(() => _hint = problem);
      return;
    }
    final activeProvider = provider!;
    final outNode = _outputNode!;
    final instruction = _instruction.text.trim();

    setState(() {
      _running = true;
      _canceled = false;
      _written = false;
      _result = null;
      _error = null;
      _applyError = null;
      _buffer = '';
      _status = null;
      _expanded = false;
      _hint = null;
      _servedModel = null;
    });

    final inputs = <AiContextInput>[];
    final images = <Uint8List>[];
    // 先收键盘。必须放在 `_running = true` 之后：`_onFocusChanged` 靠它判断
    // 「有没有结果要看」，提前 unfocus 会把抽屉缩回 0.56，流式输出只露一条缝。
    _instructionFocus.unfocus();
    try {
      final imageNodes = _imageNodes;
      for (var i = 0; i < imageNodes.length; i++) {
        final node = imageNodes[i];
        if (imageNodes.length > 1) {
          setState(() => _status = l.aiReadingImages(i + 1, imageNodes.length));
        }
        final bytes = await _bytesFor(node);
        images.add(bytes);
      }

      for (final node in _selectedInputNodes) {
        if (isImageInputNode(node)) {
          inputs.add(
            AiContextInput(
              nodeId: node.id,
              title: _titleOf(node),
              classType: node.classType,
              key: node.key,
              image: _fileNameOf(node),
            ),
          );
        } else {
          inputs.add(
            AiContextInput(
              nodeId: node.id,
              title: _titleOf(node),
              classType: node.classType,
              key: node.key,
              text: widget.args.textOf(node),
            ),
          );
        }
      }

      final payload = buildAiPayload(
        task: _template?.name ?? 'rewrite',
        target: AiOutputTarget(
          nodeId: outNode.id,
          key: outNode.key,
          title: _titleOf(outNode),
          current: widget.args.textOf(outNode),
        ),
        inputs: inputs,
        models: _modelInfos(),
        instruction: instruction,
      );

      var imageBytesTotal = 0;
      for (var i = 0; i < images.length; i++) {
        imageBytesTotal += images[i].length;
        appendImagePart(
          payload,
          'data:${imageMimeOf(images[i])};base64,${base64Encode(images[i])}',
        );
      }
      if (images.isNotEmpty) {
        setState(() {
          _status = l.aiImagesSent(
            images.length,
            _formatBytes(imageBytesTotal),
          );
        });
      }

      final client = widget.args.client ?? AiClient();
      _sub = client
          .streamChat(
            provider: activeProvider,
            systemPrompt: payload.systemPrompt,
            userParts: payload.userParts,
            onModel: (model) {
              if (mounted) setState(() => _servedModel = model);
            },
          )
          .listen(
            (delta) {
              _buffer += delta;
              if (!_expanded) {
                _expanded = true;
                _expand();
              }
              if (mounted) setState(() {});
              _followResult();
            },
            onError: (Object e) {
              if (!mounted) return;
              setState(() {
                _running = false;
                _error = e is AiException
                    ? e
                    : AiException(kind: AiErrorKind.network, detail: '$e');
              });
            },
            onDone: () {
              if (!mounted) return;
              setState(() {
                _running = false;
                _result = parseAiResult(_buffer);
              });
              _revealResult();
            },
            cancelOnError: true,
          );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _running = false;
        _error = e is AiException
            ? e
            : AiException(kind: AiErrorKind.network, detail: '$e');
      });
    }
  }

  void _expand() {
    final controller = widget.args.sheetController;
    if (controller == null || !controller.isAttached) return;
    controller.animateTo(
      0.92,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  /// 结果出来后把它滚进可视区（底部对齐），保证「写入 / 复制」不是被压在页脚下面。
  void _revealResult() => _followResult(throttle: false);

  /// [throttle] 为 false 时无条件滚动（收尾动作）；否则限流，用于流式过程中跟着长。
  /// 不这样做的话结果卡一路往下长，用户得不停往上划才能看到最新的字。
  void _followResult({bool throttle = true}) {
    final now = DateTime.now();
    if (throttle) {
      if (now.difference(_lastFollow) < const Duration(milliseconds: 400)) {
        return;
      }
    }
    _lastFollow = now;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _resultKey.currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOut,
        alignment: 1,
      );
    });
  }

  void _stop() {
    _sub?.cancel();
    _sub = null;
    setState(() {
      _running = false;
      _canceled = true;
      _result = parseAiResult(_buffer);
    });
    _revealResult();
  }

  Future<Uint8List> _bytesFor(WorkflowNode node) async {
    final local = widget.args.localBytesOf(node);
    if (local != null) return local;
    final value = widget.args.imageValueOf(node);
    final ref = value == null ? null : parseImageRef(value);
    if (ref == null) {
      throw const AiException(
        kind: AiErrorKind.badRequest,
        detail: 'image value is empty',
      );
    }
    _fetcher ??= widget.args.fetcher ?? OriginalImageFetcher();
    return _fetcher!.fetch(
      baseUrl: widget.args.baseUrl,
      ref: ref,
      serverId: widget.args.serverId ?? '',
    );
  }

  String _fileNameOf(WorkflowNode node) {
    final value = widget.args.imageValueOf(node);
    final ref = value == null ? null : parseImageRef(value);
    return ref?.filename ?? value ?? '';
  }

  List<AiModelInfo> _modelInfos() {
    const keys = {
      'ckpt_name': 'checkpoint',
      'unet_name': 'unet',
      'clip_name': 'clip',
      'vae_name': 'vae',
      'lora_name': 'lora',
      'control_net_name': 'controlnet',
      'upscale_model': 'upscale',
    };
    final out = <AiModelInfo>[];
    final seen = <String>{};
    for (final n in _allNodes) {
      final kind = keys[n.key];
      if (kind == null) continue;
      final value = n.value;
      if (value is! String || value.trim().isEmpty) continue;
      if (!seen.add('$kind|$value')) continue;
      out.add(AiModelInfo(kind: kind, name: value));
      if (out.length >= 6) break;
    }
    return out;
  }

  // ── 写入 / 复制 / 撤销 ───────────────────────────────────

  void _applyResult() {
    final l = AppLocalizations.of(context);
    final node = _outputNode;
    final result = _result;
    if (node == null || result == null) return;

    final patch = result.structured
        ? result.patches.first
        : AiPatch(node: node.id, key: node.key, value: result.rawText);

    final check = validateAiPatch(
      patch: patch,
      nodes: _allNodes,
      allowedParamKeys: {_idOf(node)},
    );
    if (!check.ok) {
      setState(() => _applyError = check.error);
      return;
    }
    final controller = widget.args.controllerOf(node);
    if (controller == null) {
      setState(() => _applyError = AiApplyError.notTextParam);
      return;
    }
    _previousText = controller.text;
    controller.text = patch.value;
    setState(() {
      _applyError = null;
      _written = true;
    });
    _snack(l.aiWritten);
  }

  void _undo() {
    final node = _outputNode;
    final controller = node == null ? null : widget.args.controllerOf(node);
    if (controller != null && _previousText != null) {
      controller.text = _previousText!;
    }
    setState(() {
      _written = false;
      _previousText = null;
    });
  }

  /// 卡片与复制都用「要写进表单的那段文本」。
  ///
  /// 结构化返回时 `rawText` 是整包 JSON，直接展示会让人以为 AI 只回了 JSON。
  String get _displayText {
    final result = _result;
    if (result == null) return '';
    if (result.structured && result.patches.isNotEmpty) {
      return result.patches.first.value;
    }
    return result.rawText;
  }

  Future<void> _copyResult() async {
    final l = AppLocalizations.of(context);
    final text = _displayText.isEmpty ? _buffer : _displayText;
    await Clipboard.setData(ClipboardData(text: text));
    _snack(l.aiCopied);
  }

  String _errorText(AppLocalizations l, AiException e) => switch (e.kind) {
    AiErrorKind.unauthorized => l.aiErrorUnauthorized,
    AiErrorKind.notFound => l.aiErrorNotFound,
    AiErrorKind.rateLimited => l.aiErrorRateLimited,
    AiErrorKind.server => l.aiErrorServer,
    AiErrorKind.network => l.aiErrorNetwork,
    AiErrorKind.timeout => l.aiErrorTimeout,
    AiErrorKind.badRequest => l.aiErrorBadRequest,
  };

  String _applyErrorText(AppLocalizations l, AiApplyError e) => switch (e) {
    AiApplyError.nodeMissing => l.aiWriteNodeMissing,
    AiApplyError.notTextParam => l.aiWriteNotText,
    AiApplyError.notAllowed => l.aiWriteNotAllowed,
    AiApplyError.tooLong => l.aiWriteTooLong,
  };

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
}
