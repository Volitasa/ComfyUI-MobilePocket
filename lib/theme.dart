import 'package:flutter/material.dart';

/// 明色基准值。
///
/// 这些常量只描述**明色**下的取值，供 `AppTheme.lightScheme()` 与
/// `AppSemanticColors` 引用；界面代码一律通过 `context.xxx` 取色，
/// 不要再直接写常量——常量不随亮/暗切换，深色下必然失色。
class AppColors {
  AppColors._();

  /// 明色页面底色。
  ///
  /// 不能太接近卡片色：卡片是 #F7F8F7，原先底色取 #F4F5F4 只差 1.3% 明度，
  /// 容器色去掉黄绿色相后卡片边界就看不见了（以前是靠色相差撑着的）。
  /// 这里压到 #EFF1EF，与卡片拉开约 7%，分组边界重新成立。
  static const Color scaffoldBackground = Color(0xFFEFF1EF);

  /// 成功状态（明色基准）
  static const Color success = Color(0xFF2E7D32);

  /// 失败状态（明色基准）
  static const Color danger = Color(0xFFD32F2F);

  /// 进行中/警告（明色基准）。
  ///
  /// 原来是 #F57C00，在卡片底上只有 2.54:1——「排队中 / 生成中」是 11px 小字，
  /// 这个值等于看不清。压到 #B45309 后 4.72:1 过线，色相仍是橙（25°），
  /// 与红色的失败态、绿色的成功态不会混。
  static const Color warning = Color(0xFFB45309);

  /// 中断/中性（明色基准）。#757575 在填充底上只有 4.14:1，收到 #6B6B6B（4.79:1）。
  static const Color neutral = Color(0xFF6B6B6B);
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

  /// 深色方案。`fromSeed` 在深色下输出天然协调，容器色不需要像浅色那样覆写。
  static ColorScheme darkScheme() => ColorScheme.fromSeed(
    seedColor: const Color(0xFF6FC08A),
    brightness: Brightness.dark,
  );
}

/// 按当前主题取色的快捷方式。
///
/// 用扩展而不是 `AppColors` 常量，是因为**常量不随亮/暗主题切换**：
/// #5F665F 在浅色卡片上是 5.5:1，到了深色卡片底只有 2.89:1，等于隐形。
/// 凡是要支持多主题的颜色，都必须走这里。
extension AppThemeColors on BuildContext {
  /// 次要文字 / 次要图标
  Color get textSecondary => Theme.of(this).colorScheme.onSurfaceVariant;

  /// 柔和边框
  Color get borderColor => Theme.of(this).colorScheme.outlineVariant;

  /// 输入框填充。两种主题下都是「比所在卡片亮一档」：
  /// 浅色用纯白（卡片是 #F7F8F7），深色用 surfaceContainerHighest（卡片是 #181D18）。
  /// 直接写死 `Colors.white` 的话，深色下会冒出一片瞎白块。
  Color get fieldFill => Theme.of(this).brightness == Brightness.dark
      ? Theme.of(this).colorScheme.surfaceContainerHighest
      : Colors.white;

  /// 次要容器填充：搜索框、缩略图占位、键名小标签这类「卡片里的浅底块」。
  /// 浅色取 surfaceContainer（#F2F3F2），深色取 surfaceContainerHigh（#262B27）——
  /// 深色下不能用更「低」的容器，否则和页面底分不出边界。
  Color get containerFill => Theme.of(this).brightness == Brightness.dark
      ? Theme.of(this).colorScheme.surfaceContainerHigh
      : Theme.of(this).colorScheme.surfaceContainer;

  /// 强调色（用法的原意是「品牌绿」）。深色下 primary 自动变成提亮版，
  /// 所以不要再写死 `AppColors.primary` —— 那个常量在深底上只有 2.6:1。
  Color get accent => Theme.of(this).colorScheme.primary;

  /// 强调色底上的前景（主色按钮的文字 / 图标 / 转圈）
  Color get onAccent => Theme.of(this).colorScheme.onPrimary;

  /// 装饰性弱化图标（空状态的大插画）。不承载信息，所以不按 4.5:1 要求，
  /// 但深浅两套都得「隐约看得见」，不能是灰 400（深色下会变亮块）。
  Color get iconMuted =>
      Theme.of(this).brightness == Brightness.dark
      ? const Color(0xFF8D958D)
      : const Color(0xFFB4B8B4);
}

/// 随主题变化的语义色。
///
/// 原来这些是常量（#2E7D32 / #D32F2F / #757575），都是为白底挑的中深色，
/// 到了深底上只有 3.3–3.7:1，读不出来。深色下换成提亮版（8.9 / 7.5 / 7.7:1）。
extension AppSemanticColors on BuildContext {
  bool get _isDark => Theme.of(this).brightness == Brightness.dark;

  Color get stateSuccess => _isDark ? const Color(0xFF6FCF85) : AppColors.success;

  Color get stateDanger => _isDark ? const Color(0xFFFF8A80) : AppColors.danger;

  Color get stateNeutral => _isDark ? const Color(0xFFADAEAD) : AppColors.neutral;

  /// 警告色。深色下不能再沿用 #B45309（在 #181D18 上只有 3.9:1），换成提亮版。
  Color get stateWarning =>
      _isDark ? const Color(0xFFFFB74D) : AppColors.warning;

  /// 警告色底上的前景，只在把 warning 当填充色用时需要
  Color get onStateWarning => _isDark ? const Color(0xFF3A2A0D) : Colors.white;

  // ---- 状态容器（提示条 / 徽标 / 「有新版本」卡片）----
  // 浅色是浅底深字，深色必须反转成深底浅字；值都验算过 ≥5.7:1。
  Color get stateSuccessFill =>
      _isDark ? const Color(0xFF1B3A22) : const Color(0xFFE8F5E9);
  Color get onStateSuccessFill =>
      _isDark ? const Color(0xFF8FD9A0) : const Color(0xFF1B5E20);
  Color get stateSuccessOutline =>
      _isDark ? const Color(0xFF2E5B39) : const Color(0xFFA5D6A7);

  Color get stateWarningFill =>
      _isDark ? const Color(0xFF3A2A0D) : const Color(0xFFFFF4E5);
  Color get onStateWarningFill =>
      _isDark ? const Color(0xFFFFC06B) : const Color(0xFF7A4A00);
  Color get stateWarningOutline =>
      _isDark ? const Color(0xFF6B4A1B) : const Color(0xFFF0C99A);

  Color get stateDangerFill =>
      _isDark ? const Color(0xFF4A1C1A) : const Color(0xFFFDECEA);
  Color get onStateDangerFill =>
      _isDark ? const Color(0xFFFFA9A0) : const Color(0xFFB3261E);

  // ---- 危险动作的实底按钮（删除确认）----
  // ⚠️ 不能拿 stateDangerFill 当按钮底：那是 #FDECEA 的浅底，白字在上面只有 1.14:1。
  // ⚠️ 也不能拿 stateDanger 当按钮底：它是「深色下的文字色」#FF8A80（浅粉），
  //    铺成实底再压白字只有 2.28:1，等于把删除按钮做成一块看不清字的粉饼。
  // 实底按钮必须**底与字成对**，而且深色要反过来还不够——深色下再把这个
  // 浅粉色当底铺满整块，会把「删除」做成全屏最亮的一块，抢走所有注意力。
  // 这里两套都是「深红底 + 亮字」：明色 #D32F2F+白（4.97:1），
  // 深色 #93000A+#FFDAD6（7.2:1），视觉重量与浅色那块一致。
  Color get dangerButtonFill =>
      _isDark ? const Color(0xFF93000A) : AppColors.danger;

  /// [dangerButtonFill] 底上的文字 / 图标。
  ///
  /// 不写的话就是 FilledButton 默认的 `onPrimary`——那是品牌绿那一组的前景，
  /// 跟这块红底毫无关系，深浅两套下都会配出「红底绿字」这种错色。
  Color get onDangerButtonFill =>
      _isDark ? const Color(0xFFFFDAD6) : Colors.white;
}

