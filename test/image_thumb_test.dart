import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:comfyui_mobilepocket/ui/widgets/image_thumb.dart';
import 'package:comfyui_mobilepocket/ui/widgets/image_viewer.dart';

// 1×1 的 PNG，够小、够真，测试里不需要大图
const _pngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

void main() {
  final png = Uint8List.fromList(base64Decode(_pngBase64));

  Widget wrap(Widget child) {
    return MaterialApp(
      home: Scaffold(body: SizedBox(width: 300, child: child)),
    );
  }

  testWidgets('缩略图是两层：模糊铺底 + 上层完整图', (tester) async {
    await tester.pumpWidget(wrap(ImageThumb(bytes: png)));

    // 两层都要在，只有一层就退化成老样子（裁切或大留白）
    expect(find.byType(Image), findsNWidgets(2));
    expect(find.byType(ImageFiltered), findsOneWidget);
  });

  testWidgets('铺底按 cover 撑满、上层按 contain 完整显示', (tester) async {
    await tester.pumpWidget(wrap(ImageThumb(bytes: png)));

    final images = tester
        .widgetList<Image>(find.byType(Image))
        .map((i) => i.fit)
        .toList();
    expect(images, contains(BoxFit.cover));
    expect(images, contains(BoxFit.contain));

    // 铺底反正是模糊的，解码尺寸要压住，别为一张背景图吃满内存
    final thumb = tester
        .widgetList<Image>(find.byType(Image))
        .firstWhere((i) => i.fit == BoxFit.cover);
    final provider = thumb.image;
    expect(provider, isA<ResizeImage>());
    expect((provider as ResizeImage).width, lessThanOrEqualTo(120));

    // 高度是写死的，卡片才不会跟着图片比例变高变矮
    final box = tester.widget<SizedBox>(
      find.byWidgetPredicate((w) => w is SizedBox && w.height == 120),
    );
    expect(box.height, 120);
  });

  testWidgets('没图时铺底留空，不会盖住破图提示', (tester) async {
    await tester.pumpWidget(
      wrap(ImageThumb(url: 'http://127.0.0.1:1/none.png')),
    );
    await tester.pump();

    // 网络图取不到：铺底层是 SizedBox.shrink，上层才是破图图标
    final ctx = tester.element(find.byType(ImageThumb));
    final images = tester.widgetList<Image>(find.byType(Image)).toList();
    final cover = images.firstWhere((i) => i.fit == BoxFit.cover);
    expect(cover.errorBuilder!(ctx, Object(), null), isA<SizedBox>());
    final contain = images.firstWhere((i) => i.fit == BoxFit.contain);
    expect(contain.errorBuilder!(ctx, Object(), null), isA<Icon>());
  });

  testWidgets('点缩略图会通知外部打开查看器', (tester) async {
    var tapped = 0;
    await tester.pumpWidget(
      wrap(ImageThumb(bytes: png, onTap: () => tapped++)),
    );

    await tester.tap(find.byType(ImageThumb));
    expect(tapped, 1);
  });

  testWidgets('查看器是纯黑底、能缩放、顶栏带文件名', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: FullscreenImageViewer(bytes: png, title: '参考图.png'),
      ),
    );

    expect(find.text('参考图.png'), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsOneWidget);

    final viewer = tester.widget<FullscreenImageViewer>(
      find.byType(FullscreenImageViewer),
    );
    expect(viewer.bytes, png);

    // 看图场景要暗环境，所以这里不跟明暗主题
    final appBar = tester.widget<AppBar>(find.byType(AppBar));
    expect(appBar.backgroundColor, Colors.black);
  });
}
