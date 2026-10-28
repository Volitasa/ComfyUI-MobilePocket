import 'package:flutter/material.dart';

import '../../theme.dart';

/// 图片参数卡片右侧的操作列：文件名 + 来源 + 一颗（或两颗）按钮。
///
/// 它和左边的缩略图共用同一行高度，所以这里的高度是写死的：卡片再高一点
/// 就会把别的参数挤出屏幕。右列宽度只有卡片的两成，长文件名 + 两颗按钮
/// 曾经溢出 27px（实机截图抓到的），因此文件名在双按钮状态下只占一行。
class ImageParamActions extends StatelessWidget {
  const ImageParamActions({
    super.key,
    required this.filename,
    required this.sourceLabel,
    required this.primaryLabel,
    required this.onPrimary,
    this.placeholder,
    this.secondaryLabel,
    this.onSecondary,
    this.height = 120,
  });

  /// 文件名；为空时显示 [placeholder]
  final String? filename;
  final String? placeholder;
  final String sourceLabel;
  final String primaryLabel;
  final VoidCallback onPrimary;

  /// 第二颗按钮（如「用原图」）；为 null 时只剩一颗
  final String? secondaryLabel;
  final VoidCallback? onSecondary;
  final double height;

  @override
  Widget build(BuildContext context) {
    final name = filename;
    final twoButtons = secondaryLabel != null && onSecondary != null;
    return SizedBox(
      height: height,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            name ?? placeholder ?? '',
            style: const TextStyle(fontSize: 12, height: 1.35),
            maxLines: twoButtons ? 1 : 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (name != null) ...[
            const SizedBox(height: 2),
            Text(
              sourceLabel,
              style: TextStyle(
                fontSize: 11,
                height: 1.3,
                color: context.textSecondary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          // 按钮固定贴底：名字只有一行时也不会浮到中间，和左图的上下沿对齐
          const Spacer(),
          _button(primaryLabel, onPrimary),
          if (twoButtons) ...[
            const SizedBox(height: 6),
            _button(secondaryLabel!, onSecondary!),
          ],
        ],
      ),
    );
  }

  Widget _button(String label, VoidCallback onTap) {
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        padding: EdgeInsets.zero,
        minimumSize: const Size.fromHeight(32),
        visualDensity: VisualDensity.compact,
        textStyle: const TextStyle(fontSize: 12),
      ),
      onPressed: onTap,
      child: Text(label),
    );
  }
}
