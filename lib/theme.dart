import 'package:flutter/material.dart';

/// 全局主题色常量：统一品牌主色，避免各处硬编码 Colors.green。
class AppColors {
  AppColors._();

  /// 品牌主色（冷绿；与 AppTheme.lightScheme() 派生出的 primary 保持一致）
  static const Color primary = Color(0xFF256A4B);

  /// 明色页面底色。比纯白略沉一点，让白色卡片能浮起来。
  static const Color scaffoldBackground = Color(0xFFF4F5F4);

  /// 次要文字与图标色。
  ///
  /// 值是 `AppTheme.lightScheme().onSurfaceVariant` 的镜像（对卡片底 5.5:1）。
  /// 以前这些位置直接写 `Colors.grey`（#9E9E9E），在白底上只有 2.68:1、
  /// 在卡片底上更低，掉出了 4.5:1 的可读下限，界面整体发闷。
  /// 用常量而不是 `Theme.of(...)` 是为了保持 `const` 写法；等将来支持深色主题时，
  /// 这几处要改回按 `Theme.of(context).colorScheme.onSurfaceVariant` 取色。
  static const Color textSecondary = Color(0xFF5F665F);

  /// 柔和边框色，替代原先直接用的 `Colors.grey`（边框不需要那么重）。
  static const Color border = Color(0xFFE3E6E3);

  /// 成功状态
  static const Color success = Color(0xFF2E7D32);

  /// 失败状态
  static const Color danger = Color(0xFFD32F2F);

  /// 进行中/警告
  static const Color warning = Color(0xFFF57C00);

  /// 中断/中性
  static const Color neutral = Color(0xFF757575);
}

/// 明色主题。
///
/// 这里没有直接用 `ColorScheme.fromSeed` 的结果，而是在它之上覆写了一组容器色，
/// 原因是实测出来的：Material 3 会把中性面也染上种子色的色相。`Colors.green`
/// 派生出的 `surfaceContainerLow` 是 #F1F5EC，色相 87°——那是黄绿区间，不是绿，
/// 大面积铺开后整屏泛黄。换更冷的种子色（#2F7A57）也只能回到 110°，治标不治本，
/// 所以容器系列必须显式写成中性灰（饱和度 7% 左右），品牌绿只留在主色和淡强调处。
///
/// 次要文字同理：原来的 onSurfaceVariant 在卡片底上只有约 2.2:1 的对比度，
/// 远低于 4.5:1 的可读下限，这里加深到 5.5:1。
class AppTheme {
  AppTheme._();

  static ColorScheme lightScheme() =>
      ColorScheme.fromSeed(
        seedColor: const Color(0xFF2F7A57), // 冷绿（色相 153°），替代 Colors.green
        surface: Colors.white,
      ).copyWith(
        surfaceContainerLowest: Colors.white,
        surfaceContainerLow: const Color(0xFFF7F8F7),
        surfaceContainer: const Color(0xFFF2F3F2),
        surfaceContainerHigh: const Color(0xFFECEEEC),
        secondaryContainer: const Color(0xFFE4EFE8),
        onSurface: const Color(0xFF171A17),
        onSurfaceVariant: const Color(0xFF5F665F),
        outlineVariant: const Color(0xFFE3E6E3),
      );
}
