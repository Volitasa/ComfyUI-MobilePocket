import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:comfyui_mobilepocket/l10n/app_localizations.dart';

import '../../models/workflow_snapshot.dart';
import '../../providers/connection_provider.dart';
import '../../providers/snapshot_provider.dart';
import '../../providers/task_manager.dart';

/// 工作流快照管理：查看所有快照、显示被多少条生成记录引用、手动删除。
///
/// 删除生成记录**不会**连带删除快照（快照可能被其他记录引用），
/// 所以清理只在这里由用户主动进行。
class SnapshotListView extends ConsumerWidget {
  const SnapshotListView({super.key});

  static String _formatTime(int millis) {
    if (millis <= 0) return '-';
    final t = DateTime.fromMillisecondsSinceEpoch(millis);
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
  }

  static String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    WorkflowSnapshot snapshot,
    int refCount,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(ctx).snapshotDeleteTitle),
        content: Text(
          AppLocalizations.of(ctx).snapshotDeleteBody(
            snapshot.displayName(AppLocalizations.of(ctx)),
            refCount,
          ),
        ),
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
      ref.read(snapshotProvider.notifier).remove(snapshot.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).snapshotDeleted)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final snapshots = ref.watch(snapshotProvider);
    final history = ref.watch(taskManagerProvider).history;
    final servers = ref.watch(connectionProvider).servers;

    int refCountOf(String id) =>
        history.where((t) => t.snapshotId == id).length;

    String serverNameOf(String? id) {
      if (id == null) return AppLocalizations.of(context).snapshotNotRecorded;
      for (final s in servers) {
        if (s.id == id) return s.name;
      }
      return AppLocalizations.of(context).snapshotNotRecorded;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          AppLocalizations.of(context).snapshotTitle,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: false,
      ),
      body: snapshots.isEmpty
          ? Center(
              child: Text(
                AppLocalizations.of(context).snapshotEmpty,
                style: const TextStyle(color: Colors.grey),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: snapshots.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final s = snapshots[index];
                final refCount = refCountOf(s.id);
                return Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: Colors.grey.shade200),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    title: Text(
                      s.displayName(l),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            AppLocalizations.of(context).snapshotFrozenAt(
                              _formatTime(s.createdAt),
                              _formatSize(s.sizeBytes),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            AppLocalizations.of(context)
                                .snapshotSourceServer(serverNameOf(s.serverId)),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            refCount > 0
                                ? AppLocalizations.of(context)
                                      .snapshotRefCount(refCount)
                                : AppLocalizations.of(context).snapshotNoRef,
                            style: TextStyle(
                              color: refCount > 0
                                  ? Colors.black54
                                  : Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: AppLocalizations.of(context).snapshotDeleteTitle,
                      onPressed: () =>
                          _confirmDelete(context, ref, s, refCount),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
