import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:comfyui_mobilepocket/l10n/app_localizations.dart';

import 'package:comfyui_mobilepocket/models/task_history.dart';
import 'package:comfyui_mobilepocket/models/task_status.dart';
import 'package:comfyui_mobilepocket/providers/connection_provider.dart';
import 'package:comfyui_mobilepocket/ui/settings/server_config_view.dart';
import 'package:comfyui_mobilepocket/utils/task_display.dart';

AppLocalizations _zh() => lookupAppLocalizations(const Locale('zh'));
AppLocalizations _en() => lookupAppLocalizations(const Locale('en'));

void main() {
  group('状态持久化值', () {
    test('新版存枚举名', () {
      expect(taskStatusFromStorage('queued'), TaskStatus.queued);
      expect(taskStatusFromStorage('running'), TaskStatus.running);
      expect(taskStatusFromStorage('completed'), TaskStatus.completed);
      expect(taskStatusFromStorage('failed'), TaskStatus.failed);
      expect(taskStatusFromStorage('interrupted'), TaskStatus.interrupted);
    });

    test('旧版中文值能迁移回来', () {
      expect(taskStatusFromStorage('排队中'), TaskStatus.queued);
      expect(taskStatusFromStorage('生成中'), TaskStatus.running);
      expect(taskStatusFromStorage('已完成'), TaskStatus.completed);
      expect(taskStatusFromStorage('已失败'), TaskStatus.failed);
      expect(taskStatusFromStorage('已中断'), TaskStatus.interrupted);
    });

    test('认不出来的值兜底为排队中，不抛异常', () {
      expect(taskStatusFromStorage(null), TaskStatus.queued);
      expect(taskStatusFromStorage('???'), TaskStatus.queued);
    });

    test('终结态只有三种，进行中的两种不是', () {
      expect(TaskStatus.completed.isTerminal, isTrue);
      expect(TaskStatus.failed.isTerminal, isTrue);
      expect(TaskStatus.interrupted.isTerminal, isTrue);
      expect(TaskStatus.queued.isTerminal, isFalse);
      expect(TaskStatus.running.isTerminal, isFalse);
      expect(TaskStatus.running.isPending, isTrue);
    });
  });

  group('TaskHistory 序列化', () {
    test('枚举与详情往返一致', () {
      final task = TaskHistory(
        promptId: 'p1',
        workflowId: 'w1',
        title: 't1',
        status: TaskStatus.failed,
        nodePhase: TaskNodePhase.error,
        nodeDetail: 'boom',
      );

      final json = task.toJson();
      expect(json['status'], 'failed');
      expect(json['nodePhase'], 'error');
      expect(json['nodeDetail'], 'boom');

      final restored = TaskHistory.fromJson(json);
      expect(restored.status, TaskStatus.failed);
      expect(restored.nodePhase, TaskNodePhase.error);
      expect(restored.nodeDetail, 'boom');
    });

    test('旧版中文记录：状态迁移、错误详情从整句里捞回来', () {
      final restored = TaskHistory.fromJson({
        'promptId': 'p1',
        'workflowId': 'w1',
        'title': 't1',
        'status': '已失败',
        'nodeInfo': '❌ 执行出错: value out of range',
      });

      expect(restored.status, TaskStatus.failed);
      expect(restored.nodePhase, TaskNodePhase.error);
      expect(restored.nodeDetail, 'value out of range');
    });

    test('旧版无错误详情的记录：详情留空而不是塞进整句中文', () {
      final restored = TaskHistory.fromJson({
        'promptId': 'p1',
        'workflowId': 'w1',
        'title': 't1',
        'status': '已完成',
        'nodeInfo': '✅ 生成成功',
      });

      expect(restored.status, TaskStatus.completed);
      expect(restored.nodePhase, TaskNodePhase.done);
      expect(restored.nodeDetail, isEmpty);
    });
  });

  group('同一条记录按当前语言渲染', () {
    test('状态与阶段文案随语言变化', () {
      final task = TaskHistory(
        promptId: 'p1',
        workflowId: 'w1',
        title: 't1',
        status: TaskStatus.running,
        nodePhase: TaskNodePhase.running,
        nodeDetail: 'KSampler',
        progressValue: 3,
        progressMax: 10,
      );

      expect(taskStatusLabel(_zh(), task.status), '生成中');
      expect(taskStatusLabel(_en(), task.status), 'Running');
      // 节点名与百分比与语言无关，两种语言下都要出现
      expect(taskNodeText(_zh(), task), contains('KSampler'));
      expect(taskNodeText(_zh(), task), contains('30%'));
      expect(taskNodeText(_en(), task), contains('KSampler'));
      expect(taskNodeText(_en(), task), contains('30%'));
    });

    test('错误详情为空时不编造内容', () {
      final task = TaskHistory(
        promptId: 'p1',
        workflowId: 'w1',
        title: 't1',
        status: TaskStatus.failed,
        nodePhase: TaskNodePhase.error,
      );

      expect(taskNodeText(_zh(), task), '执行出错');
      expect(taskNodeText(_en(), task), 'Execution failed');
    });
  });

  group('连接探测结果', () {
    test('结果只描述事实，文案按语言生成', () {
      const result = ConnectionTestResult(
        ok: true,
        kind: ConnectionTestKind.activatedPrimary,
        name: '家里内网',
      );

      expect(testResultText(_zh(), result), contains('家里内网'));
      expect(testResultText(_zh(), result), contains('主地址'));
      expect(testResultText(_en(), result), contains('家里内网'));
      expect(testResultText(_en(), result), contains('primary'));
    });

    test('失败结果的 ok 为 false，颜色据此决定而非文案内容', () {
      const result = ConnectionTestResult(
        ok: false,
        kind: ConnectionTestKind.activateFailed,
        name: '公司外网',
      );

      expect(result.ok, isFalse);
      // 英文文案里根本没有「不可用」三个字，UI 不能再靠 contains 判断
      expect(testResultText(_en(), result), isNot(contains('不可用')));
    });
  });
}
