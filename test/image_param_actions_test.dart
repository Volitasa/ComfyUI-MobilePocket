import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:comfyui_mobilepocket/ui/widgets/image_param_actions.dart';

/// 右列宽度只有卡片的两成（左右布局里 flex 2/5 再减去间距，实测约 130）。
const _width = 130.0;

void main() {
  Widget wrap(Widget child) {
    return MaterialApp(
      home: Scaffold(
        body: Center(child: SizedBox(width: _width, child: child)),
      ),
    );
  }

  testWidgets('长文件名 + 两颗按钮也不溢出（曾经溢出 27px）', (tester) async {
    await tester.pumpWidget(
      wrap(
        ImageParamActions(
          // image_picker 存下来的名字就这么长，实测把右列撑破过
          filename: 'JPEG_20261028_193938_4660741988535994963.jpg',
          sourceLabel: '本地 · 待上传',
          primaryLabel: '更换图片',
          onPrimary: () {},
          secondaryLabel: '用原图',
          onSecondary: () {},
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('两颗按钮时文件名只占一行，一颗时允许两行', (tester) async {
    Text nameText() => tester.widget<Text>(find.text('a_very_long_file_name.png'));

    await tester.pumpWidget(
      wrap(
        ImageParamActions(
          filename: 'a_very_long_file_name.png',
          sourceLabel: '服务器 · 已有',
          primaryLabel: '选择图片',
          onPrimary: () {},
          secondaryLabel: '用原图',
          onSecondary: () {},
        ),
      ),
    );
    expect(nameText().maxLines, 1);

    await tester.pumpWidget(
      wrap(
        ImageParamActions(
          filename: 'a_very_long_file_name.png',
          sourceLabel: '服务器 · 已有',
          primaryLabel: '选择图片',
          onPrimary: () {},
        ),
      ),
    );
    expect(nameText().maxLines, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('没图时显示占位文案且不显示来源行', (tester) async {
    await tester.pumpWidget(
      wrap(
        ImageParamActions(
          filename: null,
          placeholder: '未选择图片',
          sourceLabel: '服务器 · 已有',
          primaryLabel: '选择图片',
          onPrimary: () {},
        ),
      ),
    );

    expect(find.text('未选择图片'), findsOneWidget);
    expect(find.text('服务器 · 已有'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('按钮点击各自回调，不会互相串', (tester) async {
    var primary = 0;
    var secondary = 0;
    await tester.pumpWidget(
      wrap(
        ImageParamActions(
          filename: 'x.png',
          sourceLabel: '本地 · 待上传',
          primaryLabel: '更换图片',
          onPrimary: () => primary++,
          secondaryLabel: '用原图',
          onSecondary: () => secondary++,
        ),
      ),
    );

    await tester.tap(find.text('更换图片'));
    await tester.tap(find.text('用原图'));
    expect(primary, 1);
    expect(secondary, 1);
  });
}
