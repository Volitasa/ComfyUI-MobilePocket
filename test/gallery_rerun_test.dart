import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:comfyui_mobilepocket/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:comfyui_mobilepocket/providers/shared_preferences_provider.dart';
import 'package:comfyui_mobilepocket/providers/task_manager.dart';
import 'package:comfyui_mobilepocket/services/gallery_store.dart';
import 'package:comfyui_mobilepocket/ui/gallery/gallery_view.dart';
import 'package:comfyui_mobilepocket/ui/widgets/reference_rail.dart';

/// 1×1 透明 PNG
final Uint8List _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

late Directory _galleryDir;

/// 画廊里那张图的真实路径（分隔符跟 `dir.list()` 保持一致）
String get _outPath => '${_galleryDir.path}${Platform.pathSeparator}out.png';

/// 一条"有快照、带一张图、喂过一张参考图"的记录。
Map<String, dynamic> _historyJson(String localPath) => {
  'promptId': 'p1',
  'workflowId': 'wf.json',
  'title': 'wf',
  'status': 'completed',
  'nodePhase': 'done',
  'snapshotId': 'snap1',
  'params': <String, dynamic>{},
  'images': [
    {'filename': 'out.png', 'type': 'output', 'localPath': localPath},
  ],
  'timestamp': 1791579799776,
};

Map<String, dynamic> _snapshotJson() => {
  'id': 'snap1',
  'sourceName': 'wf',
  'createdAt': 1791579799776,
  'workflowJson': {
    '10': {
      'class_type': 'LoadImage',
      'inputs': {'image': 'face.png'},
      '_meta': {'title': '加载图像'},
    },
    '20': {
      'class_type': 'KSampler',
      'inputs': {'seed': 1},
    },
  },
  'mappingConfig': <dynamic>[],
};

/// 打开画廊并点开第一张图。
///
/// ⚠️ 列表要真的读磁盘，必须用 `runAsync` 把真实 I/O 放回真 async 区跑一次，
/// 否则 `tester.pump()` 里那批 future 永远不完成（页面停在骨架屏）。
Future<void> _openFirstImage(
  WidgetTester tester,
  List<Map<String, dynamic>> history, {
  bool withSnapshot = true,
}) async {
  SharedPreferences.setMockInitialValues({
    'comfy_history_placeholder': '', // 占位：确保 mock 生效
    'comfy_task_history': jsonEncode(history),
    if (withSnapshot) 'comfy_workflow_snapshots': jsonEncode([_snapshotJson()]),
  });
  final prefs = await tester.runAsync(() => SharedPreferences.getInstance());

  // ⚠️ pumpWidget 必须在 runAsync 里：initState 里那次列目录是真实 I/O，
  // 在 fake-async 区里起的 future 不会前进，页面会永远停在骨架屏。
  await tester.runAsync(() async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs!)],
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const GalleryView(),
        ),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 200));
  });
  await tester.pump();

  expect(find.byType(Hero), findsWidgets, reason: '画廊里应该有图才能点开');
  await tester.tap(find.byType(Hero).first);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  setUpAll(() async {
    final root = await Directory.systemTemp.createTemp('gallery_rerun_test');
    _galleryDir = Directory('${root.path}/comfy_gallery');
    await _galleryDir.create(recursive: true);
    await File('${_galleryDir.path}${Platform.pathSeparator}out.png')
        .writeAsBytes(_png);
  });

  setUp(() {
    GalleryStore.debugDirectoryOverride = _galleryDir.parent;
    GalleryStore.instance.resetCachedDir();
  });

  testWidgets('能反查到记录且快照还在：出现「再次运行」，并带出参考图 rail', (tester) async {
    await _openFirstImage(tester, [_historyJson(_outPath)]);

    // 查看器确实打开了
    expect(find.text('保存到相册'), findsOneWidget);
    // 「再次运行」按 tooltip 断言，不依赖图标码点
    expect(find.byTooltip('再次运行'), findsOneWidget);
    expect(find.byType(ReferenceRail), findsOneWidget);
  });

  testWidgets('反查不到记录（记录已删）：两个入口都不出现，也不置灰', (tester) async {
    // 记录里的 localPath 指向别处，与画廊里这张图对不上
    await _openFirstImage(tester, [_historyJson('/nonexistent/other.png')]);

    expect(find.byTooltip('再次运行'), findsNothing);
    expect(find.byType(ReferenceRail), findsNothing);
  });

  testWidgets('快照被删了：即使反查到记录也不给再次运行', (tester) async {
    await _openFirstImage(
      tester,
      [_historyJson(_outPath)],
      withSnapshot: false,
    );

    expect(find.byTooltip('再次运行'), findsNothing);
  });

  test('taskByLocalPath：命中返回记录，未命中返回 null', () async {
    SharedPreferences.setMockInitialValues({
      'comfy_task_history': jsonEncode([
        _historyJson('/gallery/a.png'),
      ]),
    });
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);

    final notifier = container.read(taskManagerProvider.notifier);
    expect(notifier.taskByLocalPath('/gallery/a.png')?.promptId, 'p1');
    expect(notifier.taskByLocalPath('/gallery/b.png'), isNull);
  });
}
