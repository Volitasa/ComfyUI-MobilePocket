import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/local_workflow.dart';
import '../../models/parsed_workflow.dart';
import '../../providers/connection_provider.dart';
import '../../providers/local_workflow_provider.dart';
import '../../providers/parsed_workflow_provider.dart';
import '../../utils.dart';

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

  Future<void> _confirmClearCache(
    BuildContext context,
    WidgetRef ref,
    ParsedWorkflow workflow,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清除解析缓存'),
        content: Text(
          '确定清除「${workflow.name}」的解析结果吗？\n\n'
          '清除后回到未解析状态，在服务器列表里可以重新解析。'
          '已保存的节点配置不受影响。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清除'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      ref.read(parsedWorkflowProvider.notifier).remove(workflow.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('已清除解析结果')));
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
          title: const Text('工作流存储', style: TextStyle(fontWeight: FontWeight.bold)),
          centerTitle: false,
        ),
        body: const Center(
          child: Text('本机还没有保存任何工作流',
              style: TextStyle(color: Colors.grey)),
        ),
      );
    }

    final localBytes = ref.read(localWorkflowProvider.notifier).totalBytes;
    final parsedBytes = ref.read(parsedWorkflowProvider.notifier).totalBytes;
    final total = local.length + parsed.length;
    final servers = ref.read(connectionProvider).servers;

    return Scaffold(
      appBar: AppBar(
        title: const Text('工作流存储', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: false,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
            child: Text(
              '共 $total 项 · 合计 ${formatBytes(localBytes + parsedBytes)}',
              style: const TextStyle(fontSize: 13, color: Colors.black54),
            ),
          ),
          if (local.isNotEmpty) ...[
            _buildGroupTitle('本地资产 · ${local.length} 项'),
            ...local.map((w) => _buildLocalTile(context, ref, w)),
            const SizedBox(height: 16),
          ],
          if (parsed.isNotEmpty) ...[
            _buildGroupTitle('解析缓存 · ${parsed.length} 项'),
            ...parsed.map((w) => _buildParsedTile(context, ref, w, servers)),
            const SizedBox(height: 8),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                '解析缓存由服务器上的 UI 工作流转换而来，'
                '清除后回到未解析状态，可随时重新解析。',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildGroupTitle(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: Text(text, style: const TextStyle(fontSize: 12, color: Colors.grey)),
    );
  }

  Widget _buildLocalTile(BuildContext context, WidgetRef ref, LocalWorkflow workflow) {
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

  Widget _buildParsedTile(
    BuildContext context,
    WidgetRef ref,
    ParsedWorkflow workflow,
    List<ServerConfig> servers,
  ) {
    final serverName = servers
        .where((s) => s.id == workflow.serverId)
        .map((s) => s.name)
        .firstWhere((n) => n.isNotEmpty, orElse: () => '');

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
                'UI 工作流解析 · ${_formatTime(workflow.parsedAt)}'
                ' · ${formatBytes(workflow.sizeBytes)}',
              ),
              const SizedBox(height: 2),
              Text(
                '来源 ${serverName.isEmpty ? '未知连接' : '$serverName / ${workflow.filename}'}',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ),
        // 用「清除」而不是删除图标：这条数据可再生，语义不同不宜混用
        trailing: IconButton(
          icon: const Icon(Icons.restart_alt),
          tooltip: '清除解析缓存',
          onPressed: () => _confirmClearCache(context, ref, workflow),
        ),
      ),
    );
  }
}
