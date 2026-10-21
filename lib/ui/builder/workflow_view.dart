import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:comfyui_mobilepocket/l10n/app_localizations.dart';

import '../../models/workflow_node.dart';
import '../../providers/workflow_provider.dart';
import '../../services/workflow_node_parser.dart';
import '../../providers/snapshot_provider.dart';
import '../../providers/local_workflow_provider.dart';
import '../../utils.dart';
import '../widgets/compact_search_field.dart';
import '../widgets/param_config_tile.dart';
import 'run_view.dart'; // 下一步我们将创建运行页面

class WorkflowView extends ConsumerStatefulWidget {
  final String workflowId;

  /// 非空时进入「快照模式」：解析快照里的工作流 JSON，
  /// 保存配置只写回快照，不碰线上工作流的 mapping 配置。
  final String? snapshotId;

  const WorkflowView({super.key, required this.workflowId, this.snapshotId});

  @override
  ConsumerState<WorkflowView> createState() => _WorkflowViewState();
}

class _WorkflowViewState extends ConsumerState<WorkflowView> {
  bool _isReady = false;
  List<WorkflowNode> _extractableNodes = [];
  // 别名输入框控制器统一挂到 State 上，随页面销毁一并释放（避免 build 内新建导致泄漏）
  final Map<String, TextEditingController> _aliasControllers = {};
  // 节点分组的展开/收起状态（用户手动切换）
  final Set<String> _expandedNodeIds = {};
  final Set<String> _collapsedNodeIds = {};
  // 搜索关键字：只影响列表过滤，不改数据
  String _keyword = '';

  final TextEditingController _searchController = TextEditingController();

  /// 当前实际显示的参数：按关键字过滤别名 / 参数名 / 节点类名。
  ///
  /// 过滤粒度是"参数"而非"节点"：命中哪个参数就只显示哪个参数。
  /// 若按节点整体保留，搜一个词会把该节点的几十个参数一起带出来，搜索就没意义了。
  /// 卡片头部的统计与全选按钮跟随可见参数走，保证"看到的就是能选的"。
  List<WorkflowNode> get _visibleNodes => _keyword.isEmpty
      ? _extractableNodes
      : _extractableNodes
            .where(
              (n) =>
                  n.alias.toLowerCase().contains(_keyword) ||
                  n.key.toLowerCase().contains(_keyword) ||
                  n.classType.toLowerCase().contains(_keyword),
            )
            .toList();

  @override
  void dispose() {
    _searchController.dispose();
    for (final c in _aliasControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _initData();
  }

  bool get _isSnapshotMode => widget.snapshotId != null;

  bool get _isLocal => widget.workflowId.startsWith('local_');

  bool get _isParsed => widget.workflowId.startsWith('parsed_');

  /// 本地资产与解析缓存的持久化数据（命中则不必请求服务器）
  Map<String, dynamic>? get _persisted =>
      persistedWorkflowJson(ref, widget.workflowId);

  Future<void> _initData() async {
    final notifier = ref.read(workflowProvider.notifier);

    if (_isSnapshotMode) {
      final snapshot = ref
          .read(snapshotProvider.notifier)
          .byId(widget.snapshotId!);
      if (snapshot == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).workflowSnapshotDeleted),
          ),
        );
        Navigator.pop(context);
        return;
      }
      // 用快照里保存的配置作为「已保存配置」，不读线上的 mapping_
      _parseWorkflow(
        snapshot.workflowJson,
        savedConfig: snapshot.mappingConfig,
      );
    } else if (_isLocal || _isParsed) {
      // 本地资产与解析缓存都持久化在本地，重启后依然可用
      final entry = _persisted;
      if (entry == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _isLocal
                  ? AppLocalizations.of(context).workflowLocalMissing
                  : AppLocalizations.of(context).workflowParsedCleared,
            ),
          ),
        );
        Navigator.pop(context);
        return;
      }
      // 顺带写进缓存，供运行页直接从缓存取，不必再回各自的库里读一次。
      // 首屏是从 initState 进来的，写 provider 必须让出当前帧。
      await scheduleProviderWrite(
        () => ref
            .read(workflowProvider.notifier)
            .setWorkflowData(entry, workflowId: widget.workflowId),
      );
      _parseWorkflow(entry);
    } else {
      final success = await notifier.fetchWorkflowContent(widget.workflowId);
      if (!success) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).workflowFetchFailed),
          ),
        );
        Navigator.pop(context);
        return;
      }
      _parseWorkflow(ref.read(workflowProvider).currentWorkflowData!);
    }

    if (!mounted) return;
    setState(() {
      _isReady = true;
    });
  }

  void _parseWorkflow(
    Map<String, dynamic> jsonMap, {
    bool useSavedConfig = true,

    /// 直接指定「已保存配置」（快照模式用），优先级高于从 prefs 读
    List<WorkflowNode>? savedConfig,
  }) {
    // 解析规则已抽到 services/workflow_node_parser.dart：
    // 那边是一张手写的数据化规则表（认哪些节点 / 暴露哪些参数 / 各是什么类型），
    // 这里只负责把结果与「已保存配置」合并。
    final nodes = WorkflowNodeParser.parse(
      jsonMap,
      l: AppLocalizations.of(context),
    );

    // 默认优先使用历史保存的配置，但以最新解析为基准做合并：
    // 参数集合/类型/当前值取新解析（保证旧配置自动补齐新参数、类型不回退），
    // 仅保留用户在旧配置里的勾选状态与别名
    if (useSavedConfig) {
      final config =
          savedConfig ??
          ref
              .read(workflowProvider.notifier)
              .getMappingConfig(widget.workflowId);
      if (config != null && config.isNotEmpty) {
        final savedConfig = config;
        if (nodes.isEmpty) {
          // 新解析为空（工作流内容异常等）时兜底保留旧配置，避免误清空
          _extractableNodes = savedConfig;
        } else {
          final savedByKey = {
            for (final n in savedConfig) nodeParamKey(n.id, n.key): n,
          };
          _extractableNodes = nodes.map((n) {
            final saved = savedByKey[nodeParamKey(n.id, n.key)];
            if (saved == null) return n;
            return WorkflowNode(
              id: n.id,
              classType: n.classType,
              key: n.key,
              alias: saved.alias.isNotEmpty ? saved.alias : n.alias,
              exposed: saved.exposed,
              title: n.title,
              paramType: n.paramType,
              options: n.options,
              value: n.value,
            );
          }).toList();
        }
        return;
      }
    }
    _extractableNodes = nodes;
  }

  // 重新解析：放弃已保存的映射，用工作流当前结构重新提取参数。
  // 用于服务器端工作流更新后，让 App 重新识别新参数。
  Future<void> _reparse() async {
    setState(() {
      _extractableNodes = [];
      _isReady = false;
    });

    // 快照用快照里的 JSON；本地从本地库读；线上则重新拉取最新内容
    if (_isSnapshotMode) {
      final snapshot = ref
          .read(snapshotProvider.notifier)
          .byId(widget.snapshotId!);
      if (snapshot == null) {
        if (!mounted) return;
        setState(() => _isReady = true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).workflowSnapshotDeleted),
          ),
        );
        return;
      }
      _parseWorkflow(snapshot.workflowJson, useSavedConfig: false);
    } else if (_isLocal || _isParsed) {
      final entry = _persisted;
      if (entry == null) {
        if (!mounted) return;
        setState(() => _isReady = true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _isLocal
                  ? AppLocalizations.of(context).workflowLocalMissing
                  : AppLocalizations.of(context).workflowParsedCleared,
            ),
          ),
        );
        return;
      }
      await scheduleProviderWrite(
        () => ref
            .read(workflowProvider.notifier)
            .setWorkflowData(entry, workflowId: widget.workflowId),
      );
      _parseWorkflow(entry, useSavedConfig: false);
    } else {
      final ok = await ref
          .read(workflowProvider.notifier)
          .fetchWorkflowContent(widget.workflowId);
      if (!ok) {
        if (!mounted) return;
        setState(() => _isReady = true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).workflowRefetchFailed),
          ),
        );
        return;
      }
      _parseWorkflow(
        ref.read(workflowProvider).currentWorkflowData!,
        useSavedConfig: false,
      );
    }

    if (!mounted) return;
    // 清掉旧的别名控制器，避免与新解析出的节点错位
    for (final c in _aliasControllers.values) {
      c.dispose();
    }
    _aliasControllers.clear();
    setState(() => _isReady = true);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context).workflowReparsed)),
    );
  }

  // 分组卡片的头部标签：优先展示节点标题（有辨识度），无有效标题回退类名
  String _groupLabel(List<WorkflowNode> params) {
    final classType = params.first.classType;
    final title = params.first.title;
    if (isMeaningfulTitle(title, classType)) {
      return title;
    }
    return classType;
  }

  // 配置面板里单个参数行：勾选 + 别名编辑 + 类型/当前值摘要
  //
  // 紧凑版：勾选行 44 + 别名输入框 36（常显，不藏进二级入口），
  // 类型说明与当前值合并成行尾一行小字。详见 ParamConfigTile。
  Widget _buildParamRow(WorkflowNode node) {
    final controllerKey = nodeParamKey(node.id, node.key);
    final controller = _aliasControllers.putIfAbsent(
      controllerKey,
      () => TextEditingController(text: node.alias),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: ParamConfigTile(
        alias: node.alias,
        summary: _describeParam(node, AppLocalizations.of(context)),
        exposed: node.exposed,
        onChanged: (val) {
          setState(() {
            node.exposed = val ?? false;
          });
        },
        aliasController: controller,
        aliasHint: AppLocalizations.of(context).paramAliasHint,
        // 保存时用的是 node.alias，控制器文本必须回写，否则改了不生效
        onAliasChanged: (val) => node.alias = val,
      ),
    );
  }

  // 配置面板里参数卡片的一行摘要：类型 + 当前值
  String _describeParam(WorkflowNode node, AppLocalizations l) {
    final typeName =
        {
          ParamType.text: l.paramTypeText,
          ParamType.seed: l.paramTypeSeed,
          ParamType.image: l.paramTypeImage,
          ParamType.intType: l.paramTypeInt,
          ParamType.float: l.paramTypeFloat,
          ParamType.boolType: l.paramTypeBool,
          ParamType.enumType: l.paramTypeEnum,
        }[node.paramType] ??
        l.paramTypeDefault;

    final v = node.value;
    String valueStr = '';
    if (v != null) {
      valueStr = v.toString();
      if (valueStr.length > 20) valueStr = '${valueStr.substring(0, 20)}…';
    }
    return valueStr.isEmpty
        ? l.paramSummaryType(typeName)
        : l.paramSummaryTypeValue(typeName, valueStr);
  }

  /// 列表上方工具条：左边统计，右边批量展开 / 折叠。
  ///
  /// 刻意**不做全局全选** —— 勾参数应当是"逐个看、逐个选"的事，
  /// 一键全勾会把几十个参数全放出来，运行页直接没法用。
  /// 全选只放在单个节点卡片内部。
  Widget _buildToolbar() {
    final l = AppLocalizations.of(context);
    final exposedTotal = _extractableNodes.where((n) => n.exposed).length;

    // 区块内字号统一 13：以前计数是 11、按钮是默认 14，混在一行里大小不齐。
    const textStyle = TextStyle(fontSize: 13);
    // 用 visualDensity 收紧按钮内边距，而不是 styleFrom(padding: …) ——
    // 后者会把水平内边距一起清掉。
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
                  ? l.configSelectedCount(
                      exposedTotal,
                      _extractableNodes.length,
                    )
                  : l.configParamCount(_extractableNodes.length),
              style: textStyle.copyWith(
                color: exposedTotal > 0 ? Colors.green.shade700 : Colors.grey,
              ),
            ),
          ),
          TextButton.icon(
            style: buttonStyle,
            onPressed: () => setState(() {
              _collapsedNodeIds.clear();
              _expandedNodeIds.addAll(_extractableNodes.map((n) => n.id));
            }),
            icon: const Icon(Icons.unfold_more, size: 18),
            label: Text(l.configExpandAll),
          ),
          TextButton.icon(
            style: buttonStyle,
            onPressed: () => setState(() {
              _expandedNodeIds.clear();
              _collapsedNodeIds.addAll(_extractableNodes.map((n) => n.id));
            }),
            icon: const Icon(Icons.unfold_less, size: 18),
            label: Text(l.configCollapseAll),
          ),
        ],
      ),
    );
  }

  /// 搜索框：按别名 / 参数名 / 节点类名过滤（只影响显示，不改数据）。
  /// 与生成记录页共用同一个紧凑搜索框。
  Widget _buildSearchField() {
    final l = AppLocalizations.of(context);
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

  void _handleSaveMapping() {
    if (_isSnapshotMode) {
      // 只写回快照：此刻原工作流未必还在，不能去改线上的 mapping 配置
      ref
          .read(snapshotProvider.notifier)
          .updateMappingConfig(widget.snapshotId!, _extractableNodes);
    } else {
      ref
          .read(workflowProvider.notifier)
          .saveMappingConfig(widget.workflowId, _extractableNodes);
    }
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => RunView(
          workflowId: widget.workflowId,
          snapshotId: widget.snapshotId,
        ),
      ),
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context).configSaved)),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_isReady) {
      return Scaffold(
        appBar: AppBar(
          title: Text(AppLocalizations.of(context).configParsingTitle),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final displayName = resolveWorkflowName(
      ref.read(knownWorkflowEntriesProvider),
      widget.workflowId,
      localLabel: AppLocalizations.of(context).workflowLocalImport,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(
          AppLocalizations.of(context).configPanelTitle(displayName),
          style: const TextStyle(fontSize: 16),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: AppLocalizations.of(context).configReparseTooltip,
            onPressed: _reparse,
          ),
        ],
      ),
      body: Column(
        children: [
          // 顶部三块顺序固定为「搜索 → 工具条 → 说明」，
          // 相互间距统一 8，避免三块各自一个边距。
          if (_extractableNodes.isNotEmpty) _buildSearchField(),
          if (_extractableNodes.isNotEmpty) _buildToolbar(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text(
              AppLocalizations.of(context).configPanelHint,
              // 与工具条同为 13：三块挨在一起，字号不齐会显得脏
              style: const TextStyle(color: Colors.black54, fontSize: 13),
            ),
          ),
          Expanded(
            child: _extractableNodes.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32.0),
                      child: Text(
                        AppLocalizations.of(context).configNoParams,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.grey),
                      ),
                    ),
                  )
                : Builder(
                    builder: (context) {
                      // 按节点分组展示：同一节点的多个参数合并为一张卡片
                      final groups = <String, List<WorkflowNode>>{};
                      for (final n in _visibleNodes) {
                        groups.putIfAbsent(n.id, () => []).add(n);
                      }
                      final groupIds = groups.keys.toList();
                      return ListView.builder(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        itemCount: groupIds.length,
                        itemBuilder: (context, index) {
                          final nodeId = groupIds[index];
                          final params = groups[nodeId]!;
                          final exposedCount = params
                              .where((p) => p.exposed)
                              .length;
                          // 供卡片头部的「全选 / 取消全选」判断当前是否已全勾
                          final allExposed =
                              params.isNotEmpty &&
                              exposedCount == params.length;

                          // 默认展开含已勾选参数的节点，其余收起；用户可手动切换。
                          // 搜索命中时一并展开 —— 否则卡片留在列表里却是收起的，
                          // 用户不知道自己搜到了什么。手动展开/折叠的状态始终优先。
                          final expanded = _expandedNodeIds.contains(nodeId)
                              ? true
                              : _collapsedNodeIds.contains(nodeId)
                              ? false
                              : _keyword.isNotEmpty || exposedCount > 0;

                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                              side: BorderSide(color: Colors.grey.shade300),
                            ),
                            child: Column(
                              children: [
                                // 节点分组头部：类名 + 参数统计 + 展开/收起
                                InkWell(
                                  borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(8),
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
                                          duration: const Duration(
                                            milliseconds: 150,
                                          ),
                                          child: const Icon(
                                            Icons.expand_more,
                                            size: 20,
                                            color: Colors.grey,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            _groupLabel(params),
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        Text(
                                          exposedCount > 0
                                              ? AppLocalizations.of(context)
                                                    .configSelectedCount(
                                                      exposedCount,
                                                      params.length,
                                                    )
                                              : AppLocalizations.of(context)
                                                    .configParamCount(
                                                      params.length,
                                                    ),
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
                                              ? AppLocalizations.of(context)
                                                    .configNodeClearAll
                                              : AppLocalizations.of(context)
                                                    .configNodeSelectAll,
                                          onPressed: () => setState(() {
                                            for (final p in params) {
                                              p.exposed = !allExposed;
                                            }
                                          }),
                                          icon: Icon(
                                            allExposed
                                                ? Icons.deselect
                                                : Icons.select_all,
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
                                    padding: const EdgeInsets.fromLTRB(
                                      10,
                                      0,
                                      10,
                                      8,
                                    ),
                                    child: Column(
                                      children: [
                                        const Divider(height: 1),
                                        ...params.map(
                                          (node) => _buildParamRow(node),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          );
                        },
                      );
                    },
                  ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: Colors.green,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: _handleSaveMapping,
                  child: Text(
                    AppLocalizations.of(context).configSaveButton,
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
