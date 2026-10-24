import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:comfyui_mobilepocket/providers/gallery_revision_provider.dart';
import 'package:comfyui_mobilepocket/providers/shared_preferences_provider.dart';
import 'package:comfyui_mobilepocket/providers/task_manager.dart';

/// 用给定的历史记录起一个容器（任务历史从 SharedPreferences 读，与 App 一致）。
Future<ProviderContainer> _containerWith(
  List<Map<String, dynamic>> history,
) async {
  SharedPreferences.setMockInitialValues({
    'comfy_task_history': jsonEncode(history),
  });
  final prefs = await SharedPreferences.getInstance();
  return ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  );
}

Map<String, dynamic> _task(
  String id, {
  List<Map<String, dynamic>> images = const [],
}) => {
  'promptId': id,
  'workflowId': 'wf',
  'title': 'wf',
  'status': 'completed',
  'nodePhase': 'done',
  'images': images,
  'timestamp': 1791579799776,
};

Map<String, dynamic> _media(String name, String localPath) => {
  'filename': name,
  'type': 'output',
  'localPath': localPath,
};

void main() {
  group('画廊目录变动计数', () {
    test('初始为 0：刚打开画廊不该被无谓重扫', () async {
      final container = await _containerWith([]);
      addTearDown(container.dispose);

      expect(container.read(galleryRevisionProvider), 0);
    });

    test('删除记录并连带删本地图片后递增（文件确实被删）', () async {
      final dir = await Directory.systemTemp.createTemp('gallery_rev');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/a.png')..writeAsBytesSync([1, 2, 3]);

      final container = await _containerWith([
        _task('p1', images: [_media('a.png', file.path)]),
      ]);
      addTearDown(container.dispose);

      await container
          .read(taskManagerProvider.notifier)
          .removeTask('p1', deleteLocalImages: true);

      expect(file.existsSync(), isFalse);
      expect(container.read(galleryRevisionProvider), 1);
    });

    test('只删记录、保留图片时目录没动，不递增', () async {
      final dir = await Directory.systemTemp.createTemp('gallery_rev');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/a.png')..writeAsBytesSync([1, 2, 3]);

      final container = await _containerWith([
        _task('p1', images: [_media('a.png', file.path)]),
      ]);
      addTearDown(container.dispose);

      await container.read(taskManagerProvider.notifier).removeTask('p1');

      // 保图优先：文件还在，画廊也不必重扫
      expect(file.existsSync(), isTrue);
      expect(container.read(galleryRevisionProvider), 0);
    });

    test('一次删除多张图只递增一次', () async {
      final dir = await Directory.systemTemp.createTemp('gallery_rev');
      addTearDown(() => dir.delete(recursive: true));
      final a = File('${dir.path}/a.png')..writeAsBytesSync([1]);
      final b = File('${dir.path}/b.png')..writeAsBytesSync([2]);

      final container = await _containerWith([
        _task('p1', images: [_media('a.png', a.path), _media('b.png', b.path)]),
      ]);
      addTearDown(container.dispose);

      await container
          .read(taskManagerProvider.notifier)
          .removeTask('p1', deleteLocalImages: true);

      expect(container.read(galleryRevisionProvider), 1);
    });

    test('生成过程中的进度推送不递增', () async {
      final container = await _containerWith([_task('p1')]);
      addTearDown(container.dispose);

      // 进度每秒好几次，跟着全量列目录纯属浪费
      container.read(taskManagerProvider.notifier).updateTaskFromWs({
        'type': 'progress',
        'data': {'prompt_id': 'p1', 'value': 3, 'max': 10},
      });

      expect(container.read(galleryRevisionProvider), 0);
    });
  });
}
