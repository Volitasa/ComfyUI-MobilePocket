import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/workflow_node.dart';
import 'size_presets.dart';

/// latent 节点的「尺寸卡」：比例 + 长边 + 张数，替代三个分开的数字输入框。
///
/// 三条约束（改动前定死的）：
/// 1. **进入卡片不改写已有值**：工作流原来是 720 × 1280 就原样保留，chips 不选中；
/// 2. **只写用户动过的键**：点比例/长边只改 width、height，点步进只改 batch_size；
/// 3. **字段标签取配置**：张数那行的名字用 alias（用户在配置页改过就用改过的）。
class LatentSizeCard extends StatefulWidget {
  const LatentSizeCard({
    super.key,
    required this.params,
    required this.controllerOf,
  });

  /// 该节点暴露出来的参数
  final List<WorkflowNode> params;

  /// 取参数对应的控制器（运行页持有，卡片只写文本，不另造一份状态）
  final TextEditingController? Function(WorkflowNode node) controllerOf;

  @override
  State<LatentSizeCard> createState() => _LatentSizeCardState();
}

class _LatentSizeCardState extends State<LatentSizeCard> {
  String? _ratio;
  int? _longEdge;
  bool _custom = false;

  WorkflowNode? _node(String key) {
    for (final n in widget.params) {
      if (n.key == key) return n;
    }
    return null;
  }

  TextEditingController? _controller(String key) {
    final node = _node(key);
    return node == null ? null : widget.controllerOf(node);
  }

  int _intOf(String key) =>
      int.tryParse(_controller(key)?.text.trim() ?? '') ?? 0;

  bool get _hasSize => _node('width') != null && _node('height') != null;

  @override
  void initState() {
    super.initState();
    // 只做「认出当前尺寸」，不写任何东西
    _ratio = ratioForSize(_intOf('width'), _intOf('height'));
    _longEdge = longEdgeForSize(_intOf('width'), _intOf('height'));
  }

  void _applySize() {
    final ratio = _ratio;
    final edge = _longEdge;
    if (ratio == null || edge == null) return;
    final size = sizeForRatio(kSizeRatios[ratio]!, edge);
    _controller('width')?.text = size.width.toString();
    _controller('height')?.text = size.height.toString();
    setState(() {});
  }

  void _applyBatch(int delta) {
    final controller = _controller('batch_size');
    if (controller == null) return;
    final current = int.tryParse(controller.text.trim()) ?? kBatchMin;
    final next = (current + delta).clamp(kBatchMin, kBatchMax);
    controller.text = next.toString();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final batchNode = _node('batch_size');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_hasSize) ...[
          _sectionLabel(l.runSizeRatio),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: kSizeRatios.keys.map((name) {
              final selected = _ratio == name;
              return ChoiceChip(
                label: Text(name, style: const TextStyle(fontSize: 12)),
                selected: selected,
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onSelected: (_) {
                  setState(() {
                    _ratio = selected ? null : name;
                    // 没选过长边就给个默认档，避免点了比例没反应
                    _longEdge ??= kLongEdgeOptions[1];
                  });
                  if (!selected) _applySize();
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 10),
          _sectionLabel(l.runSizeLongEdge),
          _longEdgePicker(),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                '${_intOf('width')} × ${_intOf('height')}',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => setState(() => _custom = !_custom),
                child: Text(
                  l.runSizeCustom,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
          if (_custom) _customFields(l),
        ],
        if (batchNode != null) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  batchNode.alias,
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.remove, size: 18),
                visualDensity: VisualDensity.compact,
                onPressed: () => _applyBatch(-1),
              ),
              Text(
                (_controller('batch_size')?.text.trim() ?? '').isEmpty
                    ? '1'
                    : _controller('batch_size')!.text.trim(),
                style: const TextStyle(fontSize: 13),
              ),
              IconButton(
                icon: const Icon(Icons.add, size: 18),
                visualDensity: VisualDensity.compact,
                onPressed: () => _applyBatch(1),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _sectionLabel(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(text, style: const TextStyle(fontSize: 11, color: Colors.grey)),
  );

  Widget _longEdgePicker() {
    return Container(
      height: 32,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: kLongEdgeOptions.map((edge) {
          final selected = _longEdge == edge;
          return Expanded(
            child: InkWell(
              onTap: () {
                setState(() {
                  _longEdge = selected ? null : edge;
                  _ratio ??= '1:1';
                });
                if (!selected) _applySize();
              },
              child: Container(
                alignment: Alignment.center,
                color: selected ? Colors.blue.shade50 : null,
                child: Text(
                  '$edge',
                  style: TextStyle(
                    fontSize: 12,
                    color: selected
                        ? Colors.blue.shade700
                        : Colors.grey.shade700,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _customFields(AppLocalizations l) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _controller('width'),
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              isDense: true,
              hintText: 'width',
              border: const OutlineInputBorder(),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 8,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: _controller('height'),
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              isDense: true,
              hintText: 'height',
              border: const OutlineInputBorder(),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 8,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
