import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/local_workflow.dart';
import '../../providers/connection_provider.dart';
import '../../providers/local_workflow_provider.dart';
import '../../providers/workflow_provider.dart';
import '../../utils.dart';
import '../builder/run_view.dart';
import '../builder/workflow_view.dart';
import '../settings/server_config_view.dart';

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

    if (!configState.isConnected) return _buildDisconnected(context);
    if (workflowState.isLoading) {
      return const Padding(
        padding: EdgeInsets.all(40),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (workflowState.workflowList.isEmpty) return _buildEmpty();

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        ...workflowState.workflowList.map(
          (file) => _buildWorkflowCard(context, ref, file, workflowState),
        ),
        const SizedBox(height: 12),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            '提示：工作流来自 ComfyUI 的 userdata/workflows 目录下的 _api.json 文件。'
            '这些 API JSON 由 ComfyUI-AutoSaveAPI 插件自动生成'
            '（https://github.com/Volitasa/ComfyUI-AutoSaveAPI.git）。',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ),
      ],
    );
  }

  Widget _buildDisconnected(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.cloud_off, size: 48, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          const Text('尚未连接到服务器',
              style: TextStyle(color: Colors.black54, fontSize: 16)),
          const SizedBox(height: 4),
          const Text('请先配置并启用一个服务器连接',
              style: TextStyle(color: Colors.grey, fontSize: 12)),
          const SizedBox(height: 20),
          FilledButton.icon(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ServerConfigView()),
            ),
            label: const Text('前往配置'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inbox_outlined, size: 48, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          const Text(
            '未找到工作流',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.black54, fontSize: 16),
          ),
          const SizedBox(height: 4),
          const Text(
            '服务器上没有找到 _api.json 后缀的工作流',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey, fontSize: 12),
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
    final title = workflowDisplayName(filename);
    final status = state.statusOf(filename);
    final exposedCount = ref
            .read(workflowProvider.notifier)
            .getMappingConfig(filename)
            ?.where((n) => n.exposed)
            .length ??
        0;

    final bool stale = status == WorkflowMappingStatus.stale;
    final String subtitle;
    if (status == WorkflowMappingStatus.unknown) {
      subtitle = state.isChecking ? '检查中…' : '未配置';
    } else if (status == WorkflowMappingStatus.unconfigured) {
      subtitle = '未配置';
    } else if (stale) {
      subtitle = '内容已更新，需重新确认配置';
    } else {
      subtitle = '$exposedCount 项参数已配置';
    }

    final borderColor = stale ? const Color(0xFF854F0B) : Colors.grey.shade300;
    final fillColor = stale ? const Color(0xFFFAEEDA) : null;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 0,
      color: fillColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: borderColor),
      ),
      child: InkWell(
        onTap: () => _open(context, ref, filename),
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
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: stale ? const Color(0xFF854F0B) : Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
              _buildMenu(context, ref, filename),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMenu(BuildContext context, WidgetRef ref, String filename) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, color: Colors.grey),
      tooltip: '更多操作',
      onSelected: (value) => _onMenuSelected(context, ref, filename, value),
      itemBuilder: (_) => const [
        PopupMenuItem(value: 'save', child: Text('存入本地库')),
        PopupMenuItem(value: 'config', child: Text('重新配置节点')),
        PopupMenuItem(value: 'refresh', child: Text('刷新内容')),
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
          MaterialPageRoute(
            builder: (_) => WorkflowView(workflowId: filename),
          ),
        );
        // 配置可能刚被保存，回来后重新判定该条目状态
        if (context.mounted) {
          await ref.read(workflowProvider.notifier).refreshStatuses([filename]);
        }
        break;
      case 'refresh':
        await ref.read(workflowProvider.notifier).refreshStatuses([filename]);
        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('已重新检查')));
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
    final data =
        await ref.read(workflowProvider.notifier).fetchWorkflowContentOnly(filename);
    if (data == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('拉取工作流内容失败，请检查服务器连接')));
      }
      return;
    }

    if (!context.mounted) return;

    final name = await showDialog<String>(
      context: context,
      builder: (_) => _SaveToLocalDialog(initialName: workflowDisplayName(filename)),
    );
    if (name == null || name.trim().isEmpty) return;

    ref.read(localWorkflowProvider.notifier).save(
          name: name.trim(),
          workflowJson: data,
          sourceKind: LocalWorkflowSource.savedFromRemote,
          originName: filename,
        );

    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已存入本地库')));
    }
  }

  /// 已配置且内容没变 → 直接进运行页；未配置或内容已变 → 先进配置面板
  Future<void> _open(BuildContext context, WidgetRef ref, String filename) async {
    final state = ref.read(workflowProvider);
    final hasConfig = ref.read(workflowProvider.notifier).hasMappingConfig(filename);
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
      title: const Text('存入本地库'),
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
