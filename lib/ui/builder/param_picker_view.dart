import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/workflow_node.dart';
import '../../services/workflow_node_parser.dart';
import '../widgets/compact_search_field.dart';
import 'param_row_helpers.dart';

/// 「添加参数」页：全量参数按节点分组摆在这里，勾完返回。
///
/// 它存在的前提是主视图只放已选参数 —— **全量列表必须有地方去**，
/// 而且必须一个不漏（解析器刻意不裁剪识别范围，见 `NodeRule.keys`）。
///
/// [nodes] 传的是引用：这里的勾选直接改在主视图那份数据上，
/// 不需要返回值。返回时主视图自己 `setState` 重算已选列表。
class ParamPickerView extends StatefulWidget {
  const ParamPickerView({
    super.key,
    required this.nodes,
    required this.aliasControllers,
    required this.issues,
  });

  final List<WorkflowNode> nodes;
  final Map<String, TextEditingController> aliasControllers;
  final SpecIssues issues;

  @override
  State<ParamPickerView> createState() => _ParamPickerViewState();
}

class _ParamPickerViewState extends State<ParamPickerView> {
  final Set<String> _expandedNodeIds = {};
  final Set<String> _collapsedNodeIds = {};
  final TextEditingController _searchController = TextEditingController();
  String _keyword = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// 当前实际显示的参数：按关键字过滤别名 / 参数名 / 节点类名。
  ///
  /// 过滤粒度是"参数"而非"节点"：命中哪个参数就只显示哪个参数。
  /// 若按节点整体保留，搜一个词会把该节点的几十个参数一起带出来。
  List<WorkflowNode> get _visibleNodes => _keyword.isEmpty
      ? widget.nodes
      : widget.nodes
            .where(
              (n) =>
                  n.alias.toLowerCase().contains(_keyword) ||
                  n.key.toLowerCase().contains(_keyword) ||
                  n.classType.toLowerCase().contains(_keyword),
            )
            .toList();

  Widget _buildSearchField(AppLocalizations l) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: CompactSearchField(
        controller: _searchController,
        hintText: l.configSearchHint,
        hasText: _keyword.isNotEmpty,
        onChanged: (v) => setState(() => _keyword = v.trim().toLowerCase()),
        onClear: () {
          _searchController.clear();
          setState(() => _keyword = '');
        },
      ),
    );
  }

  /// 工具条：左边统计，右边批量展开 / 折叠。
  ///
  /// 刻意**不做全局全选** —— 一键全勾会把几十个参数全放出来，
  /// 手机表单直接没法用。全选只放在单个节点卡片内部。
  Widget _buildToolbar(AppLocalizations l) {
    final exposedTotal = widget.nodes.where((n) => n.exposed).length;
    const textStyle = TextStyle(fontSize: 13);
    final buttonStyle = TextButton.styleFrom(
      textStyle: const TextStyle(fontSize: 13),
      visualDensity: VisualDensity.compact,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              exposedTotal > 0
                  ? l.configSelectedCount(exposedTotal, widget.nodes.length)
                  : l.configParamCount(widget.nodes.length),
              style: textStyle.copyWith(
                color: exposedTotal > 0 ? Colors.green.shade700 : Colors.grey,
              ),
            ),
          ),
          TextButton.icon(
            style: buttonStyle,
            onPressed: () => setState(() {
              _collapsedNodeIds.clear();
              _expandedNodeIds.addAll(widget.nodes.map((n) => n.id));
            }),
            icon: const Icon(Icons.unfold_more, size: 18),
            label: Text(l.configExpandAll),
          ),
          TextButton.icon(
            style: buttonStyle,
            onPressed: () => setState(() {
              _expandedNodeIds.clear();
              _collapsedNodeIds.addAll(widget.nodes.map((n) => n.id));
            }),
            icon: const Icon(Icons.unfold_less, size: 18),
            label: Text(l.configCollapseAll),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupList(AppLocalizations l) {
    final groups = <String, List<WorkflowNode>>{};
    for (final n in _visibleNodes) {
      groups.putIfAbsent(n.id, () => []).add(n);
    }
    final groupIds = groups.keys.toList();

    // 有参数、但一个都没命中：说明是搜空了。
    // 不提示的话整片留白，看着像页面坏了。
    if (groupIds.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            l.configSearchEmpty,
            style: const TextStyle(color: Colors.grey),
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: groupIds.length,
      itemBuilder: (context, index) {
        final nodeId = groupIds[index];
        final params = groups[nodeId]!;
        final exposedCount = params.where((p) => p.exposed).length;
        final allExposed = params.isNotEmpty && exposedCount == params.length;

        // 默认展开含已勾选参数的节点，其余收起；搜索命中时一并展开 ——
        // 否则卡片留在列表里却是收起的，用户不知道自己搜到了什么。
        final expanded = _expandedNodeIds.contains(nodeId)
            ? true
            : _collapsedNodeIds.contains(nodeId)
            ? false
            : _keyword.isNotEmpty || exposedCount > 0;

        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.grey.shade200),
          ),
          child: Column(
            children: [
              InkWell(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(12),
                ),
                onTap: () => setState(() {
                  if (expanded) {
                    _collapsedNodeIds.add(nodeId);
                    _expandedNodeIds.remove(nodeId);
                  } else {
                    _expandedNodeIds.add(nodeId);
                    _collapsedNodeIds.remove(nodeId);
                  }
                }),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      AnimatedRotation(
                        turns: expanded ? 0 : -0.25,
                        duration: const Duration(milliseconds: 150),
                        child: const Icon(
                          Icons.expand_more,
                          size: 20,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          nodeGroupLabel(params, l),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        exposedCount > 0
                            ? l.configSelectedCount(exposedCount, params.length)
                            : l.configParamCount(params.length),
                        style: TextStyle(
                          fontSize: 11,
                          color: exposedCount > 0
                              ? Colors.green.shade700
                              : Colors.grey,
                        ),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        iconSize: 20,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        tooltip: allExposed
                            ? l.configNodeClearAll
                            : l.configNodeSelectAll,
                        onPressed: () => setState(() {
                          for (final p in params) {
                            p.exposed = !allExposed;
                          }
                        }),
                        icon: Icon(
                          allExposed ? Icons.deselect : Icons.select_all,
                          size: 20,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (expanded)
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
                  child: Column(
                    children: [
                      const Divider(height: 1),
                      ...params.map(
                        (node) => buildParamConfigRow(
                          context,
                          node: node,
                          aliasControllers: widget.aliasControllers,
                          issues: widget.issues,
                          onChanged: () => setState(() {}),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.configPickerTitle)),
      body: Column(
        children: [
          _buildSearchField(l),
          _buildToolbar(l),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text(
              l.configPanelHint,
              style: const TextStyle(color: Colors.black54, fontSize: 13),
            ),
          ),
          Expanded(child: _buildGroupList(l)),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: Colors.green,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    l.configPickerDone,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
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
