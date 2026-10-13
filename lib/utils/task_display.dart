import 'package:comfyui_mobilepocket/l10n/app_localizations.dart';

import '../models/task_history.dart';
import '../models/task_status.dart';

/// 状态与阶段的展示文案统一在这里生成：持久化层只存枚举与原始值，
/// 界面语言切换后，同一条记录会按新语言重新渲染。
String taskStatusLabel(AppLocalizations l, TaskStatus status) =>
    switch (status) {
      TaskStatus.queued => l.taskStatusQueued,
      TaskStatus.running => l.taskStatusRunning,
      TaskStatus.completed => l.taskStatusCompleted,
      TaskStatus.failed => l.taskStatusFailed,
      TaskStatus.interrupted => l.taskStatusInterrupted,
    };

/// 卡片第二行「状态 · 阶段」里的阶段部分。
///
/// 进度百分比不入库，由 progressValue/progressMax 现算——
/// 这样切语言不会把「30%」这种与语言无关的数字也固化进去。
String taskNodeText(AppLocalizations l, TaskHistory task) {
  final percent = task.progressMax > 0
      ? (task.progressValue / task.progressMax * 100).round()
      : null;
  final detail = task.nodeDetail;

  return switch (task.nodePhase) {
    TaskNodePhase.waiting => l.taskPhaseWaiting,
    TaskNodePhase.started => l.taskPhaseStarted,
    TaskNodePhase.cached => l.taskPhaseCached,
    TaskNodePhase.running => _runningText(l, detail, percent),
    TaskNodePhase.done => l.taskPhaseDone,
    TaskNodePhase.error =>
      detail.isEmpty ? l.taskPhaseError : l.taskPhaseErrorDetail(detail),
    TaskNodePhase.interrupted => l.taskPhaseInterrupted,
    TaskNodePhase.lost => l.taskPhaseLost,
    TaskNodePhase.parseFailed => l.taskPhaseParseFailed,
  };
}

String _runningText(AppLocalizations l, String node, int? percent) {
  final hasNode = node.isNotEmpty;
  if (percent != null) {
    return hasNode
        ? l.taskPhaseRunningNodePercent(node, percent)
        : l.taskPhaseRunningPercent(percent);
  }
  return hasNode ? l.taskPhaseRunningNode(node) : l.taskPhaseRunning;
}
