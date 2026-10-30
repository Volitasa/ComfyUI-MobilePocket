import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/ai_task.dart';
import '../../../models/workflow_node.dart';
import '../../../theme.dart';

/// 节点选择器：抽屉内就地切换（不叠第二个 sheet）。
///
/// 每行必须给四件东西：类型图标、节点标题、参数名、**值摘要**。
/// 值摘要不能省——同名节点（两个「加载图像」）只有文件名能区分。
class AiNodePicker extends StatefulWidget {
  const AiNodePicker({
    super.key,
    required this.nodes,
    required this.initialSelected,
    required this.multi,
    required this.summaryOf,
    required this.scrollController,
    required this.onBack,
    required this.onConfirm,
  });

  final List<WorkflowNode> nodes;
  final Set<String> initialSelected;
  final bool multi;

  /// 一行里的值摘要（文本取正文，图片取文件名）。
  final String Function(WorkflowNode node) summaryOf;

  final ScrollController scrollController;
  final VoidCallback onBack;
  final ValueChanged<Set<String>> onConfirm;

  @override
  State<AiNodePicker> createState() => _AiNodePickerState();
}

enum _Tab { image, text, all }

class _AiNodePickerState extends State<AiNodePicker> {
  final Set<String> _selected = {};
  _Tab _tab = _Tab.image;
  String _query = '';
  late final TextEditingController _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _selected.addAll(widget.initialSelected);
    // 没有图片节点时默认落在「文本」页，避免一进来就是空的
    if (!widget.nodes.any(isImageInputNode)) _tab = _Tab.text;
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  static String _idOf(WorkflowNode n) => '${n.id}:${n.key}';

  String _titleOf(WorkflowNode n) =>
      n.title.trim().isEmpty ? n.classType : n.title;

  List<WorkflowNode> get _visible {
    final q = _query.trim().toLowerCase();
    return widget.nodes.where((n) {
      final tabOk = switch (_tab) {
        _Tab.image => isImageInputNode(n),
        _Tab.text => isTextTargetNode(n),
        _Tab.all => true,
      };
      if (!tabOk) return false;
      if (q.isEmpty) return true;
      final hay =
          '${_titleOf(n)} ${n.classType} ${n.key} ${widget.summaryOf(n)}'
              .toLowerCase();
      return hay.contains(q);
    }).toList();
  }

  void _toggle(WorkflowNode n) {
    final id = _idOf(n);
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
      } else {
        if (!widget.multi) _selected.clear();
        _selected.add(id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final items = _visible;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
          child: Row(
            children: [
              IconButton(
                onPressed: widget.onBack,
                icon: const Icon(Icons.arrow_back, size: 20),
                visualDensity: VisualDensity.compact,
              ),
              Text(
                l.aiPickNodes,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              ),
              const Spacer(),
              Text(
                l.aiSelectedCount(_selected.length),
                style: TextStyle(fontSize: 12, color: context.textSecondary),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: TextField(
            controller: _search,
            onChanged: (v) => setState(() => _query = v),
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              hintText: l.aiSearchNodes,
              isDense: true,
              prefixIcon: const Icon(Icons.search, size: 18),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(9),
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              _tabChip(l.aiTabImage, _Tab.image, l),
              const SizedBox(width: 6),
              _tabChip(l.aiTabText, _Tab.text, l),
              const SizedBox(width: 6),
              _tabChip(l.aiTabAll, _Tab.all, l),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: ListView.builder(
            controller: widget.scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
            itemCount: items.length,
            itemBuilder: (context, i) {
              final n = items[i];
              final id = _idOf(n);
              final selected = _selected.contains(id);
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: _PickerRow(
                  node: n,
                  title: _titleOf(n),
                  summary: widget.summaryOf(n),
                  selected: selected,
                  multi: widget.multi,
                  onTap: () => _toggle(n),
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _selected.isEmpty
                  ? null
                  : () => widget.onConfirm(_selected),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(44),
                backgroundColor: context.accent,
                foregroundColor: context.onAccent,
              ),
              child: Text(l.aiConfirmCount(_selected.length)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _tabChip(String label, _Tab tab, AppLocalizations l) {
    final on = _tab == tab;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _tab = tab),
        child: Container(
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on ? context.containerFill : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: on ? context.borderColor : Colors.transparent,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: on ? FontWeight.w500 : FontWeight.w400,
              color: on ? Theme.of(context).colorScheme.onSurface : context.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _PickerRow extends StatelessWidget {
  const _PickerRow({
    required this.node,
    required this.title,
    required this.summary,
    required this.selected,
    required this.multi,
    required this.onTap,
  });

  final WorkflowNode node;
  final String title;
  final String summary;
  final bool selected;
  final bool multi;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isImage = isImageInputNode(node);
    final l = AppLocalizations.of(context);
    return Material(
      color: selected ? context.containerFill : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? context.accent : context.borderColor,
            ),
          ),
          child: Row(
            children: [
              Icon(
                isImage ? Icons.image_outlined : Icons.text_fields,
                size: 16,
                color: context.accent,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        // 同名同值的节点（两个 CLIP文本编码、值都为空）只能靠 id 区分
                        Text(
                          '#${node.id}',
                          style: TextStyle(
                            fontSize: 10,
                            color: context.textSecondary,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: context.containerFill,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            node.key,
                            style: TextStyle(
                              fontSize: 10,
                              color: context.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      summary.isEmpty ? l.aiEmptyValue : summary,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: context.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                selected
                    ? (multi ? Icons.check_box : Icons.radio_button_checked)
                    : (multi
                          ? Icons.check_box_outline_blank
                          : Icons.radio_button_unchecked),
                size: 18,
                color: selected ? context.accent : context.borderColor,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
