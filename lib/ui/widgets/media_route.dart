import 'package:flutter/material.dart';

/// 看图用的路由。
///
/// 为什么不能直接用 `MaterialPageRoute`：看图页的底色是纯黑，而 Material 的转场
/// 是**整页一起淡入**的——于是屏幕上是「图一边长大、背后同时整块黑了」，
/// 共享元素带来的连续感立刻被打断。
///
/// 这里把页面做成非不透明（`opaque: false`），并让整页的淡入推迟到转场后 35%：
/// 前半程只看得见正在飞的那张图（下方列表照旧显示），后半程深色底才合拢。
Route<T> mediaViewerRoute<T>(WidgetBuilder builder) {
  return PageRouteBuilder<T>(
    // 非不透明：下面那页要继续画，深色底才能"淡进来"而不是"切进来"
    opaque: false,
    transitionDuration: const Duration(milliseconds: 420),
    reverseTransitionDuration: const Duration(milliseconds: 300),
    pageBuilder: (context, animation, secondaryAnimation) => builder(context),
    transitionsBuilder: (context, animation, secondary, child) {
      return FadeTransition(
        // 前 35% 完全透明：这段时间属于共享元素
        opacity: CurvedAnimation(
          parent: animation,
          curve: const Interval(0.35, 1, curve: Curves.easeOut),
        ),
        child: child,
      );
    },
  );
}
