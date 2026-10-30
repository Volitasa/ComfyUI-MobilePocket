import 'package:flutter/material.dart';

/// 看图页底部那条缩略图 rail 里的一项。
///
/// 刻意只描述"长什么样、点了做什么"：**谁提供图、点了跳到哪，由调用方决定**。
/// 生成记录页与画廊页的图源不同（前者可能是本地文件也可能是 /view 地址，
/// 后者一律本地文件），控件不该知道这些。
class RailItem {
  const RailItem({
    required this.thumb,
    this.selected = false,
    this.badge,
    this.onTap,
    this.onLongPressStart,
  });

  /// 缩略图。尺寸由 rail 统一给（34×34），调用方只管塞 [Image.file] / [Image.network]。
  final Widget thumb;

  final bool selected;

  /// 右下角小角标（输出张数）。null = 不显示。
  final String? badge;

  final VoidCallback? onTap;

  /// 按住不放：临时把主区域换成这张（松手由 rail 统一收尾）。
  final VoidCallback? onLongPressStart;
}

/// 看图页底部的缩略图条：**入口 + 状态**，不是第二个看图区。
///
/// 悬浮在主图区底部（由调用方用 `Positioned` 摆），**不参与布局**——
/// 不挤压主图空间，也不会让"有参考图的页"和"没参考图的页"几何不一致。
/// 只在这条记录有参考图时才出现。
///
/// 为什么是半透明 + 边框：纯黑底上一块实底色会变成"贴上去的黑块"，
/// 看不出和主图的关系；半透明能透出主图边缘，一眼知道它是浮在图上的。
/// 为什么缩略图只有 34：48 高的条里塞 44 的方块会顶出边；点击热区靠
/// `InkResponse` 撑到 40。为什么选中描边用白色而不是主题强调色：
/// 看图页是纯黑底，浅色主题下 `accent` 是深绿，压上去只有约 2:1，
/// 「选中」这件事会看不出来。
class ReferenceRail extends StatelessWidget {
  const ReferenceRail({
    super.key,
    required this.items,
    this.dividerAfter,
    this.onPeekEnd,
  });

  final List<RailItem> items;

  /// 在第 N 项之后画一条竖分隔（0 起）。null = 不画。
  final int? dividerAfter;

  /// 松手 / 指针离开：结束"临时预览"。
  final VoidCallback? onPeekEnd;

  /// rail 条本身的高度（含上下内边距）。
  static const double height = 48;
  static const double _thumb = 34;
  static const double _hit = 40;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    final children = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      if (i > 0) children.add(const SizedBox(width: 6));
      children.add(_buildItem(context, items[i]));
      if (dividerAfter == i && i != items.length - 1) {
        children.add(const SizedBox(width: 6));
        children.add(
          Container(width: 1, height: 24, color: Colors.white24),
        );
        children.add(const SizedBox(width: 6));
      }
    }

    return SizedBox(
      height: height,
      // 指针在任何位置抬起都算结束：光靠 item 自己的手势收不到"抬在条外面"
      child: Listener(
        onPointerUp: (_) => onPeekEnd?.call(),
        onPointerCancel: (_) => onPeekEnd?.call(),
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 4),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            // 半透明：透出下面的主图，读起来是"浮在图上的一条"
            color: Colors.black.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
          ),
          child: ListView(
            scrollDirection: Axis.horizontal,
            // 48 - 8(下边距) = 40 的可视高度，装 34 的图正好居中
            physics: const ClampingScrollPhysics(),
            children: children,
          ),
        ),
      ),
    );
  }

  Widget _buildItem(BuildContext context, RailItem item) {
    final thumb = Container(
      width: _thumb,
      height: _thumb,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: item.selected ? Colors.white : Colors.white24,
          width: item.selected ? 1.5 : 1,
        ),
      ),
      clipBehavior: Clip.hardEdge,
      child: Stack(
        fit: StackFit.expand,
        children: [
          item.thumb,
          if (item.badge != null)
            Positioned(
              right: 1,
              bottom: 1,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.62),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  item.badge!,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 8,
                    height: 1.4,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      ),
    );

    return InkResponse(
      onTap: item.onTap,
      onLongPress: item.onLongPressStart,
      radius: _hit / 2,
      containedInkWell: true,
      child: SizedBox(
        width: _hit,
        height: _hit,
        child: Center(child: thumb),
      ),
    );
  }
}
