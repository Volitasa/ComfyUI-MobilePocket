import 'package:flutter_test/flutter_test.dart';

import 'package:comfyui_mobilepocket/services/throttled_image.dart';

/// 并发闸门的契约。
///
/// 这个闸门存在的理由不是"省 CPU"——服务端每张 `preview` 都是同步转码
/// （实测 webp;50 ≈ 216ms），总时间省不掉。它防的是**连接层被自己打爆**：
/// 一次滚出几十个并发连接 → 服务端 backlog 占满 → 客户端超时断开 → Windows RST
/// → `ProactorEventLoop.accept_coro` 抛 WinError 64 → accept loop 终结
/// → 整个 ComfyUI「无法连接」，只能重启。
///
/// 所以下面三条都是真会踩到生产事故的：
/// 1. 同时在飞的数量绝不超过上限；
/// 2. 离开页面时，**还没发出去**的必须作废（否则退出后还在打服务器）；
/// 3. 离开页面时，**已经在飞**的绝不能打断（主动断连 = RST = 触发上面的崩溃）。
void main() {
  group('ImageFetchGate', () {
    test('同时最多放行 maxConcurrent 个，其余排队', () async {
      final gate = ImageFetchGate(maxConcurrent: 3);
      for (var i = 0; i < 3; i++) {
        expect(await gate.acquire('s'), isTrue);
      }
      expect(gate.activeCount, 3);
      expect(gate.waitingCount, 0);

      // 第 4 个必须挂住
      var fourthGranted = false;
      final fourth = gate.acquire('s').then((v) {
        fourthGranted = v;
        return v;
      });
      await Future<void>.delayed(Duration.zero);
      expect(fourthGranted, isFalse, reason: '超额请求不该被放出去');
      expect(gate.waitingCount, 1);

      // 归还一个 → 排队的那个才被放行
      gate.release();
      await fourth;
      expect(fourthGranted, isTrue);
      expect(gate.activeCount, 3);
    });

    test('cancelScope 只作废本页排队的，别页不受影响', () async {
      final gate = ImageFetchGate(maxConcurrent: 1);
      expect(await gate.acquire('A'), isTrue); // 占满

      final samePage = gate.acquire('A'); // 本页排队
      final otherPage = gate.acquire('B'); // 别页排队
      await Future<void>.delayed(Duration.zero);
      expect(gate.waitingCount, 2);

      gate.cancelScope('A');
      expect(await samePage, isFalse, reason: '本页排队的要作废');
      expect(gate.waitingCount, 1);

      gate.release();
      expect(await otherPage, isTrue, reason: '别页排队的要照常放行');
    });

    test('已在飞的不受 cancelScope 影响（不打断 = 不产生 RST）', () async {
      final gate = ImageFetchGate(maxConcurrent: 2);
      expect(await gate.acquire('A'), isTrue);
      expect(await gate.acquire('A'), isTrue);
      expect(gate.activeCount, 2);

      gate.cancelScope('A');

      expect(gate.activeCount, 2, reason: '在飞的不能被强行收掉');
      expect(gate.waitingCount, 0);

      gate.release();
      gate.release();
      expect(gate.activeCount, 0);
    });

    test('作废的名额不会被后续 release 弄乱计数', () async {
      // 被 cancelScope 作废的等待者从未占用名额，
      // 如果实现里提前 +1 再作废，计数会越跑越偏，闸门会永久卡死。
      final gate = ImageFetchGate(maxConcurrent: 1);
      expect(await gate.acquire('A'), isTrue);

      final cancelled = gate.acquire('A');
      await Future<void>.delayed(Duration.zero);
      gate.cancelScope('A');
      expect(await cancelled, isFalse);

      gate.release();
      expect(gate.activeCount, 0);

      // 闸门仍然可用
      expect(await gate.acquire('B'), isTrue);
      expect(gate.activeCount, 1);
    });

    test('默认上限就是一行（3）', () {
      expect(kImageFetchConcurrency, 3);
      expect(ImageFetchGate.instance.maxConcurrent, 3);
    });
  });
}
