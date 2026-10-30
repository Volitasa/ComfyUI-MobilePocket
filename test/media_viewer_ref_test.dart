import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:comfyui_mobilepocket/l10n/app_localizations.dart';

import 'package:comfyui_mobilepocket/services/image_ref.dart';
import 'package:comfyui_mobilepocket/services/reference_image.dart';
import 'package:comfyui_mobilepocket/ui/gallery/history_view.dart';
import 'package:comfyui_mobilepocket/ui/widgets/reference_rail.dart';

/// 1×1 透明 PNG：出图走本地文件，免得测试里发真网络请求。
final Uint8List _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

ReferenceImage _ref(String filename, {String label = '加载图像', String id = '10'}) {
  return ReferenceImage(
    nodeId: id,
    classType: 'LoadImage',
    label: label,
    paramKey: 'image',
    ref: ImageRef(filename: filename),
    fromParams: false,
  );
}

/// rail 里的可点项。必须限定在 ReferenceRail 内 ——
/// `FilledButton` / `IconButton` 内部也是 InkResponse，全局查会混进来。
Finder _railItems() => find.descendant(
  of: find.byType(ReferenceRail),
  matching: find.byType(InkResponse),
);

/// 建一条"出图 + 参考图"的记录并打开查看器。
///
/// [refBaseUrl] 传 null 代表"原服务器已移除"：这时参考图不走网络、直接给占位，
/// 正好让结构类用例不依赖网络。
/// ⚠️ 写文件必须放在 `setUpAll` 里：`testWidgets` 跑在 fake-async 里，
/// 直接 `await` 真实文件 I/O 永远不会返回（整条用例挂死，不是报错）。
/// 出图走本地文件，免得测试里发真网络请求。
late Directory _dir;

Map<String, dynamic> _media(String name) => {
  'filename': name,
  'subfolder': '',
  'type': 'output',
  'localPath': '${_dir.path}/$name',
};

Future<void> _pumpViewer(
  WidgetTester tester, {
  required List<String> outputs,
  List<ReferenceImage> refs = const [],
  String? refBaseUrl,
  Locale locale = const Locale('zh'),
}) async {
  final media = outputs.map(_media).toList();

  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: MediaViewer(
        mediaList: media,
        initialIndex: 0,
        urlBuilder: (m) => 'http://127.0.0.1:1/view?filename=${m['filename']}',
        isVideoChecker: (_) => false,
        referenceImages: refs,
        refBaseUrl: refBaseUrl,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  setUpAll(() async {
    _dir = await Directory.systemTemp.createTemp('media_viewer_test');
    for (final name in ['a.png', 'b.png']) {
      await File('${_dir.path}/$name').writeAsBytes(_png);
    }
  });

  testWidgets('没有参考图时 rail 整条不出现（与加功能之前完全一致）', (tester) async {
    await _pumpViewer(tester, outputs: ['a.png']);
    expect(find.byType(ReferenceRail), findsNothing);
    expect(find.text('1 / 1'), findsOneWidget);
  });

  testWidgets('有参考图时 rail 出现、高 48，且在主按钮上方', (tester) async {
    await _pumpViewer(
      tester,
      outputs: ['a.png', 'b.png'],
      refs: [_ref('face.png'), _ref('cloth.png', label: '衣服', id: '11')],
    );

    expect(find.byType(ReferenceRail), findsOneWidget);
    expect(tester.getSize(find.byType(ReferenceRail)).height, 48);

    final railBottom = tester.getRect(find.byType(ReferenceRail)).bottom;
    final buttonTop = tester.getRect(find.byType(FilledButton)).top;
    expect(railBottom, lessThanOrEqualTo(buttonTop));

    // 分母是总数：2 张出图 + 2 张参考图
    expect(find.text('1 / 4'), findsOneWidget);
  });

  testWidgets('rail 悬浮不占布局：有参考图与没参考图时，主图区尺寸完全一致', (tester) async {
    await _pumpViewer(tester, outputs: ['a.png']);
    final without = tester.getSize(find.byType(PageView));

    await _pumpViewer(tester, outputs: ['a.png'], refs: [_ref('face.png')]);
    final withRefs = tester.getSize(find.byType(PageView));

    // 这条是 2026-10-30 那条"图位置跳一下"的回归闸：rail 一旦回到布局流里，
    // 有参考图的页主图区就被压短，出图与参考图的居中位置会对不上。
    expect(withRefs, without);
  });

  testWidgets('点 rail 里的参考图：跳到那一页，标题变「输入 1 / 2」并显示节点名', (tester) async {
    await _pumpViewer(
      tester,
      outputs: ['a.png'],
      refs: [_ref('face.png'), _ref('cloth.png', label: '衣服', id: '11')],
    );

    // 顺序：出图 → 参考图 1 → 参考图 2
    await tester.tap(_railItems().at(1));
    await tester.pumpAndSettle();

    expect(find.text('输入 1 / 2'), findsOneWidget);
    expect(find.text('加载图像'), findsOneWidget);
  });

  testWidgets('出图页长按主图：临时翻到参考图组**停留过**的那一页，不是永远第一张', (tester) async {
    await _pumpViewer(
      tester,
      outputs: ['a.png'],
      refs: [_ref('face.png'), _ref('cloth.png', label: '衣服', id: '11')],
    );

    // 先在参考图组停到第 2 张，再回出图组
    await tester.tap(_railItems().at(2));
    await tester.pumpAndSettle();
    expect(find.text('输入 2 / 2'), findsOneWidget);
    await tester.tap(_railItems().at(0));
    await tester.pumpAndSettle();
    expect(find.text('1 / 3'), findsOneWidget);

    // 长按主图 → 应看到参考图组的第 2 张（提示条带页码，这是唯一凭证）
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(PageView)),
    );
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('输入 2 / 2 · 松开回到出图'), findsOneWidget);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text('输入 2 / 2 · 松开回到出图'), findsNothing);
  });

  testWidgets('长按 rail 项：主区域临时换成那一张，松手恢复', (tester) async {
    await _pumpViewer(
      tester,
      outputs: ['a.png'],
      refs: [_ref('face.png'), _ref('cloth.png', label: '衣服', id: '11')],
    );

    final gesture = await tester.startGesture(
      tester.getCenter(_railItems().at(2)),
    );
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('输入 2 / 2 · 松开回到出图'), findsOneWidget);

    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text('输入 2 / 2 · 松开回到出图'), findsNothing);
  });

  testWidgets('原服务器已移除时，参考图页给出明确说明而不是一片黑', (tester) async {
    await _pumpViewer(
      tester,
      outputs: ['a.png'],
      refs: [_ref('face.png')],
      refBaseUrl: null,
    );

    await tester.tap(_railItems().at(1));
    await tester.pumpAndSettle();

    expect(find.text('输入 1 / 1'), findsOneWidget);
    expect(find.text('原服务器已移除，无法查看参考图'), findsOneWidget);
  });
}
