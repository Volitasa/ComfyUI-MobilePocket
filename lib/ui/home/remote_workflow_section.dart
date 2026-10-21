import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:comfyui_mobilepocket/l10n/app_localizations.dart';

import '../../models/local_workflow.dart';
import '../../models/workflow_entry.dart';
import '../../providers/connection_provider.dart';
import '../../providers/local_workflow_provider.dart';
import '../../providers/parsed_workflow_provider.dart';
import '../../providers/task_manager.dart';
import '../../providers/workflow_provider.dart';
import '../../services/workflow_api_converter.dart';
import '../../utils.dart';
import '../../utils/workflow_last_run.dart';
import '../builder/run_view.dart';
import '../builder/workflow_parse_view.dart';
import '../builder/workflow_view.dart';
import '../settings/server_config_view.dart';
import '../widgets/workflow_tile.dart';

/// 服务器段：服务端工作流目录的投影。
///
/// 这里的条目都能从服务器重新获得，所以**不提供删除**，
/// 只提供刷新与「存入本地库」（把可再生的转成不可再生的资产）。
class RemoteWorkflowSection extends ConsumerWidget {
  const RemoteWorkflowSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final configState = ref.watch(connectionProvider);
    final workflowState = ref.watch(workflowProvider);
    // 只为「新任务产生/记录被删」时刷新列表上的「上次运行时间」。
    // 刻意不监听任务列表本身：WebSocket 每秒推好几次进度，
    // 直接监听会把整个工作流列表跟着重建（画廊页踩过这个坑）。
    ref.watch(taskManagerProvider.select((s) => s.history.length));

    if (!configState.isConnected) return _buildDisconnected(context);
    if (workflowState.isLoading) {
      return const Padding(
        padding: EdgeInsets.all(40),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (workflowState.isEmpty) return _buildEmpty(context);

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // 分组按格式而非状态：条目解析后不会在两组之间跳来跳去
        if (workflowState.workflowList.isNotEmpty) ...[
          _buildGroupTitle(AppLocalizations.of(context).homeGroupApi),
          ...workflowState.workflowList.map(
            (file) => _buildWorkflowCard(context, ref, file, workflowState),
          ),
          const SizedBox(height: 18),
        ],
        if (workflowState.uiWorkflowList.isNotEmpty) ...[
          _buildGroupTitle(AppLocalizations.of(context).homeGroupUi),
          ...workflowState.uiWorkflowList.map(
            (file) => _buildUiWorkflowCard(context, ref, file, workflowState),
          ),
          const SizedBox(height: 18),
        ],
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            AppLocalizations.of(context).homeWorkflowSourceNote,
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ),
      ],
    );
  }

  Widget _buildGroupTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, right: 4, bottom: 8),
      child: Text(
        text,
        style: const TextStyle(fontSize: 12, color: Colors.grey),
      ),
    );
  }

  /// UI 格式工作流：需要先用 ComfyUI 前端转换成 API 结构才能运行。
  ///
  /// 三态：未解析 / 已解析 / 服务器有更新。解析由用户手动单条触发——
  /// 它要加载整个前端，不适合在刷新时批量做。
  Widget _buildUiWorkflowCard(
    BuildContext context,
    WidgetRef ref,
    String filename,
    WorkflowState state,
  ) {
    final title = uiWorkflowTitle(filename);
    final serverId = ref.read(connectionProvider).activeServerId;
    final cached = ref
        .read(parsedWorkflowProvider.notifier)
        .byServerFile(serverId, filename);
    final status = state.uiStatusOf(filename);
    final stale = status == UiWorkflowStatus.stale;

    final exposedCount = cached == null
        ? 0
        : ref
                  .read(workflowProvider.notifier)
                  .getMappingConfig(cached.id)
                  ?.where((n) => n.exposed)
                  .length ??
              0;

    final l = AppLocalizations.of(context);
    final String subtitle;
    if (cached == null) {
      subtitle = l.uiStatusNotParsed;
    } else if (stale) {
      subtitle = l.uiStatusStale;
    } else if (status == UiWorkflowStatus.parsed) {
      subtitle = exposedCount == 0
          ? l.uiStatusParsed
          : l.uiStatusParsedWithCount(exposedCount);
    } else {
      subtitle = state.isChecking ? l.statusChecking : l.uiStatusParsed;
    }

    // 未解析的条目不描边：与「能用但还没配」的实线条目区分开
    final borderColor = stale ? const Color(0xFF854F0B) : Colors.grey.shade300;

    return WorkflowTile(
      title: title,
      statusLabel: subtitle,
      statusColor: stale ? const Color(0xFF854F0B) : null,
      // 解析缓存的 id 才是历史记录里记的那个 id
      footnote: cached == null ? l.wfNeverRun : _lastRunText(ref, cached.id, l),
      footnoteColor: stale ? const Color(0xFF854F0B) : null,
      borderColor: borderColor,
      fillColor: stale ? const Color(0xFFFAEEDA) : null,
      showBorder: cached != null,
      menu: PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert, color: Colors.grey),
        tooltip: AppLocalizations.of(context).menuMore,
        onSelected: (v) =>
            _onUiMenuSelected(context, ref, filename, cached?.id, v),
        itemBuilder: (_) => cached == null
            ? [
                PopupMenuItem(
                  value: 'parse',
                  child: Text(AppLocalizations.of(context).uiMenuParse),
                ),
              ]
            : [
                PopupMenuItem(
                  value: 'parse',
                  child: Text(AppLocalizations.of(context).uiMenuReparse),
                ),
                PopupMenuItem(
                  value: 'clear',
                  child: Text(AppLocalizations.of(context).uiMenuClearParse),
                ),
              ],
      ),
      onTap: () => _onUiTap(context, ref, filename, cached?.id),
    );
  }

  Future<void> _onUiTap(
    BuildContext context,
    WidgetRef ref,
    String filename,
    String? cachedId,
  ) async {
    if (cachedId != null) {
      await _openParsed(context, ref, cachedId);
      return;
    }
    await _parseUiWorkflow(context, ref, filename);
  }

  Future<void> _onUiMenuSelected(
    BuildContext context,
    WidgetRef ref,
    String filename,
    String? cachedId,
    String value,
  ) async {
    switch (value) {
      case 'parse':
        await _parseUiWorkflow(context, ref, filename);
        break;
      case 'clear':
        await _confirmClearParse(context, ref, cachedId);
        break;
    }
  }

  /// 已解析的条目：配置过直接进运行页，否则先进配置面板
  Future<void> _openParsed(
    BuildContext context,
    WidgetRef ref,
    String parsedId,
  ) async {
    final hasConfig = ref
        .read(workflowProvider.notifier)
        .hasMappingConfig(parsedId);
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => hasConfig
            ? RunView(workflowId: parsedId)
            : WorkflowView(workflowId: parsedId),
      ),
    );
  }

  /// 解析单条 UI 工作流：拉原始 JSON → 交前端转换 → 写解析缓存
  Future<void> _parseUiWorkflow(
    BuildContext context,
    WidgetRef ref,
    String filename,
  ) async {
    final text = await ref
        .read(workflowProvider.notifier)
        .fetchWorkflowRawText(filename);
    if (text == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).homeFetchFailed)),
        );
      }
      return;
    }

    Map<String, dynamic> uiJson;
    try {
      uiJson = jsonDecode(text) as Map<String, dynamic>;
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).homeInvalidJson)),
        );
      }
      return;
    }

    if (!context.mounted) return;
    final result = await startWorkflowParse(
      context,
      displayName: uiWorkflowTitle(filename),
      uiWorkflow: uiJson,
    );
    if (result == null) return; // 用户中途返回

    if (!result.ok) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result.error ?? AppLocalizations.of(context).homeParseFailed,
            ),
          ),
        );
      }
      return;
    }

    final serverId = ref.read(connectionProvider).activeServerId;
    if (serverId == null) return;

    final id = ref
        .read(parsedWorkflowProvider.notifier)
        .upsert(
          serverId: serverId,
          filename: filename,
          name: uiWorkflowTitle(filename),
          sourceHash: WorkflowApiConverter.sourceHashOf(text),
          workflowJson: result.workflow ?? const {},
        );

    await ref.read(workflowProvider.notifier).refreshUiStatuses([filename]);
    if (context.mounted) await _openParsed(context, ref, id);
  }

  /// 清除解析缓存：语义是「回到未解析」，不是删除——随时可以再解析一次
  Future<void> _confirmClearParse(
    BuildContext context,
    WidgetRef ref,
    String? cachedId,
  ) async {
    if (cachedId == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(ctx).uiMenuClearParse),
        content: Text(AppLocalizations.of(ctx).clearParseBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(AppLocalizations.of(ctx).cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(AppLocalizations.of(ctx).clear),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      ref.read(parsedWorkflowProvider.notifier).remove(cachedId);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).clearParseDone)),
        );
      }
    }
  }

  Widget _buildDisconnected(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.cloud_off, size: 48, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Text(
            AppLocalizations.of(context).homeDisconnectedTitle,
            style: const TextStyle(color: Colors.black54, fontSize: 16),
          ),
          const SizedBox(height: 4),
          Text(
            AppLocalizations.of(context).homeDisconnectedBody,
            style: const TextStyle(color: Colors.grey, fontSize: 12),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ServerConfigView()),
            ),
            label: Text(AppLocalizations.of(context).homeGoToConfig),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inbox_outlined, size: 48, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Text(
            AppLocalizations.of(context).homeEmptyTitle,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.black54, fontSize: 16),
          ),
          const SizedBox(height: 4),
          Text(
            AppLocalizations.of(context).homeEmptyBody,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.grey, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildWorkflowCard(
    BuildContext context,
    WidgetRef ref,
    String filename,
    WorkflowState state,
  ) {
    final title = workflowDisplayName(
      filename,
      localLabel: AppLocalizations.of(context).workflowLocalImport,
    );
    final status = state.statusOf(filename);
    final exposedCount =
        ref
            .read(workflowProvider.notifier)
            .getMappingConfig(filename)
            ?.where((n) => n.exposed)
            .length ??
        0;

    final l = AppLocalizations.of(context);
    final bool stale = status == WorkflowMappingStatus.stale;
    final String subtitle;
    if (status == WorkflowMappingStatus.unknown) {
      subtitle = state.isChecking ? l.statusChecking : l.wfStatusUnconfigured;
    } else if (status == WorkflowMappingStatus.unconfigured) {
      subtitle = l.wfStatusUnconfigured;
    } else if (stale) {
      subtitle = l.wfStatusStale;
    } else {
      subtitle = l.wfStatusConfigured(exposedCount);
    }

    final borderColor = stale ? const Color(0xFF854F0B) : Colors.grey.shade300;
    final fillColor = stale ? const Color(0xFFFAEEDA) : null;

    return WorkflowTile(
      title: title,
      statusLabel: subtitle,
      statusColor: stale ? const Color(0xFF854F0B) : null,
      footnote: _lastRunText(ref, filename, l),
      footnoteColor: stale ? const Color(0xFF854F0B) : null,
      borderColor: borderColor,
      fillColor: fillColor,
      menu: _buildMenu(context, ref, filename),
      onTap: () => _open(context, ref, filename),
    );
  }

  /// 第二行：该工作流上次什么时候跑过。
  ///
  /// ⚠️ 这里刻意用 `read` 而不是 `watch` 去拿任务列表：WebSocket 每秒推
  /// 好几次进度，直接监听会让整个工作流列表跟着重建（画廊页踩过这个坑）。
  /// 真正触发重建的是页面顶部那条 `select` —— 只在任务条数变化时刷新。
  String _lastRunText(WidgetRef ref, String workflowId, AppLocalizations l) {
    final lastRun = lastRunTimeOf(
      ref.read(taskManagerProvider).history,
      workflowId,
    );
    if (lastRun == null) return l.wfNeverRun;
    return l.wfLastRun(formatSnapshotStamp(lastRun));
  }

  Widget _buildMenu(BuildContext context, WidgetRef ref, String filename) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, color: Colors.grey),
      tooltip: AppLocalizations.of(context).menuMore,
      onSelected: (value) => _onMenuSelected(context, ref, filename, value),
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'save',
          child: Text(AppLocalizations.of(context).wfMenuSaveLocal),
        ),
        PopupMenuItem(
          value: 'config',
          child: Text(AppLocalizations.of(context).wfMenuReconfig),
        ),
        PopupMenuItem(
          value: 'refresh',
          child: Text(AppLocalizations.of(context).wfMenuRefresh),
        ),
      ],
    );
  }

  Future<void> _onMenuSelected(
    BuildContext context,
    WidgetRef ref,
    String filename,
    String value,
  ) async {
    switch (value) {
      case 'save':
        await _saveToLocal(context, ref, filename);
        break;
      case 'config':
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => WorkflowView(workflowId: filename)),
        );
        // 配置可能刚被保存，回来后重新判定该条目状态
        if (context.mounted) {
          await ref.read(workflowProvider.notifier).refreshStatuses([filename]);
        }
        break;
      case 'refresh':
        await ref.read(workflowProvider.notifier).refreshStatuses([filename]);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(AppLocalizations.of(context).homeRechecked)),
          );
        }
        break;
    }
  }

  /// 「存入本地库」：把可再生的服务器工作流固化成一份不可再生的本地资产
  Future<void> _saveToLocal(
    BuildContext context,
    WidgetRef ref,
    String filename,
  ) async {
    final data = await ref
        .read(workflowProvider.notifier)
        .fetchWorkflowContentOnly(filename);
    if (data == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).homeFetchContentFailed),
          ),
        );
      }
      return;
    }

    if (!context.mounted) return;

    final name = await showDialog<String>(
      context: context,
      builder: (_) => _SaveToLocalDialog(
        // 默认名直接用文件名推导（远程工作流永远有文件名），
        // 不写入「本地导入」这类翻译文案，免得存进本地库后切语言残留
        initialName:
            workflowNameForStorage(const <WorkflowEntry>[], filename) ??
            filename,
      ),
    );
    if (name == null || name.trim().isEmpty) return;

    ref
        .read(localWorkflowProvider.notifier)
        .save(
          name: name.trim(),
          workflowJson: data,
          sourceKind: LocalWorkflowSource.savedFromRemote,
          originName: filename,
        );

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).homeSavedToLocal)),
      );
    }
  }

  /// 已配置且内容没变 → 直接进运行页；未配置或内容已变 → 先进配置面板
  Future<void> _open(
    BuildContext context,
    WidgetRef ref,
    String filename,
  ) async {
    final state = ref.read(workflowProvider);
    final hasConfig = ref
        .read(workflowProvider.notifier)
        .hasMappingConfig(filename);
    final stale = state.statusOf(filename) == WorkflowMappingStatus.stale;

    final Widget page = (hasConfig && !stale)
        ? RunView(workflowId: filename)
        : WorkflowView(workflowId: filename);

    await Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    if (context.mounted) {
      // 配置可能刚被保存，回来后重新判定该条目状态
      await ref.read(workflowProvider.notifier).refreshStatuses([filename]);
    }
  }
}

/// 存入本地库时的命名对话框。
/// 控制器挂在这个 dialog 自己的 State 上，随 dialog 销毁释放。
class _SaveToLocalDialog extends StatefulWidget {
  final String initialName;
  const _SaveToLocalDialog({required this.initialName});

  @override
  State<_SaveToLocalDialog> createState() => _SaveToLocalDialogState();
}

class _SaveToLocalDialogState extends State<_SaveToLocalDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(AppLocalizations.of(context).wfMenuSaveLocal),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(
          labelText: AppLocalizations.of(context).nameLabel,
          border: const OutlineInputBorder(),
        ),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(AppLocalizations.of(context).cancel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: Text(AppLocalizations.of(context).save),
        ),
      ],
    );
  }
}
