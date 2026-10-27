import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:comfyui_mobilepocket/theme.dart';

double _channel(int v) {
  final s = v / 255.0;
  return s <= 0.03928
      ? s / 12.92
      : math.pow((s + 0.055) / 1.055, 2.4).toDouble();
}

double _luminance(Color c) {
  final a = c.toARGB32();
  return 0.2126 * _channel((a >> 16) & 0xFF) +
      0.7152 * _channel((a >> 8) & 0xFF) +
      0.0722 * _channel(a & 0xFF);
}

/// WCAG 相对亮度对比度，正文可读下限为 4.5:1。
double _contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

String _hex(Color c) =>
    '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

void main() {
  final scheme = AppTheme.lightScheme();

  group('明色配色', () {
    test('中性面不沾种子色相', () {
      // M3 默认派生的 surfaceContainerLow 是 #F1F5EC（色相 87°，黄绿），
      // 大面积铺开整屏泛黄，所以这里要求容器色接近中性。
      for (final entry in {
        'surfaceContainerLowest': scheme.surfaceContainerLowest,
        'surfaceContainerLow': scheme.surfaceContainerLow,
        'surfaceContainer': scheme.surfaceContainer,
        'surfaceContainerHigh': scheme.surfaceContainerHigh,
      }.entries) {
        final saturation = HSLColor.fromColor(entry.value).saturation;
        expect(
          saturation,
          lessThan(0.15),
          reason:
              '${entry.key}（${_hex(entry.value)}）饱和度 $saturation 过高，'
              '中性面会被染上种子色相',
        );
      }
    });

    test('文字达到可读下限', () {
      final cardSurface = scheme.surfaceContainerLow;
      expect(
        _contrast(scheme.onSurface, cardSurface),
        greaterThanOrEqualTo(4.5),
        reason: '主文字 ${_hex(scheme.onSurface)} 对卡片底 ${_hex(cardSurface)} 对比度不足',
      );
      expect(
        _contrast(scheme.onSurfaceVariant, cardSurface),
        greaterThanOrEqualTo(4.5),
        reason:
            '次要文字 ${_hex(scheme.onSurfaceVariant)} 对卡片底 ${_hex(cardSurface)} '
            '对比度不足（改版前实测只有 2.23:1，界面会发闷）',
      );
    });

    test('品牌主色落在绿色的色相区间', () {
      // 绿在 120° 附近，冷绿到 160° 仍算绿；低于 100° 就偏黄绿了。
      final hue = HSLColor.fromColor(scheme.primary).hue;
      expect(
        hue,
        inInclusiveRange(110.0, 180.0),
        reason: '主色 ${_hex(scheme.primary)} 色相 $hue° 不在绿色区间',
      );
    });

    test('页面底色比卡片更沉，白卡片才浮得起来', () {
      expect(
        _luminance(AppColors.scaffoldBackground),
        lessThan(_luminance(scheme.surface)),
        reason: '页面底色应比卡片表面暗，否则卡片无法与背景分离',
      );
    });
  });
}
