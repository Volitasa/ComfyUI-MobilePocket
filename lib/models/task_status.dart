/// 任务的五种状态。
///
/// 以前这里存的是中文明文（'排队中' / '已完成'…），还被 UI 直接拿来判等，
/// 一旦界面换语言，旧记录与新记录就对不上。现在持久化只存枚举名，
/// 展示文案在渲染时才按当前语言生成。
enum TaskStatus {
  queued, // 排队中：已提交，还没开始执行
  running, // 生成中：正在执行
  completed, // 已完成
  failed, // 已失败
  interrupted; // 已中断

  /// 终结态：任务已经结束，不会再有新的输出或状态变化。
  bool get isTerminal => switch (this) {
        TaskStatus.completed || TaskStatus.failed || TaskStatus.interrupted => true,
        TaskStatus.queued || TaskStatus.running => false,
      };

  /// 非终结态：仍可能收到服务端推送。
  bool get isPending => !isTerminal;

  String get storageKey => name;
}

/// 任务当前所处的执行阶段：比状态更细，决定列表里第二行显示什么。
///
/// 同样只存枚举名，动态部分（节点名、服务端错误原文）单独存 [TaskHistory.nodeDetail]。
enum TaskNodePhase {
  waiting, // 等待服务端开始执行
  started, // 收到 execution_start
  cached, // 命中节点缓存
  running, // 正在执行某节点（进度与节点名在别处）
  done, // 正常结束
  error, // 执行出错（nodeDetail 为服务端错误原文，可能为空）
  interrupted, // 被用户中断
  lost, // 服务端重启或任务丢失，对账时找不到
  parseFailed; // 本地解析服务端返回的结果失败

  String get storageKey => name;
}

/// 旧版本写进 SharedPreferences 的中文状态值 → 枚举。
/// 读到无法识别的值（含已损坏数据）时按 [TaskStatus.queued] 兜底，至少不崩。
TaskStatus taskStatusFromStorage(Object? raw) {
  switch (raw) {
    case 'running':
      return TaskStatus.running;
    case 'completed':
      return TaskStatus.completed;
    case 'failed':
      return TaskStatus.failed;
    case 'interrupted':
      return TaskStatus.interrupted;
    case 'queued':
      return TaskStatus.queued;
    // 以下是旧版中文明文，升级后读到时映射一次即可
    case '生成中':
      return TaskStatus.running;
    case '已完成':
      return TaskStatus.completed;
    case '已失败':
      return TaskStatus.failed;
    case '已中断':
      return TaskStatus.interrupted;
    case '排队中':
      return TaskStatus.queued;
    default:
      return TaskStatus.queued;
  }
}

/// 旧记录的 phase 丢失了（只存过整句中文），按状态推断一个最接近的。
TaskNodePhase taskPhaseFromStatus(TaskStatus status) => switch (status) {
      TaskStatus.completed => TaskNodePhase.done,
      TaskStatus.failed => TaskNodePhase.error,
      TaskStatus.interrupted => TaskNodePhase.interrupted,
      TaskStatus.running => TaskNodePhase.running,
      TaskStatus.queued => TaskNodePhase.waiting,
    };

/// 从持久化值还原阶段；缺失时退回按状态推断。
TaskNodePhase taskPhaseFromStorage(Object? raw, TaskStatus status) {
  for (final p in TaskNodePhase.values) {
    if (p.name == raw) return p;
  }
  return taskPhaseFromStatus(status);
}
