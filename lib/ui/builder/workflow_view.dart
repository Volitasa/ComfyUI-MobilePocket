import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:comfyui_mobilepocket/l10n/app_localizations.dart';

import '../../models/workflow_node.dart';
import '../../providers/workflow_provider.dart';
import '../../services/workflow_node_parser.dart';
import '../../providers/snapshot_provider.dart';
import '../../providers/local_workflow_provider.dart';
import '../../providers/connection_provider.dart';
import '../../providers/object_info_provider.dart';
import '../../services/node_role.dart';
import '../../services/object_info_service.dart';
import '../../utils.dart';
import '../widgets/page_title.dart';
import 'param_picker_view.dart';
import 'param_row_helpers.dart';
import '../../theme.dart';
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
  //
  // ⚠️ 这份 map 要传给「添加参数」页：那边改了别名，回主视图必须是同一个控制器，
  // 否则会出现「在添加页改了名、回主视图又变回旧的」。
  final Map<String, TextEditingController> _aliasControllers = {};

  /// 本次拿到的服务器说明书（classType → 定义）。**只放内存，不落盘**（方案 §3.2）。
  Map<String, NodeSpec> _specs = const {};

  /// 本次取数是否降级过（超时 / 拿不到）→ 顶部提示，不阻塞使用。
  bool _specsDegraded = false;

  /// 工作流与说明书对不上的地方（缺节点 / 缺参数），供标黄用。不落盘。
  SpecIssues _specIssues = const SpecIssues();

  /// 节点在图里的角色（正向 / 负向 / 装了什么）。**只放内存，不落盘**：
  /// 它随时能从工作流 JSON 重算，存一份只会多一处要跟着改的地方。
  Map<String, NodeRole> _nodeRoles = const {};

  /// 已放进手机表单的参数 —— 主视图只展示这批。
  ///
  /// 整页的取舍都系在这一行上：用户来这里是**确认系统替他挑好的结果**，
  /// 不是从几十项里做减法。全部参数一个不少地留在「添加参数」页里，
  /// 只是不默认摆在主视图上。
  List<WorkflowNode> get _selectedNodes =>
      _extractableNodes.where((n) => n.exposed).toList();

  @override
  void dispose() {
    for (final c in _aliasControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// 只解析一次：_initData 可能被 didChangeDependencies 触发多次
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 不放在 initState 里：_parseWorkflow 要用 AppLocalizations（InheritedWidget），
    // 而 initState 阶段还不允许查 —— 快照模式在那一帧同步解析，debug 下直接断言崩溃。
    if (_started) return;
    _started = true;
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

    // 三个分支只负责把「要解析的 JSON」弄到手，取说明书与解析统一放后面，
    // 免得某条路径漏掉定型。
    Map<String, dynamic>? jsonMap;
    List<WorkflowNode>? savedConfig;

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
      jsonMap = snapshot.workflowJson;
      savedConfig = snapshot.mappingConfig;
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
      jsonMap = entry;
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
      jsonMap = ref.read(workflowProvider).currentWorkflowData!;
    }

    // 取服务器说明书（§3.1）：扫出全部 class_type → 去重 → 并发取 → 整体预算 2s。
    // 取齐才解析；超预算就按已拿到的定型，绝不让页面一直转圈。
    _specs = await _loadSpecs(jsonMap);
    // ⚠️ 取说明书那两秒里用户可能已经按了返回键。State 一旦销毁就不能再碰 context
    // （_parseWorkflow 里要查 AppLocalizations），release 下会拿到 null 直接崩。
    // 所以过了 await 先问一句还活着没，再往下走。
    if (!mounted) return;
    // ⚠️ 必须把 _specs 传进去 —— 不然控制页拿到的说明书只用来算「缺参数」标黄，
    // `control` / `bounds` 一个都不会写，等于整期功能没生效（2026-10-23 修）。
    _parseWorkflow(jsonMap, savedConfig: savedConfig, specs: _specs);
    _specIssues = WorkflowNodeParser.computeIssues(_extractableNodes, _specs);
    _nodeRoles = inferNodeRoles(jsonMap);

    setState(() {
      _isReady = true;
    });
  }

  /// 向服务器取本工作流用到的节点说明书（§3.1）。
  ///
  /// 按 `class_type` 去重后并发取（provider 内部并发 4），整体预算
  /// [kConfigSpecBudget]。**超时即定型**：已返回的部分照常采用，
  /// 未返回的按 §3.3 保留旧 `control`（有旧值）或走推断（没有旧值）。
  ///
  /// 拿不到说明书不能让表单打不开，也不该弹任何错误。
  Future<Map<String, NodeSpec>> _loadSpecs(Map<String, dynamic> jsonMap) async {
    // 每次重新取数都重算降级提示，别让上一次的结论粘住
    _specsDegraded = false;

    final classTypes = WorkflowNodeParser.collectClassTypes(jsonMap);
    if (classTypes.isEmpty) return const {};

    final config = ref.read(connectionProvider);
    final baseUrl = config.comfyUrl;
    final serverId = config.activeServerId;
    if (!config.isConnected ||
        baseUrl.isEmpty ||
        serverId == null ||
        serverId.isEmpty) {
      _specsDegraded = true;
      return const {};
    }

    // 让出当前帧再写 provider：_initData 可能由 didChangeDependencies 同步触发。
    final task = () async {
      await scheduleProviderWrite(() async {
        await ref
            .read(objectInfoProvider.notifier)
            .ensureLoaded(
              serverId: serverId,
              baseUrl: baseUrl,
              classTypes: classTypes,
            );
      });
    }();

    // 整体预算：超时就走，不等了。
    // 请求仍在飞，回来后会写进缓存，下次进页面直接命中。
    final finished = await waitWithin(task, kConfigSpecBudget);

    // ⚠️ 超时不是失败：已返回的那部分照常采用（§3.3），只提示降级。
    final state = ref.read(objectInfoProvider);
    // 一个节点都没拿到说明书 → 控件全是推断出来的，得说一句。
    // 只认 `ok`：`empty`（服务器不认识）与 `failure` 都拿不到可用的 spec。
    final gotAny = classTypes.any(
      (t) => state.statusFor(serverId, t) == ObjectInfoFetchStatus.ok,
    );
    if (!finished || !gotAny) _specsDegraded = true;

    return <String, NodeSpec>{
      // 缓存里存的是 NodeSpecEntry（说明书 + 取数状态），定型只要规格那一半。
      //
      // ⚠️ **取数失败的条目必须排除**：它的 spec 也是空 Map，交给
      // `computeIssues` 会被当成「服务器不认识这个节点」而误标黄。
      // 空 spec 只有在**确实问到了**（status == empty）时才算缺节点（方案 §3.7）。
      for (final t in classTypes)
        if (state.statusFor(serverId, t) != null &&
            state.statusFor(serverId, t) != ObjectInfoFetchStatus.failure)
          t: state.byServer[serverId]![t]!.spec,
    };
  }

  void _parseWorkflow(
    Map<String, dynamic> jsonMap, {
    bool useSavedConfig = true,

    /// 直接指定「已保存配置」（快照模式用），优先级高于从 prefs 读
    List<WorkflowNode>? savedConfig,

    /// 服务器说明书（classType → 定义）。仅用于定型，不落盘。
    Map<String, NodeSpec>? specs,
  }) {
    // 解析规则已抽到 services/workflow_node_parser.dart：
    // 那边是一张手写的数据化规则表（认哪些节点 / 暴露哪些参数 / 各是什么类型），
    // 这里只负责把结果与「已保存配置」合并。
    final nodes = WorkflowNodeParser.parse(
      jsonMap,
      l: AppLocalizations.of(context),
      specs: specs,
    );

    // 默认优先使用历史保存的配置，但以最新解析为基准做合并：
    // 参数集合/类型/当前值取新解析（保证旧配置自动补齐新参数、类型不回退），
    // 仅保留用户在旧配置里的勾选状态与别名
    if (useSavedConfig) {
      final config =
          savedConfig ??
          ref
              .read(workflowProvider.notifier)
              .getMappingConfig(
                widget.workflowId,
                // 与保存时同一个口径，否则存进去了却读不出来
                serverId: ref.read(connectionProvider).activeServerId,
              );
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
            // 旧版会把「节点标题」当成没收录参数的别名（多参数节点上于是全叫
            // 加载CLIP / UNet加载器）。那不是用户改的，按未自定义处理，
            // 让新的默认别名（真实参数名）生效 —— 重新保存一次配置即可自愈。
            final customizedAlias =
                saved.alias.isNotEmpty && saved.alias != saved.title;

            // ⚠️ 必须用 copyWith：手工构造只传旧字段会静默清空
            // `control` / `bounds`（方案 §8.1 陷阱 1）。
            final merged = n.copyWith(
              alias: customizedAlias ? saved.alias : n.alias,
              exposed: saved.exposed,
            );

            // 参数集合 / paramType / 当前值取新解析（保证旧配置自动补齐新参数、
            // 类型不回退）；`control` / `bounds` 本次取到说明书就用新的，
            // 没取到则保留旧值 —— 不能把服务器结论降级成推断（§3.3）。
            return merged.copyWith(
              control: n.control ?? saved.control,
              bounds: n.bounds ?? saved.bounds,
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
    // （与 _initData 同一套路：先只管把 JSON 弄到手，取数与解析统一放后面）
    Map<String, dynamic>? jsonMap;

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
      jsonMap = snapshot.workflowJson;
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
      jsonMap = entry;
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
      jsonMap = ref.read(workflowProvider).currentWorkflowData!;
    }

    // 与 _initData 同样的定型流程（重新解析也要重新问一次服务器）
    _specs = await _loadSpecs(jsonMap);
    // 同上：重新解析也要等两秒，这期间用户按了返回就不能再碰 context
    if (!mounted) return;
    _parseWorkflow(jsonMap, useSavedConfig: false, specs: _specs);
    _specIssues = WorkflowNodeParser.computeIssues(_extractableNodes, _specs);
    _nodeRoles = inferNodeRoles(jsonMap);

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

  /// 打开「添加参数」页：全量参数按节点分组摆在那边，勾完返回。
  ///
  /// 传的是同一份 List 引用，勾选直接改在原数据上；回来只要重建一次。
  Future<void> _openPicker() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ParamPickerView(
          nodes: _extractableNodes,
          aliasControllers: _aliasControllers,
          issues: _specIssues,
          roles: _nodeRoles,
        ),
      ),
    );
    if (!mounted) return;
    setState(() {});
  }

  /// 顶部统计：说清「表单里现在有什么」，不解释底层机制。
  Widget _buildSummary(AppLocalizations l) {
    final selected = _selectedNodes.length;
    final total = _extractableNodes.length;
    // 一个都没选时这句话由列表区当空态说，这里不再重复一遍
    if (selected == 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l.configFormCount(selected, total),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: Colors.green.shade700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            l.configFormHint,
            style: TextStyle(fontSize: 11, color: context.textSecondary),
          ),
        ],
      ),
    );
  }

  /// 已放进表单的参数：一张卡片、一行一项，行尾是移出。
  ///
  /// 刻意**不做重排序**：顺序跟着工作流里的节点顺序走，和运行页一致，
  /// 免得这里排了一遍、那边又是另一个顺序。
  Widget _buildSelectedCard() {
    final selected = _selectedNodes;
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: context.borderColor),
      ),
      child: Column(
        children: [
          for (var i = 0; i < selected.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            buildParamConfigRow(
              context,
              node: selected[i],
              aliasControllers: _aliasControllers,
              issues: _specIssues,
              onChanged: () => setState(() {}),
              showCheckbox: false,
              // 主视图的参数是混着排的：行尾要说清它属于哪个节点
              showNodeInSummary: true,
              onRemove: () => setState(() => selected[i].exposed = false),
            ),
          ],
        ],
      ),
    );
  }

  /// 「添加参数」入口：全量参数的唯一去处，一个都不少。
  Widget _buildAddButton(AppLocalizations l) {
    final rest = _extractableNodes.length - _selectedNodes.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          onPressed: _openPicker,
          icon: const Icon(Icons.add, size: 18),
          label: Text(
            rest > 0 ? l.configAddParamsCount(rest) : l.configAddParams,
            style: const TextStyle(fontSize: 13),
          ),
        ),
      ),
    );
  }

  Future<void> _handleSaveMapping() async {
    final l = AppLocalizations.of(context);
    // await 之后 context 可能已经失效，先把要用的两样取出来
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    if (_isSnapshotMode) {
      // 只写回快照：此刻原工作流未必还在，不能去改线上的 mapping 配置
      ref
          .read(snapshotProvider.notifier)
          .updateMappingConfig(widget.snapshotId!, _extractableNodes);
    } else {
      // 等写盘真正完成再跳转：运行页在 initState 里同步读 mapping，
      // 抢在写入之前读就会出现「提示已保存、运行页却说没有表单」
      await ref
          .read(workflowProvider.notifier)
          .saveMappingConfig(
            widget.workflowId,
            _extractableNodes,
            // 服务器工作流按服务器存，避免两台服务器上同名文件共用一份配置
            serverId: ref.read(connectionProvider).activeServerId,
          );
    }
    if (!mounted) return;
    navigator.pushReplacement(
      MaterialPageRoute(
        builder: (_) => RunView(
          workflowId: widget.workflowId,
          snapshotId: widget.snapshotId,
        ),
      ),
    );
    messenger.showSnackBar(SnackBar(content: Text(l.configSaved)));
  }

  @override
  Widget build(BuildContext context) {
    if (!_isReady) {
      return Scaffold(
        appBar: AppBar(
          // 这一步是在向服务器问节点说明书（决定控件形态），
          // 取不到会在 2s 后降级 —— 文案说清在等什么，别只写「解析中」
          title: Text(
            AppLocalizations.of(context).configSpecsFetching,
            style: kSubPageTitleStyle,
          ),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final l = AppLocalizations.of(context);
    final displayName = resolveWorkflowName(
      ref.read(knownWorkflowEntriesProvider),
      widget.workflowId,
      localLabel: AppLocalizations.of(context).workflowLocalImport,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(
          AppLocalizations.of(context).configPanelTitle(displayName),
          style: kSubPageTitleStyle,
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
          if (_extractableNodes.isNotEmpty) _buildSummary(l),
          // 取说明书超时 / 拿不到：形状是推断出来的，明确告诉用户，
          // 但不阻塞勾选与保存（说明书只是加分项）。
          if (_specsDegraded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                children: [
                  const Icon(
                    Icons.info_outline,
                    size: 14,
                    color: Colors.orange,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      l.configSpecsDegraded,
                      style: const TextStyle(
                        color: Colors.orange,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: _extractableNodes.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32.0),
                      child: Text(
                        l.configNoParams,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: context.textSecondary),
                      ),
                    ),
                  )
                : _selectedNodes.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32.0),
                      child: Text(
                        l.configFormEmpty,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: context.textSecondary),
                      ),
                    ),
                  )
                : SingleChildScrollView(child: _buildSelectedCard()),
          ),
          if (_extractableNodes.isNotEmpty) _buildAddButton(l),

          SafeArea(
            child: Padding(
              // 底部按钮四周收紧：按钮本身 56 高已经够好点，外面不必再垫一圈 16
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
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
