import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:comfyui_mobilepocket/utils/task_stop.dart';

/// `/queue` 的一项：形如 [序号, prompt_id, 工作流, 附加数据, 待执行节点]。
List<dynamic> _item(String promptId) => [42, promptId, {}, {}, []];

void main() {
  group('停止任务的响应解读', () {
    test('服务器受理了取消', () {
      expect(
        parseCancelResponse(200, jsonEncode({'cancelled': true})),
        CancelResponse.stopped,
      );
    });

    test('任务已结束：接口是幂等空操作，不是错误', () {
      expect(
        parseCancelResponse(200, jsonEncode({'cancelled': false})),
        CancelResponse.alreadyDone,
      );
    });

    test('老服务器没有这个路由（404/405）→ 走降级', () {
      expect(parseCancelResponse(404, ''), CancelResponse.needFallback);
      expect(
        parseCancelResponse(405, 'Method Not Allowed'),
        CancelResponse.needFallback,
      );
    });

    test('200 但解读不出 cancelled → 保守降级', () {
      expect(parseCancelResponse(200, ''), CancelResponse.needFallback);
      expect(parseCancelResponse(200, '<html>'), CancelResponse.needFallback);
      expect(
        parseCancelResponse(200, jsonEncode({'foo': 1})),
        CancelResponse.needFallback,
      );
      // 字段类型不对也不能当成成功
      expect(
        parseCancelResponse(200, jsonEncode({'cancelled': 'yes'})),
        CancelResponse.needFallback,
      );
    });
  });

  group('任务在队列里的位置', () {
    test('正在生成', () {
      final queue = {
        'queue_running': [_item('p1')],
        'queue_pending': [],
      };
      expect(classifyQueueSlot(queue, 'p1'), TaskQueueSlot.running);
    });

    test('还在排队', () {
      final queue = {
        'queue_running': [_item('other')],
        'queue_pending': [_item('p2'), _item('p3')],
      };
      expect(classifyQueueSlot(queue, 'p3'), TaskQueueSlot.pending);
    });

    test('都不在：已结束或已丢失', () {
      final queue = {
        'queue_running': [_item('other')],
        'queue_pending': [_item('p2')],
      };
      expect(classifyQueueSlot(queue, 'p1'), TaskQueueSlot.absent);
      expect(classifyQueueSlot({}, 'p1'), TaskQueueSlot.absent);
    });

    test('结构异常时不误判', () {
      expect(classifyQueueSlot(null, 'p1'), TaskQueueSlot.absent);
      expect(classifyQueueSlot('不是 JSON 对象', 'p1'), TaskQueueSlot.absent);
      expect(
        classifyQueueSlot({
          'queue_running': ['坏数据', 1],
          'queue_pending': null,
        }, 'p1'),
        TaskQueueSlot.absent,
      );
    });
  });
}
