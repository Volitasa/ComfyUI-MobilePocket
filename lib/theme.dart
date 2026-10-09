import 'package:flutter/material.dart';

/// 全局主题色常量：统一品牌主色，避免各处硬编码 Colors.green。
class AppColors {
  AppColors._();

  /// 品牌主色（绿色，对应 main.dart 的 seedColor）
  static const Color primary = Colors.green;

  /// 成功状态
  static const Color success = Color(0xFF2E7D32);

  /// 失败状态
  static const Color danger = Color(0xFFD32F2F);

  /// 进行中/警告
  static const Color warning = Color(0xFFF57C00);

  /// 中断/中性
  static const Color neutral = Color(0xFF757575);
}
