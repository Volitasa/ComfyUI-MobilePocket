import 'package:flutter/material.dart';

import '../../theme.dart';

/// 骨架屏：加载时先把「将要出现的东西」的形状摆出来。
///
/// 为什么不用居中转圈：转圈只说明「在等」，骨架同时说明「等的是什么」；
/// 内容到了是「填进去」，而不是「整页换掉」，视线不用重新找位置。
///
/// ⚠️ 横扫的流光是**无限动画**，两件事必须同时成立：
/// ① 后台页面不能再跑——这里用的是 [AnimationController]，`TickerMode` 为 false 时
///    框架会自动把它 mute，`IndexedStack` 里那四个常驻 Tab 就是靠这个停下来的；
/// ② 系统开了「移除动画」时退化成静止灰条（隐式动画不会自己尊重这个开关）。
class SkeletonShimmer extends StatefulWidget {
  const SkeletonShimmer({super.key, required this.child});

  final Widget child;

  @override
  State<SkeletonShimmer> createState() => _SkeletonShimmerState();
}

class _SkeletonShimmerState extends State<SkeletonShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  );
  bool _running = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 无障碍开关可能在运行中被改（系统设置里随时能关），所以放在这里而不是 initState
    final animate = !MediaQuery.disableAnimationsOf(context);
    if (animate && !_running) {
      _running = true;
      _controller.repeat();
    } else if (!animate && _running) {
      _running = false;
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 不动画时直接给灰条，不再套一层遮罩：省一次合成，也不会有「静止的渐变」
    if (!_running) return widget.child;

    final base = context.containerFill;
    final highlight = Theme.of(context).brightness == Brightness.dark
        ? Color.lerp(base, Colors.white, 0.07)!
        : Colors.white;

    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) => ShaderMask(
        // srcATop：只给「有像素的地方」上色，灰条之外的空白保持透明
        blendMode: BlendMode.srcATop,
        shaderCallback: (bounds) => LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [base, highlight, base],
          stops: const [0.25, 0.5, 0.75],
          transform: _SlidingGradientTransform(_controller.value),
        ).createShader(bounds),
        child: child,
      ),
    );
  }
}

/// 把渐变整体左右平移，形成横扫。
class _SlidingGradientTransform extends GradientTransform {
  const _SlidingGradientTransform(this.progress);

  final double progress;

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues(bounds.width * (progress * 2.4 - 1.2), 0, 0);
}

/// 一块占位。颜色本身会被上层的遮罩盖掉，这里只需要不透明。
class SkeletonBar extends StatelessWidget {
  const SkeletonBar({super.key, this.width, this.height = 10, this.radius = 4});

  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: context.containerFill,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// 工作流列表的骨架：两行字 + 行间距，跟真实条目同高。
///
/// 行宽刻意不一致——等宽的几条一看就是「假的行」，反而更抓眼。
class WorkflowListSkeleton extends StatelessWidget {
  const WorkflowListSkeleton({super.key, this.rows = 6});

  final int rows;

  static const List<double> _titleFactors = [0.58, 0.46, 0.62, 0.5, 0.55, 0.42];

  @override
  Widget build(BuildContext context) {
    return SkeletonShimmer(
      child: ListView(
        padding: const EdgeInsets.all(20),
        physics: const NeverScrollableScrollPhysics(),
        children: [
          for (var i = 0; i < rows; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: _titleFactors[i % _titleFactors.length],
                    child: const SkeletonBar(height: 12),
                  ),
                  const SizedBox(height: 6),
                  FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor:
                        _titleFactors[i % _titleFactors.length] * 0.6,
                    child: const SkeletonBar(height: 9),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// 画廊网格的骨架：与真实网格同样的列数、间距、圆角。
class GalleryGridSkeleton extends StatelessWidget {
  const GalleryGridSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return SkeletonShimmer(
      child: GridView.builder(
        padding: const EdgeInsets.all(12),
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
        ),
        itemCount: 12,
        itemBuilder: (context, index) =>
            const SkeletonBar(height: double.infinity, radius: 8),
      ),
    );
  }
}
