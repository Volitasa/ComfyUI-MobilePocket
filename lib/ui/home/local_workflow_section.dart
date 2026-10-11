import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';

import '../../models/local_workflow.dart';
import '../../providers/local_workflow_provider.dart';
import '../../providers/workflow_provider.dart';
import '../../utils.dart';
import '../builder/run_view.dart';
import '../builder/workflow_view.dart';

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

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          workflows.isEmpty
              ? '本地库为空'
              : '本地库 ${workflows.length} 项 · ${formatBytes(totalBytes)}',
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 14),
        OutlinedButton.icon(
          onPressed: () => _importLocalJson(context, ref),
          icon: const Icon(Icons.upload_file),
          label: const Text('导入工作流 JSON'),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            side: const BorderSide(color: Colors.grey),
            foregroundColor: Colors.black87,
          ),
        ),
        const SizedBox(height: 12),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            '提示：这里导入的是 ComfyUI 的 API 格式 JSON（_api.json），'
            '即以节点 ID 为键、含 class_type 与 inputs 的结构；'
            '普通 UI 界面保存的 workflow JSON 不适用。',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ),
        const SizedBox(height: 20),
        if (workflows.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: Column(
              children: [
                Icon(Icons.folder_off_outlined, size: 48, color: Colors.grey.shade400),
                const SizedBox(height: 12),
                const Text(
                  '还没有本地工作流',
                  style: TextStyle(color: Colors.black54, fontSize: 16),
                ),
                const SizedBox(height: 4),
                const Text(
                  '导入或另存的工作流会保存在这里',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
          )
        else
          ...workflows.map((w) => _buildCard(context, ref, w)),
        if (workflows.isNotEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 12, left: 4, right: 4),
            child: Text(
              '来自你自己的文件，与服务器无关，可重命名或删除。删除后无法恢复。',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
      ],
    );
  }

  Widget _buildCard(BuildContext context, WidgetRef ref, LocalWorkflow workflow) {
    final exposedCount = ref
            .read(workflowProvider.notifier)
            .getMappingConfig(workflow.id)
            ?.where((n) => n.exposed)
            .length ??
        0;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: InkWell(
        onTap: () => _open(context, ref, workflow),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      workflow.name,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${workflow.sourceKind.label} · ${_formatDate(workflow.createdAt)}'
                      ' · ${formatBytes(workflow.sizeBytes)}'
                      ' · ${exposedCount == 0 ? '未配置' : '$exposedCount 项参数'}',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, color: Colors.grey),
                tooltip: '更多操作',
                onSelected: (v) => _onMenuSelected(context, ref, workflow, v),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'rename', child: Text('重命名')),
                  PopupMenuItem(value: 'config', child: Text('重新配置节点')),
                  PopupMenuItem(value: 'delete', child: Text('删除')),
                ],
              ),
            ],
          ),
        ),
      ),
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

  /// 已配置过直接进运行页，否则先进配置面板
  Future<void> _open(
    BuildContext context,
    WidgetRef ref,
    LocalWorkflow workflow,
  ) async {
    final hasConfig =
        ref.read(workflowProvider.notifier).hasMappingConfig(workflow.id);
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

      ref.read(localWorkflowProvider.notifier).save(
            name: fileName.replaceAll(RegExp(r'\.json$'), ''),
            workflowJson: data,
            sourceKind: LocalWorkflowSource.importFile,
            originName: result.files.single.name,
            id: localId,
          );

      if (context.mounted) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => WorkflowView(workflowId: localId),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('JSON 文件解析失败')));
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
      title: const Text('重命名'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(
          labelText: '名称',
          border: OutlineInputBorder(),
        ),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: const Text('保存'),
        ),
      ],
    );
  }
}

