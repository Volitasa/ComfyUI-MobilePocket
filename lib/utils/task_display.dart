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

/// 阶段文案里与状态完全重复的那些组合。
///
/// 「已完成 · 生成成功」「已中断 · 已中断」「排队中 · 等待执行」——后半句
/// 没带来任何新信息，紧凑卡片里不该再占位置。
///
/// ⚠️ 这里按**阶段**判断而不是按状态：`连接丢失`（服务器重启导致的中断）
/// 和 `结果解析失败` 都不是状态的同义反复，必须照常显示。
bool _isRedundantWithStatus(TaskNodePhase phase) => switch (phase) {
  TaskNodePhase.done ||
  TaskNodePhase.interrupted ||
  TaskNodePhase.waiting => true,
  TaskNodePhase.started ||
  TaskNodePhase.cached ||
  TaskNodePhase.running ||
  TaskNodePhase.error ||
  TaskNodePhase.parseFailed ||
  TaskNodePhase.lost => false,
};

/// 需要单独占一行展示的阶段说明；与状态重复时返回空串。
///
/// 为什么不把阶段跟时间挤在同一行：阶段文案长度不可控
/// （「未在服务端找到该任务」、几十个字的错误原文），会把时间截掉——
/// 而「什么时候跑的」在翻记录时比半句诊断更常被看。
/// 所以第二行固定「状态 · 时间」，阶段有新信息才单独占第三行。
///
/// 只影响展示，不碰持久化字段（nodePhase 照旧入库）。
String taskStageDetail(AppLocalizations l, TaskHistory task) {
  if (_isRedundantWithStatus(task.nodePhase)) return '';
  return taskNodeText(l, task);
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
