import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:comfyui_mobilepocket/l10n/app_localizations.dart';
import 'package:file_picker/file_picker.dart';

import '../../models/local_workflow.dart';
import '../../providers/local_workflow_provider.dart';
import '../../providers/task_manager.dart';
import '../../providers/workflow_provider.dart';
import '../../utils.dart';
import '../../utils/workflow_last_run.dart';
import '../../theme.dart';
import '../builder/run_view.dart';
import '../builder/workflow_view.dart';
import '../widgets/workflow_tile.dart';

/// 本地段：保存在本机的工作流资产。
///
/// 与服务器无关、删了就没有了，所以提供重命名与删除——
/// 这是唯一拥有完整增删改能力的一类工作流。
class LocalWorkflowSection extends ConsumerWidget {
  const LocalWorkflowSection({super.key});

  static String _formatDate(int millis) {
    if (millis <= 0) return '-';
    final t = DateTime.fromMillisecondsSinceEpoch(millis);
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(t.month)}-${two(t.day)}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workflows = ref.watch(localWorkflowProvider);
    final totalBytes = ref.read(localWorkflowProvider.notifier).totalBytes;
    // 只为「新任务产生/记录被删」时刷新列表上的「上次运行时间」。
    // 刻意不监听任务列表本身：WebSocket 每秒推好几次进度，
    // 直接监听会把整个工作流列表跟着重建（画廊页踩过这个坑）。
    ref.watch(taskManagerProvider.select((s) => s.history.length));

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          workflows.isEmpty
              ? AppLocalizations.of(context).localEmpty
              : AppLocalizations.of(context)
                    .localSummary(workflows.length, formatBytes(totalBytes)),
          style: TextStyle(fontSize: 12, color: context.textSecondary),
        ),
        const SizedBox(height: 14),
        OutlinedButton.icon(
          onPressed: () => _importLocalJson(context, ref),
          icon: const Icon(Icons.upload_file),
          label: Text(AppLocalizations.of(context).localImportButton),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            side: BorderSide(color: context.borderColor),
            foregroundColor: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            AppLocalizations.of(context).localImportNote,
            style: TextStyle(fontSize: 12, color: context.textSecondary),
          ),
        ),
        const SizedBox(height: 20),
        if (workflows.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: Column(
              children: [
                Icon(
                  Icons.folder_off_outlined,
                  size: 48,
                  color: Colors.grey.shade400,
                ),
                const SizedBox(height: 12),
                Text(
                  AppLocalizations.of(context).localNoWorkflows,
                  style: const TextStyle(color: Colors.black54, fontSize: 16),
                ),
                const SizedBox(height: 4),
                Text(
                  AppLocalizations.of(context).localNoWorkflowsHint,
                  style: TextStyle(color: context.textSecondary, fontSize: 12),
                ),
              ],
            ),
          )
        else
          ...workflows.map((w) => _buildCard(context, ref, w)),
        if (workflows.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12, left: 4, right: 4),
            child: Text(
              AppLocalizations.of(context).localFooterNote,
              style: TextStyle(fontSize: 12, color: context.textSecondary),
            ),
          ),
      ],
    );
  }

  Widget _buildCard(
    BuildContext context,
    WidgetRef ref,
    LocalWorkflow workflow,
  ) {
    final exposedCount =
        ref
            .read(workflowProvider.notifier)
            .getMappingConfig(workflow.id)
            ?.where((n) => n.exposed)
            .length ??
        0;

    final l = AppLocalizations.of(context);
    final lastRun = lastRunTimeOf(
      ref.read(taskManagerProvider).history,
      workflow.id,
    );
    // 上次运行放最前：这一行放不下时会截掉尾部，
    // 截掉大小无所谓，截掉刚加的上次运行就没意义了
    final meta =
        '${lastRun == null ? l.wfNeverRun : l.wfLastRun(formatSnapshotStamp(lastRun))}'
        ' · ${workflow.sourceKind.label(l)}'
        ' · ${_formatDate(workflow.createdAt)}'
        ' · ${formatBytes(workflow.sizeBytes)}';

    return WorkflowTile(
      title: workflow.name,
      statusLabel: exposedCount == 0
          ? l.wfStatusUnconfigured
          : l.configParamCount(exposedCount),
      statusColor: exposedCount == 0 ? null : AppColors.primary,
      footnote: meta,
      menu: PopupMenuButton<String>(
        icon: Icon(Icons.more_vert, color: context.textSecondary),
        tooltip: l.menuMore,
        onSelected: (v) => _onMenuSelected(context, ref, workflow, v),
        itemBuilder: (_) => [
          PopupMenuItem(value: 'rename', child: Text(l.menuRename)),
          PopupMenuItem(value: 'config', child: Text(l.wfMenuReconfig)),
          PopupMenuItem(value: 'delete', child: Text(l.delete)),
        ],
      ),
      onTap: () => _open(context, ref, workflow),
    );
  }

  Future<void> _onMenuSelected(
    BuildContext context,
    WidgetRef ref,
    LocalWorkflow workflow,
    String value,
  ) async {
    switch (value) {
      case 'rename':
        final name = await showDialog<String>(
          context: context,
          builder: (_) => _RenameDialog(initialName: workflow.name),
        );
        if (name == null || name.trim().isEmpty) return;
        ref.read(localWorkflowProvider.notifier).rename(workflow.id, name);
        break;
      case 'config':
        if (context.mounted) await _open(context, ref, workflow);
        break;
      case 'delete':
        await _confirmDelete(context, ref, workflow);
        break;
    }
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    LocalWorkflow workflow,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(ctx).localDeleteTitle),
        content: Text(AppLocalizations.of(ctx).localDeleteBody(workflow.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(AppLocalizations.of(ctx).cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(AppLocalizations.of(ctx).delete),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      ref.read(localWorkflowProvider.notifier).remove(workflow.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).localDeleted)),
        );
      }
    }
  }

  /// 已配置过直接进运行页，否则先进配置面板
  Future<void> _open(
    BuildContext context,
    WidgetRef ref,
    LocalWorkflow workflow,
  ) async {
    final hasConfig = ref
        .read(workflowProvider.notifier)
        .hasMappingConfig(workflow.id);
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => hasConfig
            ? RunView(workflowId: workflow.id)
            : WorkflowView(workflowId: workflow.id),
      ),
    );
  }

  Future<void> _importLocalJson(BuildContext context, WidgetRef ref) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: true,
      );

      if (result == null || result.files.single.bytes == null) return;

      final jsonString = utf8.decode(result.files.single.bytes!);
      final Map<String, dynamic> data = jsonDecode(jsonString);

      // 以内容哈希作为 ID：同一个文件重复导入可命中同一份配置
      final localId = 'local_${stableHash(jsonString).toRadixString(36)}';
      final fileName = result.files.single.name.replaceAll('_api.json', '');

      ref
          .read(localWorkflowProvider.notifier)
          .save(
            name: fileName.replaceAll(RegExp(r'\.json$'), ''),
            workflowJson: data,
            sourceKind: LocalWorkflowSource.importFile,
            originName: result.files.single.name,
            id: localId,
          );

      if (context.mounted) {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => WorkflowView(workflowId: localId)),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).localJsonParseFailed),
          ),
        );
      }
    }
  }
}

/// 重命名对话框。控制器挂在 dialog 自己的 State 上。
class _RenameDialog extends StatefulWidget {
  final String initialName;
  const _RenameDialog({required this.initialName});

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
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
      title: Text(AppLocalizations.of(context).menuRename),
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
