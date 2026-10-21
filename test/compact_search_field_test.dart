import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:comfyui_mobilepocket/ui/widgets/compact_search_field.dart';

/// 把搜索框放进一个页面里跑起来
Future<TextEditingController> _pump(
  WidgetTester tester, {
  bool hasText = false,
  VoidCallback? onClear,
}) async {
  final controller = TextEditingController(text: hasText ? 'abc' : '');
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: CompactSearchField(
          controller: controller,
          hintText: '搜索',
          hasText: hasText,
          onChanged: (_) {},
          onClear: onClear ?? () {},
        ),
      ),
    ),
  );
  return controller;
}

void main() {
  testWidgets('高度锁在 40，不被前置图标的 48 约束撑大', (tester) async {
    await _pump(tester);

    // 这条是核心：输入框的前置图标默认带 48×48 的最小约束，
    // 不处理的话这里会量到 48，搜索框就成了页面上最扎眼的一块。
    final size = tester.getSize(find.byType(TextField));
    expect(size.height, 40);
  });

  testWidgets('提示文字 13 号（与同一行其它文字协调）', (tester) async {
    await _pump(tester);

    final hint = tester.renderObject<RenderParagraph>(find.text('搜索'));
    expect(hint.text.style?.fontSize, 13);
  });

  testWidgets('没输入内容时不显示清除按钮', (tester) async {
    await _pump(tester, hasText: false);
    expect(find.byIcon(Icons.clear), findsNothing);
  });

  testWidgets('有输入内容时才显示清除按钮，点了会回调', (tester) async {
    var cleared = 0;
    await _pump(tester, hasText: true, onClear: () => cleared++);

    expect(find.byIcon(Icons.clear), findsOneWidget);
    await tester.tap(find.byIcon(Icons.clear));
    expect(cleared, 1);
  });

  testWidgets('清除按钮的热区不小于 36（行内可点）', (tester) async {
    await _pump(tester, hasText: true);
    final size = tester.getSize(find.byIcon(Icons.clear));
    expect(size.width >= 17, isTrue);
  });
}
