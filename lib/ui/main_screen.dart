import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:comfyui_mobilepocket/l10n/app_localizations.dart';

import '../providers/connection_provider.dart';
import '../providers/haptics_provider.dart';
import '../providers/task_manager.dart';
import '../providers/ws_event_provider.dart';
import 'home/home_view.dart';
import 'gallery/history_view.dart';
import 'gallery/gallery_view.dart';
import 'settings/settings_view.dart';

// 全局暴露的 Tab 索引状态，默认 0 (工作流)
final mainTabIndexProvider = StateProvider<int>((ref) => 0);

// Tab 索引语义常量，避免各处硬编码魔法数字
class MainTabs {
  MainTabs._();
  static const int workflow = 0;
  static const int history = 1;
  static const int gallery = 2;
  static const int setup = 3;
}

class MainScreen extends ConsumerStatefulWidget {
  const MainScreen({super.key});

  @override
  ConsumerState<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends ConsumerState<MainScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// 回到前台时补齐后台期间漏掉的进度。
  ///
  /// 切到别的 App 期间，WebSocket 可能被系统静默掐断（半开连接，
  /// 不触发断线回调，所以自动重连不会启动），回来后进度就不再更新，
  /// 只能手动刷新。这里重建连接并向服务器对账一次——对账就是刷新按钮
  /// 做的事，只针对「本地认为还没结束」的记录，空闲时不发多余请求。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state != AppLifecycleState.resumed) return;

    if (!ref.read(connectionProvider).isConnected) return;
    final hasPending = ref
        .read(taskManagerProvider)
        .history
        .any((t) => t.status.isPending);
    if (!hasPending) return;

    ref.read(wsProvider.notifier).ensureAlive();
    unawaited(ref.read(taskManagerProvider.notifier).reconcilePendingTasks());
  }

  @override
  Widget build(BuildContext context) {
    // 监听当前选中的 Tab 索引
    final currentIndex = ref.watch(mainTabIndexProvider);
    final l = AppLocalizations.of(context);

    return Scaffold(
      body: IndexedStack(
        index: currentIndex,
        children: const [
          HomeView(),
          HistoryView(),
          GalleryView(),
          SettingsView(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: currentIndex,
        onDestinationSelected: (int index) {
          // 只有真的换页才震：重复点同一个标签不该有反馈
          if (index != currentIndex) {
            hapticFeedback(ref, HapticCategory.nav);
          }
          // 更新全局索引
          ref.read(mainTabIndexProvider.notifier).state = index;
        },
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.dashboard_outlined),
            selectedIcon: const Icon(Icons.dashboard),
            label: l.navWorkflow,
          ),
          NavigationDestination(
            icon: const Icon(Icons.history_outlined),
            selectedIcon: const Icon(Icons.history),
            label: l.navHistory,
          ),
          NavigationDestination(
            icon: const Icon(Icons.photo_library_outlined),
            selectedIcon: const Icon(Icons.photo_library),
            label: l.navGallery,
          ),
          NavigationDestination(
            icon: const Icon(Icons.settings_outlined),
            selectedIcon: const Icon(Icons.settings),
            label: l.navSettings,
          ),
        ],
      ),
    );
  }
}
