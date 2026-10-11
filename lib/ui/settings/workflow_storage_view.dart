import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/local_workflow.dart';
import '../../providers/local_workflow_provider.dart';
import '../../utils.dart';

/// 工作流存储：汇总所有保存在本机的工作流，显示占用并集中提供删除入口。
///
/// 这里同时是「本地资产」与（未来的）「解析缓存」的统一管理页，
/// 用标签区分来源，因为两者的删除语义不同：
/// 本地资产删除后不可恢复，解析缓存清除后可重新解析。
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
        title: const Text('删除本地工作流'),
        content: Text(
          '确定删除「${workflow.name}」吗？\n\n'
          '它的节点配置会一并清除，删除后无法恢复。已生成的记录不受影响。',
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
      ref.read(localWorkflowProvider.notifier).remove(workflow.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('已删除')));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workflows = ref.watch(localWorkflowProvider);
    final totalBytes = ref.read(localWorkflowProvider.notifier).totalBytes;

    return Scaffold(
      appBar: AppBar(
        title: const Text('工作流存储', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: false,
      ),
      body: workflows.isEmpty
          ? const Center(
              child: Text('本机还没有保存任何工作流',
                  style: TextStyle(color: Colors.grey)),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
                  child: Text(
                    '共 ${workflows.length} 项 · 合计 ${formatBytes(totalBytes)}',
                    style: const TextStyle(fontSize: 13, color: Colors.black54),
                  ),
                ),
                ...workflows.map(
                  (w) => _buildTile(context, ref, w),
                ),
              ],
            ),
    );
  }

  Widget _buildTile(BuildContext context, WidgetRef ref, LocalWorkflow workflow) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
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
                '${workflow.sourceKind.label} · ${_formatTime(workflow.createdAt)}'
                ' · ${formatBytes(workflow.sizeBytes)}',
              ),
              if (workflow.originName != null &&
                  workflow.originName!.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  '来源 ${workflow.originName}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ],
          ),
        ),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline),
          tooltip: '删除',
          onPressed: () => _confirmDelete(context, ref, workflow),
        ),
      ),
    );
  }
}
