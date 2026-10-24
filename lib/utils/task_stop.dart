import 'dart:convert';

/// 停止一个任务的结果。
enum StopOutcome {
  /// 服务器已受理：正在生成的被中断，还在排队的被摘掉。
  stopped,

  /// 服务器上这条已经结束了（取消是一次安全的空操作），顺带对了一次账。
  alreadyDone,

  /// 没连服务器。
  offline,

  /// 请求失败或超时，状态保持原样。
  failed,
}

/// 官方「按任务取消」接口的响应解读。
enum CancelResponse {
  /// {"cancelled": true}：真的取消了。
  stopped,

  /// {"cancelled": false}：任务已结束或 id 未知，接口是幂等空操作。
  alreadyDone,

  /// 不是 200 / 解读不出来 —— 多半是老版本服务器没有这个路由，走降级。
  needFallback,
}

/// 任务在服务器队列里的位置（降级路径用，决定该发哪个请求）。
enum TaskQueueSlot { running, pending, absent }

/// 解读 `POST /api/jobs/{id}/cancel` 的响应。
///
/// 200 + {"cancelled": true} → 取消成功；
/// 200 + {"cancelled": false} → 任务已结束（幂等，不是错误）；
/// 其余（404/405/500/非 JSON）→ 交给降级路径。
CancelResponse parseCancelResponse(int statusCode, String body) {
  if (statusCode != 200) return CancelResponse.needFallback;
  final cancelled = _readCancelled(body);
  if (cancelled == null) return CancelResponse.needFallback;
  return cancelled ? CancelResponse.stopped : CancelResponse.alreadyDone;
}

bool? _readCancelled(String body) {
  try {
    final decoded = jsonDecode(body);
    if (decoded is Map && decoded['cancelled'] is bool) {
      return decoded['cancelled'] as bool;
    }
  } catch (_) {
    // 老版本返回空 body 或 HTML，都按「解读不出来」处理
  }
  return null;
}

/// 判断这条任务当前在服务器的队列里处于什么位置。
///
/// `/queue` 的每一项形如 `[序号, prompt_id, 工作流, 附加数据, 待执行节点]`，
/// 所以按下标 1 取 id。取不到就当它不在队列里（已结束或已丢失）。
TaskQueueSlot classifyQueueSlot(Object? decoded, String promptId) {
  if (decoded is! Map) return TaskQueueSlot.absent;

  for (final item in (decoded['queue_running'] as List? ?? const [])) {
    if (_matches(item, promptId)) return TaskQueueSlot.running;
  }
  for (final item in (decoded['queue_pending'] as List? ?? const [])) {
    if (_matches(item, promptId)) return TaskQueueSlot.pending;
  }
  return TaskQueueSlot.absent;
}

bool _matches(Object? item, String promptId) {
  return item is List && item.length > 1 && item[1].toString() == promptId;
}
