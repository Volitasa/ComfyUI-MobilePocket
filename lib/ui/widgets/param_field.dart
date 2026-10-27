import 'package:flutter/material.dart';

import '../../theme.dart';

/// 运行页 / 尺寸卡共用的输入框外观。
///
/// 之前每个控件各写一份 `InputDecoration`，同一页里攒出了四套观感：
/// r8 白底（文本、数字、下拉）、r4 无底（滑块右侧数值框）、r4 无底（尺寸卡自定义宽高）、
/// 无边框（配置页别名框）。这里统一成一套 —— **r8 + 白底 + 1px 灰描边**，
/// 与尺寸卡的比例 chips 同一观感，卡片之间来回看不再像换了套皮肤。
///
/// 配置页的别名框刻意不在此列：那里要的是「看起来像文本、聚焦才知道能改」。
class ParamFieldStyle {
  const ParamFieldStyle._();

  static const double radius = 8;

  /// 单行控件的实际高度：InputDecorator 自己有 48 的下限，contentPadding
  /// 再小也压不下去（实测 48 就是底）。带 errorText 时还会更高，所以不能
  /// 用 SizedBox 写死高度，否则红字会被裁掉。
  static const double height = 48;

  /// 普通输入框（文本、数字、下拉）。
  static const EdgeInsetsGeometry contentPadding = EdgeInsets.symmetric(
    horizontal: 12,
    vertical: 12,
  );

  /// 紧凑输入框（滑块右侧的数值框、尺寸卡自定义宽高）。
  static const EdgeInsetsGeometry compactPadding = EdgeInsets.symmetric(
    horizontal: 8,
    vertical: 8,
  );

  static InputDecoration decoration(
    BuildContext context, {
    String? hintText,
    String? errorText,
    EdgeInsetsGeometry? contentPadding,
    String? suffixText,
    bool invalid = false,
  }) {
    // invalid 只管描边变红：滑块那侧的红字挂在控件外面（72 宽的框里塞不下整句）。
    final hasError = errorText != null || invalid;
    final side = BorderSide(
      color: hasError
          ? Theme.of(context).colorScheme.error
          : Colors.grey.shade300,
    );
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(radius),
      borderSide: side,
    );
    // 聚焦只换描边颜色，不换形状 —— 用户得看得出光标在哪个框里
    final focusBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(radius),
      borderSide: BorderSide(
        color: hasError
            ? Theme.of(context).colorScheme.error
            : Theme.of(context).colorScheme.primary,
        width: 1.5,
      ),
    );
    return InputDecoration(
      hintText: hintText,
      errorText: errorText,
      suffixText: suffixText,
      isDense: true,
      filled: true,
      fillColor: context.fieldFill,
      contentPadding: contentPadding ?? ParamFieldStyle.contentPadding,
      border: border,
      enabledBorder: border,
      focusedBorder: focusBorder,
    );
  }
}
