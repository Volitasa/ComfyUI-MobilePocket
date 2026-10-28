import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// 图片参数卡片里的缩略图：模糊铺底 + 上层完整图。
///
/// 图片比例千奇百怪，卡片宽度却要固定：
/// - 只放 `contain`，竖图两侧会留出大片底色；
/// - 只放 `cover`，竖图会被裁得只剩中间一条。
///
/// 所以底层用同图放大裁切 + 大半径模糊把两侧填满（反正是背景，不需要清晰，
/// `cacheWidth` 压到 120 解码），上层再叠一张完整不裁切的图。这样任何比例
/// 都不会出现白边，也不会丢内容。
class ImageThumb extends StatelessWidget {
  const ImageThumb({
    super.key,
    this.bytes,
    this.url,
    this.height = 120,
    this.onTap,
  }) : assert(bytes != null || url != null);

  /// 本地选的图（还没上传时只有内存里的字节）
  final Uint8List? bytes;

  /// 服务器已有图的 /view 地址
  final String? url;

  final double height;
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
                  child: _image(fit: BoxFit.cover, cacheWidth: 120),
                ),
              ),
            ),
            Center(child: _image(fit: BoxFit.contain, cacheWidth: 560)),
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

  Widget _image({required BoxFit fit, required int cacheWidth}) {
    if (bytes != null) {
      return Image.memory(
        bytes!,
        fit: fit,
        cacheWidth: cacheWidth,
        gaplessPlayback: true,
      );
    }
    return Image.network(
      url!,
      fit: fit,
      cacheWidth: cacheWidth,
      gaplessPlayback: true,
      // 服务器上的图可能被删了：铺底层留空即可，上层才显示破图图标
      errorBuilder: (_, _, _) => fit == BoxFit.cover
          ? const SizedBox.shrink()
          : const Icon(Icons.broken_image_outlined, size: 28),
    );
  }
}
