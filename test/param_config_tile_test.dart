import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:comfyui_mobilepocket/ui/widgets/param_config_tile.dart';

Future<void> _pump(
  WidgetTester tester, {
  String alias = 'VAE 模型',
  String summary = '整数 · 10',
  bool exposed = true,
  ValueChanged<bool?>? onChanged,
  TextEditingController? controller,
  ValueChanged<String>? onAliasChanged,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        // 包一层 Column：列表里拿到的是松的竖向约束，直接放 body
        // 会被撑成整屏高，量出来的就不是行高。
        body: Column(
          children: [
            ParamConfigTile(
              summary: summary,
              exposed: exposed,
              onChanged: onChanged ?? (_) {},
              aliasController: controller ?? TextEditingController(text: alias),
              aliasHint: '别名',
              onAliasChanged: onAliasChanged,
            ),
          ],
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('一个参数只占一行 44px，别名只显示一次', (tester) async {
    await _pump(tester);

    final tile = tester.getSize(find.byType(ParamConfigTile));
    // 旧版是勾选行 44 + 别名输入框 36 的两行（≈82）；现在是单行
    expect(tile.height, lessThanOrEqualTo(44));

    // 输入框就是别名的唯一展示位：整屏里只该有一处这段文字
    expect(find.text('VAE 模型'), findsOneWidget);

    // 输入框在行内垂直居中，不能被压成一条缝
    final field = tester.getSize(find.byType(TextField));
    expect(field.height, greaterThanOrEqualTo(28));
  });

  testWidgets('点勾选框切换，点输入框只聚焦不切换', (tester) async {
    final toggles = <bool?>[];
    await _pump(tester, exposed: false, onChanged: toggles.add);

    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    expect(toggles, [true]);

    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    // 输入框只获取焦点，不产生新的勾选事件
    expect(toggles.length, 1);
  });

  testWidgets('别名输入框常显并可编辑', (tester) async {
    final controller = TextEditingController(text: 'VAE 模型');
    final edits = <String>[];
    await _pump(
      tester,
      exposed: false,
      controller: controller,
      onAliasChanged: edits.add,
    );

    // 未勾选也照样在（运行页的字段标签就是它，不能藏）
    expect(find.byType(TextField), findsOneWidget);

    await tester.enterText(find.byType(TextField), '换脸模型');
    expect(controller.text, '换脸模型');
    // 保存配置用的是 node.alias，控制器文本必须回写出去
    expect(edits, ['换脸模型']);
  });

  testWidgets('编辑别名时把行尾摘要让出去', (tester) async {
    await _pump(tester, summary: '整数 · 10');
    expect(find.text('整数 · 10'), findsOneWidget);

    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();

    // 正在改名字，这时候腾出的宽度比读当前值有用
    expect(find.text('整数 · 10'), findsNothing);
  });

  testWidgets('行尾标得下「节点 · 当前值」，比原来的类型摘要宽', (tester) async {
    const summary = 'CLIP文本编码 · masterpiece, 低质量, 模糊';
    await _pump(tester, summary: summary);

    // 原来上限 120，只够「类型: 整数 · 当前值: 20」这种短句；
    // 换成节点名 + 当前值后必须放宽，否则永远看到半截
    final width = tester.getSize(find.text(summary)).width;
    expect(width, greaterThan(120));

    // 宽也有个上限：别名还得留在屏上
    expect(width, lessThanOrEqualTo(168));
  });

  testWidgets('别名与当前值都超长也不报错，各自截断', (tester) async {
    await _pump(
      tester,
      alias: '这是一个非常非常长的参数别名用来测试截断行为是否会溢出屏幕',
      summary: 'ultrafluxVAEImprovedVersionFinalReallyLongFileName',
    );

    expect(tester.takeException(), isNull);
  });
}
