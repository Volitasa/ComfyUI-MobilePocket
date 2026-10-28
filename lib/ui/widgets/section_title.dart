import 'package:flutter/material.dart';

import '../../theme.dart';

/// 页面内的分组标题（如「通用」「API 工作流」「本地导入」）。
///
/// 以前每个页面各写一份：设置页 12 加粗、首页 12 常规、工作流存储页又是 12 常规
/// 但内边距不同 —— 同一角色三种写法，改一处漏两处。统一到这里，
/// 各页面只保留自己需要的**外边距**（设置页贴 16，卡片列表上方贴 4）。
///
/// 与 `kSubPageTitleStyle` 的区别：那个是二级页顶栏标题（16 / w600），
/// 这里是页面内部的小节标题，字号要压住、不能跟正文抢。
class SectionTitle extends StatelessWidget {
  const SectionTitle(
    this.text, {
    super.key,
    this.padding = const EdgeInsets.fromLTRB(4, 4, 4, 8),
  });

  final String text;

  /// 默认是「上方有 TabBar / 上一个分组」的 4；贴着说明文字时传 top 0，
  /// 设置页这类无卡片左右边距的页面传 16。
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: context.textSecondary,
        ),
      ),
    );
  }
}
