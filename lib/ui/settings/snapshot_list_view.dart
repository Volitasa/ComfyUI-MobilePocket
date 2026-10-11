import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
        title: const Text('删除快照'),
        content: Text(
          '确定删除「${snapshot.displayName}」吗？\n\n'
          '删除后，引用它的 $refCount 条生成记录将无法再次运行。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      ref.read(snapshotProvider.notifier).remove(snapshot.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('快照已删除')));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshots = ref.watch(snapshotProvider);
    final history = ref.watch(taskManagerProvider).history;
    final servers = ref.watch(connectionProvider).servers;

    int refCountOf(String id) =>
        history.where((t) => t.snapshotId == id).length;

    String serverNameOf(String? id) {
      if (id == null) return '未记录';
      for (final s in servers) {
        if (s.id == id) return s.name;
      }
      return '未记录';
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('工作流快照', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: false,
      ),
      body: snapshots.isEmpty
          ? const Center(
              child: Text('暂无工作流快照', style: TextStyle(color: Colors.grey)),
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
                      s.displayName,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '固化时间 ${_formatTime(s.createdAt)} · ${_formatSize(s.sizeBytes)}',
                          ),
                          const SizedBox(height: 2),
                          Text('来源服务器 ${serverNameOf(s.serverId)}'),
                          const SizedBox(height: 2),
                          Text(
                            refCount > 0
                                ? '被 $refCount 条生成记录引用'
                                : '未被任何生成记录引用',
                            style: TextStyle(
                              color: refCount > 0 ? Colors.black54 : Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: '删除快照',
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
