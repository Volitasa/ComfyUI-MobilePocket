import 'package:flutter_test/flutter_test.dart';
import 'package:comfyui_mobilepocket/models/task_history.dart';
import 'package:comfyui_mobilepocket/models/task_status.dart';
import 'package:comfyui_mobilepocket/providers/task_manager.dart';
import 'package:comfyui_mobilepocket/ui/gallery/gallery_view.dart';

TaskHistory _task(
  String id, {
  List<Map<String, dynamic>> images = const [],
  TaskStatus status = TaskStatus.queued,
}) => TaskHistory(
  promptId: id,
  workflowId: 'wf',
  title: 'wf',
  status: status,
  images: images,
);

Map<String, dynamic> _media([String? localPath]) => {
  'filename': 'a.png',
  'type': 'output',
  if (localPath != null) 'localPath': localPath,
};

void main() {
  group('画廊刷新条件', () {
    test('生成中的进度变化不触发刷新', () {
      final prev = TaskState(history: [_task('1')]);
      final next = TaskState(
        history: [_task('1', status: TaskStatus.running)..progressValue = 3],
      );
      expect(galleryDirectoryMayHaveChanged(prev, next), isFalse);
    });

    test('任务标记为已完成但图还没下完，不刷新', () {
      final prev = TaskState(history: [_task('1')]);
      final next = TaskState(
        history: [_task('1', status: TaskStatus.completed)],
      );
      expect(galleryDirectoryMayHaveChanged(prev, next), isFalse);
    });

    test('图片下载完成并登记本地路径后才刷新', () {
      final prev = TaskState(
        history: [_task('1', status: TaskStatus.completed)],
      );
      final next = TaskState(
        history: [
          _task('1', status: TaskStatus.completed, images: [_media('/a.png')]),
        ],
      );
      expect(galleryDirectoryMayHaveChanged(prev, next), isTrue);
    });

    test('记录被删除时刷新（可能连带删了本地图片）', () {
      final prev = TaskState(history: [_task('1'), _task('2')]);
      final next = TaskState(history: [_task('1')]);
      expect(galleryDirectoryMayHaveChanged(prev, next), isTrue);
    });

    test('失败与中断不刷新', () {
      final prev = TaskState(history: [_task('1')]);
      for (final s in [TaskStatus.failed, TaskStatus.interrupted]) {
        expect(
          galleryDirectoryMayHaveChanged(
            prev,
            TaskState(history: [_task('1', status: s)]),
          ),
          isFalse,
        );
      }
    });

    test('首次拿到列表（prev 为 null）不刷新，避免与 initState 重复', () {
      expect(
        galleryDirectoryMayHaveChanged(null, TaskState(history: [_task('1')])),
        isFalse,
      );
    });

    test('新增一条尚未出图的记录不刷新', () {
      final prev = TaskState(history: [_task('1')]);
      final next = TaskState(history: [_task('2'), _task('1')]);
      expect(galleryDirectoryMayHaveChanged(prev, next), isFalse);
    });
  });
}
