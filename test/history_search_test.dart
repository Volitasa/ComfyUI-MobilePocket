import 'package:flutter_test/flutter_test.dart';
import 'package:comfyui_mobilepocket/models/task_history.dart';
import 'package:comfyui_mobilepocket/models/task_status.dart';
import 'package:comfyui_mobilepocket/models/workflow_node.dart';
import 'package:comfyui_mobilepocket/models/workflow_snapshot.dart';
import 'package:comfyui_mobilepocket/utils/history_search.dart';

TaskHistory _task({
  required String id,
  required String title,
  Map<String, dynamic>? params,
  TaskStatus status = TaskStatus.completed,
  String? snapshotId,
}) => TaskHistory(
  promptId: id,
  workflowId: 'wf_$id',
  title: title,
  status: status,
  params: params,
  snapshotId: snapshotId,
  timestamp: 1000,
);

WorkflowSnapshot _snapshot(String id, List<WorkflowNode> config) =>
    WorkflowSnapshot(
      id: id,
      sourceName: 'wf',
      createdAt: 1000,
      workflowJson: const {},
      mappingConfig: config,
    );

WorkflowNode _node(String id, String key, String alias) =>
    WorkflowNode(id: id, classType: 'CLIPTextEncode', key: key, alias: alias);

void main() {
  group('HistorySearch.search', () {
    test('关键词为空时原样返回全部，且不产生摘要', () {
      final tasks = [
        _task(id: 'a', title: '基础文生图', params: {'3:text': '一只猫'}),
        _task(id: 'b', title: '换装', params: {'4:text': '一只狗'}),
      ];
      final hits = HistorySearch.search(tasks, '', displayName: (t) => t.title);
      expect(hits.length, 2);
      expect(hits.every((h) => h.summary == null), isTrue);
    });

    test('按工作流名能搜到，且不重复生成摘要', () {
      final tasks = [
        _task(id: 'a', title: '视频换脸', params: {'3:text': 'abc'}),
      ];
      final hits = HistorySearch.search(
        tasks,
        '换脸',
        displayName: (t) => t.title,
      );
      expect(hits.length, 1);
      expect(hits.first.summary, isNull);
    });

    test('按填入的文本能搜到，并给出摘要', () {
      final tasks = [
        _task(id: 'a', title: '基础文生图', params: {'3:text': '阳光下一只猫咪在窗台'}),
      ];
      final hits = HistorySearch.search(
        tasks,
        '猫',
        displayName: (t) => t.title,
      );
      expect(hits.length, 1);
      expect(hits.first.summary, contains('猫'));
    });

    test('大小写不敏感', () {
      final tasks = [
        _task(id: 'a', title: 'wf', params: {'3:text': 'Masterpiece'}),
      ];
      final hits = HistorySearch.search(
        tasks,
        'masterpiece',
        displayName: (t) => t.title,
      );
      expect(hits.length, 1);
    });

    test('多个关键词是与关系，且须落在同一字段', () {
      final same = _task(id: 'a', title: 'wf', params: {'3:text': '一只猫咪在窗台'});
      final split = _task(
        id: 'b',
        title: 'wf',
        params: {'3:text': '一只猫咪', '5:text': '在窗台'},
      );
      expect(
        HistorySearch.search(
          [same],
          '猫 窗台',
          displayName: (t) => t.title,
        ).length,
        1,
      );
      // 两个词分散在不同参数里，不算命中
      expect(
        HistorySearch.search([split], '猫 窗台', displayName: (t) => t.title),
        isEmpty,
      );
    });

    test('数值参数不参与匹配', () {
      final tasks = [
        _task(id: 'a', title: 'wf', params: {'3:steps': 7, '3:cfg': 7}),
      ];
      expect(
        HistorySearch.search(tasks, '7', displayName: (t) => t.title),
        isEmpty,
      );
    });

    test('旧记录 params 为空时不崩，只能按名称搜', () {
      final tasks = [_task(id: 'a', title: '旧记录', params: null)];
      expect(
        HistorySearch.search(tasks, '旧记录', displayName: (t) => t.title).length,
        1,
      );
      expect(
        HistorySearch.search(tasks, '任意内容', displayName: (t) => t.title),
        isEmpty,
      );
    });

    test('快照存在时别名一起搜，摘要带上别名', () {
      final tasks = [
        _task(
          id: 'a',
          title: 'wf',
          params: {'3:text': '一只猫咪'},
          snapshotId: 'snap1',
        ),
      ];
      final snap = _snapshot('snap1', [_node('3', 'text', '正面提示词')]);
      final hits = HistorySearch.search(
        tasks,
        '提示词',
        displayName: (t) => t.title,
        snapshotOf: (id) => id == 'snap1' ? snap : null,
      );
      expect(hits.length, 1);
      expect(hits.first.summary, startsWith('正面提示词'));
    });

    test('快照被删时降级：只匹配值，摘要不带别名', () {
      final tasks = [
        _task(
          id: 'a',
          title: 'wf',
          params: {'3:text': '一只猫咪'},
          snapshotId: 'snap1',
        ),
      ];
      final hits = HistorySearch.search(
        tasks,
        '猫',
        displayName: (t) => t.title,
        snapshotOf: (_) => null,
      );
      expect(hits.length, 1);
      expect(hits.first.summary, contains('猫'));
      expect(hits.first.summary, isNot(contains('正面提示词')));
    });

    test('展示名参与匹配：title 为空但补了默认名的记录也能搜到', () {
      final tasks = [
        _task(id: 'a', title: '', params: {'3:text': 'abc'}),
      ];
      // 模拟展示层补出来的默认名
      final hits = HistorySearch.search(
        tasks,
        'Local import',
        displayName: (_) => 'Local import',
      );
      expect(hits.length, 1);
    });
  });

  group('HistorySearch.passesFilter', () {
    test('all 放行一切', () {
      for (final s in TaskStatus.values) {
        expect(HistorySearch.passesFilter(HistoryStatusFilter.all, s), isTrue);
      }
    });

    test('pending 合并排队与生成', () {
      expect(
        HistorySearch.passesFilter(
          HistoryStatusFilter.pending,
          TaskStatus.queued,
        ),
        isTrue,
      );
      expect(
        HistorySearch.passesFilter(
          HistoryStatusFilter.pending,
          TaskStatus.running,
        ),
        isTrue,
      );
      expect(
        HistorySearch.passesFilter(
          HistoryStatusFilter.pending,
          TaskStatus.completed,
        ),
        isFalse,
      );
    });

    test('各筛选只放行对应状态', () {
      expect(
        HistorySearch.passesFilter(
          HistoryStatusFilter.completed,
          TaskStatus.completed,
        ),
        isTrue,
      );
      expect(
        HistorySearch.passesFilter(
          HistoryStatusFilter.failed,
          TaskStatus.completed,
        ),
        isFalse,
      );
      expect(
        HistorySearch.passesFilter(
          HistoryStatusFilter.interrupted,
          TaskStatus.interrupted,
        ),
        isTrue,
      );
    });
  });
}
