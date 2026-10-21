import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:comfyui_mobilepocket/ui/widgets/workflow_tile.dart';

Future<void> _pump(
  WidgetTester tester, {
  String status = '已配置 6 项',
  String footnote = '上次运行 10-15 18:53',
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        // 包一层 Column：它在列表里拿到的竖向约束是松的，
        // 直接放在 body 里会被撑成整屏高，量出来的高度就不是行高。
        body: Column(
          children: [
            WorkflowTile(
              title: 'Krea2换装工作流',
              statusLabel: status,
              footnote: footnote,
              menu: const Icon(Icons.more_vert),
              onTap: () {},
            ),
          ],
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('一屏放得下的行数翻倍，同时点得中', (tester) async {
    await _pump(tester);

    // 含卡片之间的 6px 间距：旧版是 85 高 + 16 间距 = 101，一屏 6 个
    final pitch = tester.getSize(find.byType(Card)).height;
    expect(pitch, lessThan(58));

    // 压高度不能把点击热区压没了（安卓最小 48dp，这里留 1px 余量）
    final tapArea = tester.getSize(find.byType(InkWell).first).height;
    expect(tapArea, greaterThan(45));
  });

  testWidgets('名字与状态在第一行，上次运行时间在第二行', (tester) async {
    await _pump(tester);

    expect(find.text('Krea2换装工作流'), findsOneWidget);
    expect(find.text('已配置 6 项'), findsOneWidget);
    expect(find.text('上次运行 10-15 18:53'), findsOneWidget);
  });

  testWidgets('没跑过的工作流显示「尚未运行」', (tester) async {
    await _pump(tester, status: '未配置', footnote: '尚未运行');

    expect(find.text('尚未运行'), findsOneWidget);
  });

  testWidgets('名字过长时截断，不把状态挤出屏幕', (tester) async {
    await _pump(tester);

    final title = tester.widget<Text>(find.text('Krea2换装工作流'));
    expect(title.maxLines, 1);
    expect(title.overflow, TextOverflow.ellipsis);
  });

  testWidgets('没有菜单按钮时也不会崩', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [WorkflowTile(title: '测试1', statusLabel: '未配置')],
          ),
        ),
      ),
    );

    expect(find.text('测试1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
