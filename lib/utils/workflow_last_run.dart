import '../models/task_history.dart';

/// 某个工作流最后一次运行的时间戳（毫秒）；一次都没跑过返回 null。
///
/// 纯函数，不依赖界面，便于单测。
int? lastRunTimeOf(Iterable<TaskHistory> history, String workflowId) {
  int? best;
  for (final t in history) {
    if (t.workflowId != workflowId) continue;
    if (best == null || t.timestamp > best) best = t.timestamp;
  }
  return best;
}
