import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:comfyui_mobilepocket/l10n/app_localizations.dart';

import '../../models/local_workflow.dart';
import '../../models/parsed_workflow.dart';
import '../../providers/connection_provider.dart';
import '../../providers/local_workflow_provider.dart';
import '../../providers/parsed_workflow_provider.dart';
import '../../utils.dart';
import 'server_config_view.dart' show serverDisplayName;

import '../../theme.dart';

/// 工作流存储：汇总所有保存在本机的工作流，显示占用并集中提供清理入口。
///
/// 两类来源用标签区分，因为**清除语义不同**：
/// 本地资产删除后不可恢复，解析缓存清除后还能从服务器再解析一次。
/// 所以后者不叫「删除」，也不允许 destructive 的默认按钮配色。
class WorkflowStorageView extends ConsumerWidget {
  const WorkflowStorageView({super.key});

  static String _formatTime(int millis) {
    if (millis <= 0) return '-';
    final t = DateTime.fromMillisecondsSinceEpoch(millis);
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
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

  Future<void> _confirmClearCache(
    BuildContext context,
    WidgetRef ref,
    ParsedWorkflow workflow,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(ctx).uiMenuClearParse),
        content: Text(
          AppLocalizations.of(ctx).storageClearCacheBody(workflow.name),
        ),
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
      ref.read(parsedWorkflowProvider.notifier).remove(workflow.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).clearParseDone)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final local = ref.watch(localWorkflowProvider);
    final parsed = ref.watch(parsedWorkflowProvider);
    if (local.isEmpty && parsed.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: Text(
            AppLocalizations.of(context).storageTitle,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          centerTitle: false,
        ),
        body: Center(
          child: Text(
            AppLocalizations.of(context).storageEmpty,
            style: TextStyle(color: context.textSecondary),
          ),
        ),
      );
    }

    final localBytes = ref.read(localWorkflowProvider.notifier).totalBytes;
    final parsedBytes = ref.read(parsedWorkflowProvider.notifier).totalBytes;
    final total = local.length + parsed.length;
    final servers = ref.read(connectionProvider).servers;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          AppLocalizations.of(context).storageTitle,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: false,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
            child: Text(
              AppLocalizations.of(context)
                  .storageSummary(total, formatBytes(localBytes + parsedBytes)),
              style: TextStyle(fontSize: 13, color: context.textSecondary),
            ),
          ),
          if (local.isNotEmpty) ...[
            _buildGroupTitle(
              context,
              AppLocalizations.of(context).storageGroupLocal(local.length),
            ),
            ...local.map((w) => _buildLocalTile(context, ref, w)),
            const SizedBox(height: 16),
          ],
          if (parsed.isNotEmpty) ...[
            _buildGroupTitle(
              context,
              AppLocalizations.of(context).storageGroupParsed(parsed.length),
            ),
            ...parsed.map((w) => _buildParsedTile(context, ref, w, servers)),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                AppLocalizations.of(context).storageParsedNote,
                style: TextStyle(fontSize: 12, color: context.textSecondary),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildGroupTitle(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: Text(
        text,
        style: TextStyle(fontSize: 12, color: context.textSecondary),
      ),
    );
  }

  Widget _buildLocalTile(
    BuildContext context,
    WidgetRef ref,
    LocalWorkflow workflow,
  ) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: context.borderColor),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        title: Text(
          workflow.name,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${workflow.sourceKind.label(AppLocalizations.of(context))} · ${_formatTime(workflow.createdAt)}'
                ' · ${formatBytes(workflow.sizeBytes)}',
              ),
              if (workflow.originName != null &&
                  workflow.originName!.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  AppLocalizations.of(context)
                      .storageOrigin(workflow.originName!),
                  style: TextStyle(fontSize: 12, color: context.textSecondary),
                ),
              ],
            ],
          ),
        ),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline),
          tooltip: AppLocalizations.of(context).delete,
          onPressed: () => _confirmDelete(context, ref, workflow),
        ),
      ),
    );
  }

  Widget _buildParsedTile(
    BuildContext context,
    WidgetRef ref,
    ParsedWorkflow workflow,
    List<ServerConfig> servers,
  ) {
    final l = AppLocalizations.of(context);
    final serverName = servers
        .where((s) => s.id == workflow.serverId)
        // 名字为空（用户没填）时按当前语言补默认名
        .map((s) => serverDisplayName(l, s.name))
        .firstWhere((n) => n.isNotEmpty, orElse: () => '');

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: context.borderColor),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        title: Text(
          workflow.name,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AppLocalizations.of(context).storageParsedAt(
                  _formatTime(workflow.parsedAt),
                  formatBytes(workflow.sizeBytes),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                AppLocalizations.of(context).storageOrigin(
                  serverName.isEmpty
                      ? AppLocalizations.of(context).unknownConnection
                      : '$serverName / ${workflow.filename}',
                ),
                style: TextStyle(fontSize: 12, color: context.textSecondary),
              ),
            ],
          ),
        ),
        // 用「清除」而不是删除图标：这条数据可再生，语义不同不宜混用
        trailing: IconButton(
          icon: const Icon(Icons.restart_alt),
          tooltip: AppLocalizations.of(context).uiMenuClearParse,
          onPressed: () => _confirmClearCache(context, ref, workflow),
        ),
      ),
    );
  }
}
