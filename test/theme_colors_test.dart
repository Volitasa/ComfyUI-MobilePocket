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

    test('警告色不能是「好看的浅橙」——它是小字状态文案的颜色', () {
      // #F57C00 在卡片底上只有 2.54:1，「排队中 / 生成中」是 11px 小字，读不出来。
      expect(
        _contrast(AppColors.warning, scheme.surfaceContainerLow),
        greaterThanOrEqualTo(4.5),
        reason:
            '警告色 ${_hex(AppColors.warning)} 对卡片底 '
            '${_hex(scheme.surfaceContainerLow)} 对比度不足，小字状态会看不清',
      );
    });

    test('对比度算法本身要能区分好坏', () {
      // 防止 _contrast 写错成「永远达标」，把上面几条变成摆设
      expect(_contrast(const Color(0xFFF57C00), Colors.white), lessThan(3.0));
      expect(_contrast(const Color(0xFF171A17), Colors.white), greaterThan(15));
    });
  });

  group('深色配色', () {
    final dark = AppTheme.darkScheme();
    final card = dark.surfaceContainerLow;

    test('文字达到可读下限', () {
      expect(_contrast(dark.onSurface, card), greaterThanOrEqualTo(4.5),
          reason: '主文字 ${_hex(dark.onSurface)} 对深色卡片 ${_hex(card)} 对比度不足');
      expect(
        _contrast(dark.onSurfaceVariant, card),
        greaterThanOrEqualTo(4.5),
        reason: '次要文字 ${_hex(dark.onSurfaceVariant)} 对深色卡片 ${_hex(card)} 对比度不足',
      );
    });

    test('页面底与卡片仍能分开', () {
      // 明色那次教训：卡片和页面底只差 1.3% 明度，分组边界直接塌掉。
      final ratio =
          _luminance(card) > _luminance(dark.surface)
              ? _luminance(card) / _luminance(dark.surface)
              : _luminance(dark.surface) / _luminance(card);
      expect(
        ratio,
        greaterThan(1.05),
        reason: '深色下卡片 ${_hex(card)} 与页面底 ${_hex(dark.surface)} 明度太接近',
      );
    });
  });

  group('语义色的深浅两套都成立', () {
    Future<void> check(
      WidgetTester tester,
      ColorScheme colorScheme,
      String label,
    ) async {
      late BuildContext ctx;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(useMaterial3: true, colorScheme: colorScheme),
          home: Builder(
            builder: (c) {
              ctx = c;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      final card = colorScheme.surfaceContainerLow;
      // 前景色：当文字/图标画在卡片上
      for (final entry in {
        '成功': ctx.stateSuccess,
        '警告': ctx.stateWarning,
        '失败': ctx.stateDanger,
        '中性': ctx.stateNeutral,
        '强调': ctx.accent,
      }.entries) {
        expect(
          _contrast(entry.value, card),
          greaterThanOrEqualTo(4.5),
          reason: '$label·${entry.key}色 ${_hex(entry.value)} 画在卡片 ${_hex(card)} 上太淡',
        );
      }
      // 容器配对：提示条 / 徽标的底与字
      for (final entry in {
        '成功提示条': [ctx.stateSuccessFill, ctx.onStateSuccessFill],
        '警告提示条': [ctx.stateWarningFill, ctx.onStateWarningFill],
        '失败提示条': [ctx.stateDangerFill, ctx.onStateDangerFill],
      }.entries) {
        expect(
          _contrast(entry.value[0], entry.value[1]),
          greaterThanOrEqualTo(4.5),
          reason:
              '$label·${entry.key} 底 ${_hex(entry.value[0])} 与字 '
              '${_hex(entry.value[1])} 对比度不足',
        );
      }
      // 按钮用的前景配强调底
      expect(
        _contrast(ctx.accent, ctx.onAccent),
        greaterThanOrEqualTo(4.5),
        reason: '$label·强调按钮（${_hex(ctx.accent)}）上的文字 ${_hex(ctx.onAccent)} 对比度不足',
      );
    }

    testWidgets('明色', (tester) async {
      await check(tester, AppTheme.lightScheme(), '明色');
    });

    testWidgets('深色', (tester) async {
      await check(tester, AppTheme.darkScheme(), '深色');
    });
  });
}
