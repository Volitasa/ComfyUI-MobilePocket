import 'package:flutter/material.dart';

import '../../theme.dart';

/// 两处共用的紧凑搜索框（生成记录页、工作流配置页）。
///
/// 高度刻意锁死在 40：输入框的前置图标默认带 48×48 的最小约束，会硬把
/// 整个框撑到 48 高，外面再套一圈实线边框，搜索框就成了页面上最扎眼的一块。
/// 这里把图标约束收紧、内边距交给外层定高，并换成「浅灰填充 + 无边框」，
/// 让它退回成一个顺手的工具，而不是页面的视觉重心。
///
/// 两页共用同一个控件，是为了避免样式在两处各自漂移
/// （改之前这两段代码是复制的，改样式必须两边都记得改）。
class CompactSearchField extends StatelessWidget {
  const CompactSearchField({
    super.key,
    required this.controller,
    required this.hintText,
    required this.hasText,
    required this.onChanged,
    required this.onClear,
  });

  /// 行高。与它同处一行的其它控件（工具条按钮）也是这个高度。
  static const double height = 40;

  final TextEditingController controller;
  final String hintText;

  /// 是否有输入内容（决定清除按钮是否出现）
  final bool hasText;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  static const BorderRadius _radius = BorderRadius.all(Radius.circular(10));

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        textAlignVertical: TextAlignVertical.center,
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: Colors.grey.shade100,
          hintText: hintText,
          hintStyle: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          prefixIcon: const Icon(Icons.search, size: 17),
          prefixIconConstraints: const BoxConstraints(
            minWidth: 32,
            minHeight: 32,
          ),
          suffixIcon: hasText
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 17),
                  tooltip: MaterialLocalizations.of(context).clearButtonTooltip,
                  onPressed: onClear,
                )
              : null,
          suffixIconConstraints: const BoxConstraints(
            minWidth: 36,
            minHeight: 36,
          ),
          border: const OutlineInputBorder(
            borderRadius: _radius,
            borderSide: BorderSide.none,
          ),
          enabledBorder: const OutlineInputBorder(
            borderRadius: _radius,
            borderSide: BorderSide.none,
          ),
          focusedBorder: const OutlineInputBorder(
            borderRadius: _radius,
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
        ),
      ),
    );
  }
}
