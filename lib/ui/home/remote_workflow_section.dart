import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../models/local_workflow.dart';
import '../../providers/connection_provider.dart';
import '../../providers/locale_provider.dart';
import '../../providers/local_workflow_provider.dart';
import '../../providers/parsed_workflow_provider.dart';
import '../../providers/workflow_provider.dart';
import '../../services/workflow_api_converter.dart';
import '../../utils.dart';
import '../builder/run_view.dart';
import '../builder/workflow_parse_view.dart';
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
    if (workflowState.isEmpty) return _buildEmpty();

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // 分组按格式而非状态：条目解析后不会在两组之间跳来跳去
        if (workflowState.workflowList.isNotEmpty) ...[
          _buildGroupTitle('API 工作流 · 可直接运行'),
          ...workflowState.workflowList.map(
            (file) => _buildWorkflowCard(context, ref, file, workflowState),
          ),
          const SizedBox(height: 18),
        ],
        if (workflowState.uiWorkflowList.isNotEmpty) ...[
          _buildGroupTitle('UI 工作流 · 需解析'),
          ...workflowState.uiWorkflowList.map(
            (file) => _buildUiWorkflowCard(context, ref, file, workflowState),
          ),
          const SizedBox(height: 12),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              'UI 格式是 ComfyUI 界面保存的原始结构，需转换为 API 结构后才能运行。',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
          const SizedBox(height: 18),
        ],
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            '提示：工作流来自 ComfyUI 的 userdata/workflows 目录。'
            '其中 API JSON 由 ComfyUI-AutoSaveAPI 插件自动生成'
            '（https://github.com/Volitasa/ComfyUI-AutoSaveAPI.git）。',
            style: TextStyle(fontSize: 12, color: Colors.grey),
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
    final cached =
        ref.read(parsedWorkflowProvider.notifier).byServerFile(serverId, filename);
    final status = state.uiStatusOf(filename);
    final stale = status == UiWorkflowStatus.stale;

    final exposedCount = cached == null
        ? 0
        : ref.read(workflowProvider.notifier).getMappingConfig(cached.id)
                ?.where((n) => n.exposed)
                .length ??
            0;

    final String subtitle;
    if (cached == null) {
      subtitle = '尚未解析 · 点击解析';
    } else if (stale) {
      subtitle = '服务器有更新，可重新解析';
    } else if (status == UiWorkflowStatus.parsed) {
      subtitle = '已解析${exposedCount == 0 ? '' : ' · $exposedCount 项参数'}';
    } else {
      subtitle = state.isChecking ? '检查中…' : '已解析';
    }

    // 未解析用虚线：与「能用但还没配」的实线卡片区分开
    final borderColor = stale ? const Color(0xFF854F0B) : Colors.grey.shade300;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      color: stale ? const Color(0xFFFAEEDA) : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: borderColor,
          style: cached == null ? BorderStyle.none : BorderStyle.solid,
        ),
      ),
      child: InkWell(
        onTap: () => _onUiTap(context, ref, filename, cached?.id),
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
                        fontSize: 16,
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
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, color: Colors.grey),
                tooltip: '更多操作',
                onSelected: (v) =>
                    _onUiMenuSelected(context, ref, filename, cached?.id, v),
                itemBuilder: (_) => cached == null
                    ? const [PopupMenuItem(value: 'parse', child: Text('解析'))]
                    : const [
                        PopupMenuItem(value: 'parse', child: Text('重新解析')),
                        PopupMenuItem(value: 'clear', child: Text('清除解析缓存')),
                      ],
              ),
            ],
          ),
        ),
      ),
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
    final hasConfig =
        ref.read(workflowProvider.notifier).hasMappingConfig(parsedId);
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
    final text =
        await ref.read(workflowProvider.notifier).fetchWorkflowRawText(filename);
    if (text == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('拉取工作流失败，请检查服务器连接')));
      }
      return;
    }

    Map<String, dynamic> uiJson;
    try {
      uiJson = jsonDecode(text) as Map<String, dynamic>;
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('工作流文件不是有效的 JSON')));
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
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(result.error ?? '解析失败')));
      }
      return;
    }

    final serverId = ref.read(connectionProvider).activeServerId;
    if (serverId == null) return;

    final id = ref.read(parsedWorkflowProvider.notifier).upsert(
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
        title: const Text('清除解析缓存'),
        content: const Text(
          '清除后会回到未解析状态，可随时从服务器重新解析。\n\n'
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
      ref.read(parsedWorkflowProvider.notifier).remove(cachedId);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('已清除解析结果')));
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
            '服务器上没有找到工作流 JSON 文件',
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
    final title = workflowDisplayName(
      filename,
      localLabel: AppLocalizations.of(context).workflowLocalImport,
    );
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
      builder: (_) => _SaveToLocalDialog(
        initialName: workflowDisplayName(
          filename,
          localLabel: l10nFor(ref.read(localeProvider)).workflowLocalImport,
        ),
      ),
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
