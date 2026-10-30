import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:comfyui_mobilepocket/ui/widgets/zoomable_image.dart';

/// 双击要能被识别：两次点击必须落在 kDoubleTapTimeout 之内，
/// 所以中间只 pump 50ms，不是 pumpAndSettle。
Future<void> _doubleTapAt(WidgetTester tester, Offset point) async {
  await tester.tapAt(point);
  await tester.pump(const Duration(milliseconds: 50));
  await tester.tapAt(point);
  // ⚠️ 必须先 pump 一帧再 pump 时长：动画是在这一帧才启动的，
  // 直接 pump(240) 只会得到动画的第 0 帧（scale 仍是 1.0），看起来像"没反应"
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 240));
}

double _scale(WidgetTester tester) => tester
    .widget<InteractiveViewer>(find.byType(InteractiveViewer))
    .transformationController!
    .value
    .getMaxScaleOnAxis();

Future<List<bool>> _pumpZoomable(WidgetTester tester) async {
  final states = <bool>[];
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 300,
            height: 300,
            child: ZoomableImage(
              onZoomChanged: states.add,
              child: Container(color: const Color(0xFF888888)),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return states;
}

void main() {
  testWidgets('双击放大，再双击缩回，并通知外层翻页开关', (tester) async {
    final states = await _pumpZoomable(tester);
    final center = tester.getCenter(find.byType(InteractiveViewer));

    expect(_scale(tester), moreOrLessEquals(1, epsilon: 0.01));

    await _doubleTapAt(tester, center);
    expect(_scale(tester), moreOrLessEquals(2.5, epsilon: 0.01));
    expect(states, [true]);

    await _doubleTapAt(tester, center);
    expect(_scale(tester), moreOrLessEquals(1, epsilon: 0.01));
    expect(states, [true, false]);
  });

  testWidgets('放大锚点是点击处，不是画面中心', (tester) async {
    await _pumpZoomable(tester);
    final topLeft = tester.getTopLeft(find.byType(InteractiveViewer));

    // 故意点右下角：从中心放大的话，这个点会被推到屏幕外
    const tapLocal = Offset(225, 225);
    await _doubleTapAt(tester, topLeft + tapLocal);

    // 先确认真的放大了，否则下面的锚点断言会因为矩阵是单位阵而"假通过"
    expect(_scale(tester), moreOrLessEquals(2.5, epsilon: 0.01));

    final matrix = tester
        .widget<InteractiveViewer>(find.byType(InteractiveViewer))
        .transformationController!
        .value;
    final moved = MatrixUtils.transformPoint(matrix, tapLocal);
    expect(moved.dx, moreOrLessEquals(tapLocal.dx, epsilon: 1));
    expect(moved.dy, moreOrLessEquals(tapLocal.dy, epsilon: 1));
  });
}
