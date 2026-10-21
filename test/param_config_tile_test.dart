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
              alias: alias,
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
  testWidgets('一个参数只占 80px：勾选行 44 + 别名框 36', (tester) async {
    await _pump(tester);

    final tile = tester.getSize(find.byType(ParamConfigTile));
    // 旧版：勾选行 48 + 副标题 + 缩进 40 的输入框 44 ≈ 104，这里必须明显更矮
    expect(tile.height, lessThanOrEqualTo(82));

    // 输入框压到 36，同时不能压到点不进去
    final field = tester.getSize(find.byType(TextField));
    expect(field.height, lessThanOrEqualTo(40));
  });

  testWidgets('点整行切换勾选，点输入框不切换', (tester) async {
    final toggles = <bool?>[];
    await _pump(tester, exposed: false, onChanged: toggles.add);

    // 点整行（别名文字与输入框里都有这四个字，不能直接按文字定位）
    await tester.tap(find.byType(InkWell));
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

  testWidgets('别名与当前值都超长也不报错，各自截断', (tester) async {
    await _pump(
      tester,
      alias: '这是一个非常非常长的参数别名用来测试截断行为是否会溢出屏幕',
      summary: 'ultrafluxVAEImprovedVersionFinalReallyLongFileName',
    );

    expect(tester.takeException(), isNull);
  });
}
