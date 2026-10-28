import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// 长按 [delay] 后开始拖动排序的监听。
///
/// 为什么不直接用官方的 `ReorderableDelayedDragStartListener`：它的延迟写死
/// `kLongPressTimeout`（500ms），而别名输入框（`TextField`）的长按选择也是 500ms。
/// 手势竞技场里**内层的 recognizer 先注册、先 accept**，所以 500ms 那一刻赢的是输入框 ——
/// 长按照名只会弹「全选 / 粘贴」菜单，拖不起来。这里的 300ms 抢在它前面。
///
/// 与「焦点决定长按归谁」配套使用：别名**聚焦时**调用方把 [enabled] 置 false，
/// 长按归还给输入框（全选 / 粘贴 / 拖光标都在）；未聚焦时长按即拖动。
/// 两边因此不冲突，谁都不用牺牲。
///
/// ⚠️ 本文件照抄自 Flutter **3.47.7** `widgets/reorderable_list.dart`
/// 的 `ReorderableDragStartListener` —— 唯一区别是把
/// `ImmediateMultiDragGestureRecognizer` 换成带自定义延迟的
/// `DelayedMultiDragGestureRecognizer`。`startItemDragReorder` 是公开 API，
/// 只是官方没把 delay 暴露出来。升级 Flutter 时若签名变了，改这里。
class ParamDragStartListener extends StatelessWidget {
  const ParamDragStartListener({
    super.key,
    required this.child,
    required this.index,
    this.enabled = true,
    this.delay = const Duration(milliseconds: 300),
  });

  /// 被包住的那一段（一张节点参数卡）。
  final Widget child;

  /// 该段在 `ReorderableListView` 里的下标。
  final int index;

  /// false 时这一段不可拖（只有一段、或段内正有别名在编辑中）。
  final bool enabled;

  /// 按住多久开始拖。默认 300ms：比系统长按（500ms）短 200ms，
  /// 又长于普通点击（<200ms），双击与滚动都不会误触。
  final Duration delay;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: enabled
          ? (PointerDownEvent event) => _startDragging(context, event)
          : null,
      child: child,
    );
  }

  void _startDragging(BuildContext context, PointerDownEvent event) {
    final gestureSettings = MediaQuery.maybeGestureSettingsOf(context);
    final list = SliverReorderableList.maybeOf(context);
    list?.startItemDragReorder(
      index: index,
      event: event,
      recognizer: DelayedMultiDragGestureRecognizer(
        delay: delay,
        debugOwner: this,
      )..gestureSettings = gestureSettings,
    );
  }
}
