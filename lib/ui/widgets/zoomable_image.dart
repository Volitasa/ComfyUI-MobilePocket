import 'package:flutter/material.dart';

/// 可双击放大的图片容器。
///
/// `InteractiveViewer` 自带双指缩放和拖动，但**没有双击**——而手机上看图的第一反应就是双击。
/// 生成记录 / 画廊 / 参数预览三处查看器共用这一个，别各写一份。
///
/// ⚠️ 与 `PageView` 的手势仲裁：放大后横向拖动是「平移图片」，`PageView` 会抢这一下，
/// 表现就是「要么拖不动图，要么一拖就翻页」。所以缩放态一变就通过 [onZoomChanged]
/// 通知外层把翻页关掉（`NeverScrollableScrollPhysics`），缩回 1.0 再恢复。
class ZoomableImage extends StatefulWidget {
  const ZoomableImage({
    super.key,
    required this.child,
    this.onZoomChanged,
    this.maxScale = 6,
    this.doubleTapScale = 2.5,
  });

  final Widget child;

  /// 进入 / 退出放大态时回调（true = 已放大）。
  final ValueChanged<bool>? onZoomChanged;

  final double maxScale;

  /// 双击一次放大到几倍。
  final double doubleTapScale;

  @override
  State<ZoomableImage> createState() => _ZoomableImageState();
}

class _ZoomableImageState extends State<ZoomableImage>
    with SingleTickerProviderStateMixin {
  final TransformationController _controller = TransformationController();
  late final AnimationController _zoom = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
  );

  Animation<Matrix4>? _tween;
  Offset _tapPoint = Offset.zero;
  bool _zoomed = false;

  /// 超过它才算「放大态」。留余量是为了不让 1.01 这种误触把翻页锁死。
  static const double _zoomedThreshold = 1.05;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_syncZoomState);
    _zoom.addListener(() {
      final tween = _tween;
      if (tween != null) _controller.value = tween.value;
    });
  }

  @override
  void dispose() {
    _controller.removeListener(_syncZoomState);
    _controller.dispose();
    _zoom.dispose();
    super.dispose();
  }

  void _syncZoomState() {
    final zoomed = _controller.value.getMaxScaleOnAxis() > _zoomedThreshold;
    if (zoomed == _zoomed) return;
    _zoomed = zoomed;
    widget.onZoomChanged?.call(zoomed);
  }

  void _handleDoubleTap() {
    final current = _controller.value.getMaxScaleOnAxis();
    final target = current > _zoomedThreshold ? 1.0 : widget.doubleTapScale;
    final Matrix4 end;
    if (target <= 1.0) {
      end = Matrix4.identity();
    } else {
      // 以**点击处**为锚点放大：从中心放大的话，想看的那个角落会被推出屏幕。
      // 推导：要 s·p + t = p，即 t = -p·(s-1)
      end = Matrix4.identity()
        ..translateByDouble(
          -_tapPoint.dx * (target - 1),
          -_tapPoint.dy * (target - 1),
          0,
          1,
        )
        ..scaleByDouble(target, target, 1, 1);
    }

    // 系统开了「移除动画」就一步到位，别补间
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = end;
      return;
    }
    _tween = Matrix4Tween(
      begin: _controller.value,
      end: end,
    ).animate(CurvedAnimation(parent: _zoom, curve: Curves.easeOutCubic));
    _zoom.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    // ⚠️ 手势识别器必须**装在 InteractiveViewer 里面**（即它的 child）。
    // 装在外面时，InteractiveViewer 的缩放/拖动识别器会先在竞技场里吃掉这一下，
    // 双击根本不会触发（实测：装外面双击后 scale 仍是 1.0）。
    // 装在里面还有个好处：localPosition 直接就是「矩阵输入空间」里的坐标，
    // 锚点公式不用再做逆变换。
    return InteractiveViewer(
      transformationController: _controller,
      maxScale: widget.maxScale,
      child: GestureDetector(
        // 落点只能从 onDoubleTapDown 拿到（onDoubleTap 不带坐标），
        // 但**触发放大必须留在 onDoubleTap**：GestureDetector 只有在 onDoubleTap 不为 null
        // 时才会安装双击识别器，只给 onDoubleTapDown 的话双击根本不触发（实测整组用例失败）。
        onDoubleTapDown: (details) => _tapPoint = details.localPosition,
        onDoubleTap: _handleDoubleTap,
        child: widget.child,
      ),
    );
  }
}
