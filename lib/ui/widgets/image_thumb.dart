import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../services/throttled_image.dart';

/// 图片参数卡片里的缩略图：模糊铺底 + 上层完整图。
///
/// 图片比例千奇百怪，卡片宽度却要固定：
/// - 只放 `contain`，竖图两侧会留出大片底色；
/// - 只放 `cover`，竖图会被裁得只剩中间一条。
///
/// 所以底层用同图放大裁切 + 大半径模糊把两侧填满，上层再叠一张完整不裁切的图。
/// 这样任何比例都不会出现白边，也不会丢内容。
///
/// ⚠️ **两层必须用同一个解码宽度**（[kThumbDecodeWidth]）。
/// `Image.network(url, cacheWidth: X)` 内部的缓存键是
/// `ResizeImage(NetworkImage(url), width: X)`，而 `ResizeImage` 的相等性
/// **包含 width** —— 底层写 120、上层写 560 就是两个不同的键，
/// ImageCache 会当成两张不同的图，**同一张缩略图向服务器请求两次**。
/// 服务端每张 `preview` 都是同步转码（webp;50 约 216ms），
/// 多出来的那一次纯属白占事件循环。模糊层用 560 解码看不出差别。
const int kThumbDecodeWidth = 560;

class ImageThumb extends StatelessWidget {
  const ImageThumb({
    super.key,
    this.bytes,
    this.url,
    this.height = 120,
    this.scope = '',
    this.onTap,
  }) : assert(bytes != null || url != null);

  /// 本地选的图（还没上传时只有内存里的字节）
  final Uint8List? bytes;

  /// 服务器已有图的 /view 地址
  final String? url;

  final double height;

  /// 发起方标识，用于「离开页面时取消排队中的请求」（见 ImageFetchGate）
  final String scope;

  final VoidCallback? onTap;

  static const double _radius = 8;

  @override
  Widget build(BuildContext context) {
    final content = ClipRRect(
      borderRadius: BorderRadius.circular(_radius),
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              child: Opacity(
                // 0.55 时竖图两侧被卡片底色冲得太淡，看不出是同一张图；
                // 0.7 既保留"这是背景"的存在感，又不跟上层清晰图抢注意力。
                opacity: 0.7,
                child: ImageFiltered(
                  imageFilter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                  child: _image(fit: BoxFit.cover),
                ),
              ),
            ),
            Center(child: _image(fit: BoxFit.contain)),
          ],
        ),
      ),
    );

    if (onTap == null) return content;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(_radius),
      child: content,
    );
  }

  Widget _image({required BoxFit fit}) {
    if (bytes != null) {
      return Image.memory(
        bytes!,
        fit: fit,
        cacheWidth: kThumbDecodeWidth,
        gaplessPlayback: true,
      );
    }
    return Image(
      // 尺寸交给 ResizeImage 算进缓存键；请求本身由 ThrottledNetworkImage 限流
      image: ResizeImage(
        ThrottledNetworkImage(url!, scope: scope),
        width: kThumbDecodeWidth,
      ),
      fit: fit,
      gaplessPlayback: true,
      // 服务器上的图可能被删了：铺底层留空即可，上层才显示破图图标
      errorBuilder: (_, _, _) => fit == BoxFit.cover
          ? const SizedBox.shrink()
          : const Icon(Icons.broken_image_outlined, size: 28),
    );
  }
}
