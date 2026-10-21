import 'package:flutter_test/flutter_test.dart';
import 'package:comfyui_mobilepocket/models/task_history.dart';
import 'package:comfyui_mobilepocket/utils/workflow_last_run.dart';

TaskHistory _task(String workflowId, int timestamp, {String promptId = 'p'}) =>
    TaskHistory(
      promptId: promptId,
      workflowId: workflowId,
      title: '',
      timestamp: timestamp,
    );

void main() {
  group('上次运行时间', () {
    test('一条都没跑过 → null', () {
      expect(lastRunTimeOf(const <TaskHistory>[], 'a.json'), isNull);
    });

    test('只有别的记录 → null', () {
      expect(lastRunTimeOf([_task('b.json', 1000)], 'a.json'), isNull);
    });

    test('只有一条 → 取它', () {
      expect(lastRunTimeOf([_task('a.json', 1000)], 'a.json'), 1000);
    });

    test('多条 → 取最新的那条，与记录顺序无关', () {
      final history = [
        _task('a.json', 3000, promptId: 'p3'),
        _task('a.json', 1000, promptId: 'p1'),
        _task('b.json', 5000, promptId: 'p5'),
        _task('a.json', 2000, promptId: 'p2'),
      ];
      expect(lastRunTimeOf(history, 'a.json'), 3000);
      expect(lastRunTimeOf(history, 'b.json'), 5000);
    });

    test('记录顺序倒过来结果也一样', () {
      final history = [
        _task('a.json', 1000),
        _task('a.json', 3000),
        _task('a.json', 2000),
      ];
      expect(lastRunTimeOf(history, 'a.json'), 3000);
    });

    test('空 id 也照常匹配（不该崩溃）', () {
      expect(lastRunTimeOf([_task('', 1000)], ''), 1000);
    });
  });
}
