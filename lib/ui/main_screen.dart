import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'home/home_view.dart';
import 'gallery/history_view.dart';
import 'gallery/gallery_view.dart';
import 'setup/setup_view.dart';

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

class MainScreen extends ConsumerWidget {
  const MainScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 监听当前选中的 Tab 索引
    final currentIndex = ref.watch(mainTabIndexProvider);

    return Scaffold(
      body: IndexedStack(
        index: currentIndex,
        children: const [
          HomeView(),
          HistoryView(),
          GalleryView(),
          SetupView(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: currentIndex,
        onDestinationSelected: (int index) {
          // 更新全局索引
          ref.read(mainTabIndexProvider.notifier).state = index;
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: '工作流',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_outlined),
            selectedIcon: Icon(Icons.history),
            label: '生成记录',
          ),
          NavigationDestination(
            icon: Icon(Icons.photo_library_outlined),
            selectedIcon: Icon(Icons.photo_library),
            label: '画廊',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: '服务器配置',
          ),
        ],
      ),
    );
  }
}