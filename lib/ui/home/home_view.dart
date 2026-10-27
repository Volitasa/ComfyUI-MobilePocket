import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:comfyui_mobilepocket/l10n/app_localizations.dart';

import '../../providers/connection_provider.dart';
import '../../providers/workflow_provider.dart';
import '../../providers/ws_event_provider.dart';
import '../../providers/task_manager.dart';
import '../widgets/connection_status_badge.dart';
import '../settings/server_config_view.dart';
import 'remote_workflow_section.dart';
import 'local_workflow_section.dart';

import '../../theme.dart';

/// 首页分段：0 服务器 / 1 本地
final workflowTabIndexProvider = StateProvider<int>((ref) => 0);

class HomeView extends ConsumerStatefulWidget {
  const HomeView({super.key});

  @override
  ConsumerState<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends ConsumerState<HomeView> {
  @override
  void initState() {
    super.initState();
    // 页面加载时：先静默探测已保存地址自动连接，成功后拉取远端列表，
    // fetchRemoteList 内部会接着比对各工作流内容是否变化
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(connectionProvider.notifier).autoConnect().then((_) {
        if (!mounted) return;
        if (ref.read(connectionProvider).isConnected) {
          ref.read(workflowProvider.notifier).fetchRemoteList();
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final configState = ref.watch(connectionProvider);
    final currentTab = ref.watch(workflowTabIndexProvider);

    // 监听连接状态：连接成功（false→true）时建立 WS 并拉取工作流列表，
    // 断开（true→false）时关闭 WS，统一在此维护连接生命周期
    ref.listen(connectionProvider, (prev, next) {
      // 切换了服务器连接：清空旧服务器的工作流列表与缓存（本地历史/画廊不受影响）
      if (prev?.activeServerId != null &&
          prev?.activeServerId != next.activeServerId) {
        ref.read(workflowProvider.notifier).clearList();
      }

      if (next.isConnected && !(prev?.isConnected ?? false)) {
        ref.read(wsProvider.notifier).connect();
        ref.read(workflowProvider.notifier).fetchRemoteList();
        // 对账未终结任务：崩溃/断线期间错过的终态事件无法经 WS 补收
        ref.read(taskManagerProvider.notifier).reconcilePendingTasks();
      } else if (!next.isConnected && (prev?.isConnected ?? false)) {
        ref.read(wsProvider.notifier).disconnect();
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(
          AppLocalizations.of(context).navWorkflow,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          // 刷新只对服务器段有意义
          if (currentTab == 0 && configState.isConnected)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: AppLocalizations.of(context).homeRefreshTooltip,
              onPressed: () =>
                  ref.read(workflowProvider.notifier).fetchRemoteList(),
            ),
          ConnectionStatusBadge(
            // 直接进服务器连接页，而不是只切到「设置」Tab
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ServerConfigView()),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          _buildTabs(currentTab),
          Expanded(
            child: currentTab == 0
                ? const RemoteWorkflowSection()
                : const LocalWorkflowSection(),
          ),
        ],
      ),
    );
  }

  /// 分段条：位于内容区顶部、用下划线指示器（不用实心色块），
  /// 避免与 AppBar 右上的连接状态徽章争视觉层级
  Widget _buildTabs(int currentTab) {
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          _buildTab(AppLocalizations.of(context).homeTabServer, 0, currentTab),
          _buildTab(AppLocalizations.of(context).homeTabLocal, 1, currentTab),
        ],
      ),
    );
  }

  Widget _buildTab(String label, int index, int currentTab) {
    final selected = currentTab == index;
    return Expanded(
      child: InkWell(
        onTap: () => ref.read(workflowTabIndexProvider.notifier).state = index,
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: selected ? AppColors.primary : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
              color: selected ? Colors.black87 : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
