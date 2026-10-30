import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:comfyui_mobilepocket/l10n/app_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';

import 'dart:io';
import 'dart:typed_data';

import '../../theme.dart';
import '../widgets/media_route.dart';
import '../widgets/zoomable_image.dart';
import '../../services/media_saver.dart';
import '../../providers/task_manager.dart';
import '../../providers/connection_provider.dart';
import '../../providers/haptics_provider.dart';
import '../../providers/snapshot_provider.dart';
import '../../models/task_history.dart';
import '../../models/task_status.dart';
import '../../models/workflow_snapshot.dart';
import '../../services/reference_image.dart';
import '../../services/image_ref.dart';
import '../widgets/reference_rail.dart';
import '../../utils.dart';
import '../../utils/history_search.dart';
import '../../utils/task_run.dart';
import '../../utils/task_references.dart';
import '../../utils/task_display.dart';
import '../../utils/task_stop.dart';
import '../widgets/compact_search_field.dart';
import '../widgets/connection_status_badge.dart';
import '../settings/server_config_view.dart';

class HistoryView extends ConsumerStatefulWidget {
  const HistoryView({super.key});

  @override
  ConsumerState<HistoryView> createState() => _HistoryViewState();
}

class _HistoryViewState extends ConsumerState<HistoryView> {
  // 连接生命周期由 home_view 统一维护（连接状态变化时 connect/disconnect），
  // 此处不再单独触发，避免多处 connect 造成框架断言风险
  @override
  void initState() {
    super.initState();
  }

  // ── 搜索与筛选（纯展示态，不落盘）────────────────────────
  final TextEditingController _searchController = TextEditingController();
  String _keyword = '';

  /// 状态筛选：null = 全部；其余为「进行中」这类合并后的筛选键。
  HistoryStatusFilter _statusFilter = HistoryStatusFilter.all;

  /// 正在请求停止的记录：按钮换成转圈，也挡住连点。
  final Set<String> _stopping = {};

  /// 正在收拢（即将删除）的记录：卡片按高度被裁短、下面的行跟着顶上来，再真正删掉。
  final Set<String> _collapsing = {};

  /// 收拢时长。与 [_CollapsibleRow] 用的是同一个值，否则会动画没播完就删。
  static const Duration _collapseDuration = Duration(milliseconds: 240);

  /// 确认框退场后再开始收拢的等待。
  ///
  /// `showDialog` 的 future 在 `pop` 那一刻就完成了，但弹窗还要退场约 150ms。
  /// 不等这一下，用户在盯着弹窗的时候动画已经播完 —— 这正是上一版「看不出效果」的原因之一。
  static const Duration _afterDialogDelay = Duration(milliseconds: 180);

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// 搜索框：按工作流名 / 填入的文本 / 参数别名过滤。
  /// 与配置页共用同一个紧凑搜索框，样式不会在两处各自漂移。
  Widget _buildSearchField(AppLocalizations l) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: CompactSearchField(
        controller: _searchController,
        hintText: l.historySearchHint,
        hasText: _keyword.isNotEmpty,
        onChanged: (v) => setState(() => _keyword = v.trim()),
        onClear: () {
          _searchController.clear();
          setState(() => _keyword = '');
        },
      ),
    );
  }

  /// 状态筛选条。
  ///
  /// 只用「边框色 + 文字色」区分选中态，不加底色块 —— 跟页面其它部分
  /// 一样走轻量路线，避免一排彩色药丸抢走记录的注意力。
  Widget _buildFilterChips(AppLocalizations l) {
    final items = <(HistoryStatusFilter, String)>[
      (HistoryStatusFilter.all, l.historyFilterAll),
      (HistoryStatusFilter.pending, l.historyFilterPending),
      (HistoryStatusFilter.completed, l.taskStatusCompleted),
      (HistoryStatusFilter.failed, l.taskStatusFailed),
      (HistoryStatusFilter.interrupted, l.taskStatusInterrupted),
    ];

    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final (filter, label) = items[i];
          final selected = _statusFilter == filter;
          return InkWell(
            onTap: () => setState(() => _statusFilter = filter),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: selected ? context.accent : context.borderColor,
                  width: selected ? 1.2 : 1,
                ),
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  color: selected ? context.accent : context.textSecondary,
                  fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // 任务状态 → 展示色（成功绿 / 失败红 / 中断灰 / 进行中橙）
  Color _statusColor(TaskStatus status) => switch (status) {
    TaskStatus.completed => context.stateSuccess,
    TaskStatus.failed => context.stateDanger,
    TaskStatus.interrupted => context.stateNeutral,
    TaskStatus.queued || TaskStatus.running => context.stateWarning,
  };

  // 无输出时的缩略图占位：终结态给出明确结果，只有进行中才转圈
  Widget _noOutputPlaceholder(
    TaskHistory task,
    Color statusColor,
    AppLocalizations l,
  ) {
    return switch (task.status) {
      TaskStatus.completed => Text(
        l.historyNoImage,
        style: TextStyle(fontSize: 12, color: context.textSecondary),
      ),
      TaskStatus.failed => Icon(
        Icons.error_outline,
        size: 22,
        color: statusColor,
      ),
      TaskStatus.interrupted => Icon(
        Icons.remove_circle_outline,
        size: 22,
        color: statusColor,
      ),
      // 排队中 / 生成中：确实还在等输出
      TaskStatus.queued || TaskStatus.running => const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    };
  }

  // 本地化的时间显示（yyyy-MM-dd HH:mm）
  String _formatTime(int timestamp) {
    final dt = DateTime.fromMillisecondsSinceEpoch(timestamp);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}';
  }

  // 删除确认：让用户选择是否连带删除画廊里对应的本地图片
  Future<void> _confirmDelete(TaskHistory task) async {
    final l = AppLocalizations.of(context);
    final hasLocal = task.images.any((img) {
      final p = img['localPath'];
      return p is String && p.isNotEmpty;
    });

    final choice = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.historyDeleteTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 名字为空（本地库已删/缓存已清）时按当前语言补默认名
            Text(l.historyDeleteConfirm(workflowDisplayNameOr(l, task.title))),
            if (hasLocal) ...[
              const SizedBox(height: 10),
              Text(
                l.historyDeleteImagesNote,
                style: TextStyle(fontSize: 12, color: context.textSecondary),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: Text(l.cancel),
          ),
          if (hasLocal)
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l.historyDeleteRecordOnly),
            ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: ctx.dangerButtonFill,
              foregroundColor: ctx.onDangerButtonFill,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(hasLocal ? l.historyDeleteWithImages : l.delete),
          ),
        ],
      ),
    );

    if (choice == null || !mounted) return;
    await Future<void>.delayed(_afterDialogDelay);
    if (!mounted) return;
    setState(() => _collapsing.add(task.promptId));
    await Future<void>.delayed(_collapseDuration);
    if (!mounted) return;
    await ref
        .read(taskManagerProvider.notifier)
        .removeTask(task.promptId, deleteLocalImages: choice);
    if (!mounted) return;
    setState(() => _collapsing.remove(task.promptId));
  }

  /// 远程停止一条还没结束的任务：先确认，再让服务器把它停掉。
  Future<void> _stopTask(TaskHistory task) async {
    final l = AppLocalizations.of(context);

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.historyStopTitle),
        content: Text(l.historyStopBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: context.stateWarning,
              foregroundColor: context.onStateWarning,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.historyStopConfirm),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _stopping.add(task.promptId));
    final outcome = await ref
        .read(taskManagerProvider.notifier)
        .stopTask(task.promptId);
    if (!mounted) return;
    setState(() => _stopping.remove(task.promptId));

    switch (outcome) {
      case StopOutcome.stopped:
        _toast(l.historyStopped);
      case StopOutcome.alreadyDone:
        _toast(l.historyStopNotRunning);
      case StopOutcome.offline || StopOutcome.failed:
        // 停不掉又删不掉，这条记录会永远卡在进行中 —— 所以失败时留一个删除出口
        _toast(
          l.historyStopFailed,
          actionLabel: l.historyStopActionDelete,
          onAction: () => _confirmDelete(task),
        );
    }
  }

  void _toast(String text, {String? actionLabel, VoidCallback? onAction}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        action: actionLabel == null
            ? null
            : SnackBarAction(label: actionLabel, onPressed: onAction ?? () {}),
      ),
    );
  }

  /// 进行中的记录：删除的位置换成停止（橙色，跟红色的删除区分开）。
  Widget _stopOrDeleteAction(TaskHistory task, AppLocalizations l) {
    if (_stopping.contains(task.promptId)) {
      return SizedBox(
        width: 40,
        height: 40,
        child: Padding(
          padding: const EdgeInsets.all(11),
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: context.stateWarning,
          ),
        ),
      );
    }
    return _IconAction(
      icon: Icons.stop_circle_outlined,
      color: context.stateWarning,
      tooltip: l.historyStopTooltip,
      onTap: () => _stopTask(task),
    );
  }

  String _getMediaUrl(Map<String, dynamic> mediaObj) {
    final config = ref.read(connectionProvider);
    final filename = Uri.encodeComponent(mediaObj['filename'] ?? '');
    final subfolder = Uri.encodeComponent(mediaObj['subfolder'] ?? '');
    final type = Uri.encodeComponent(mediaObj['type'] ?? 'output');
    return '${config.comfyUrl}/view?filename=$filename&subfolder=$subfolder&type=$type';
  }

  // 缩略图：优先读本地文件（服务端离线也能显示），无本地文件回退网络
  Widget _thumbnail(Map<String, dynamic> media) {
    final localPath = media['localPath'];
    if (localPath is String && localPath.isNotEmpty) {
      final f = File(localPath);
      if (f.existsSync()) {
        return Image.file(f, fit: BoxFit.cover);
      }
    }
    // 回退网络：切换服务器后旧 URL 可能失效，用占位图兜底避免报错
    return Image.network(
      _getMediaUrl(media),
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => Container(
        color: context.containerFill,
        child: Center(
          child: Icon(
            Icons.broken_image,
            size: 20,
            color: context.textSecondary,
          ),
        ),
      ),
    );
  }

  bool _isVideo(String? filename) {
    if (filename == null) return false;
    final ext = filename.split('.').last.toLowerCase();
    return ['mp4', 'webm', 'mov'].contains(ext);
  }

  void _openViewer(TaskHistory task, int initialIndex, {String? heroTag}) {
    final images = task.images;
    if (images.isEmpty) return;
    final refs = referenceImagesOf(ref, task);
    Navigator.of(context).push(
      // 用专属路由：前半程页面透明，黑底在后半程才淡进来（见 media_route.dart）
      mediaViewerRoute(
        (_) => MediaViewer(
          mediaList: images,
          initialIndex: initialIndex,
          urlBuilder: _getMediaUrl,
          isVideoChecker: _isVideo,
          // 首图与列表里那张缩略图之间做共享元素：点开时图自己长大，
          // 关掉时缩回原位，而不是「黑一下再出现」。
          heroTag: heroTag,
          referenceImages: refs,
          refBaseUrl: refs.isEmpty
              ? null
              : baseUrlForServer(ref, task.serverId),
        ),
      ),
    );
  }

  /// 缩略图 ↔ 大图共用的标签。同一条记录只在首图上挂，别让多图互相抢。
  /// 用 promptId（服务端给的唯一 id），不用列表下标：下标会随排序/删除整体前移。
  static String thumbHeroTagOf(TaskHistory task) =>
      'history-media-${task.promptId}-0';

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final tasks = ref.watch(taskManagerProvider).history;
    final configState = ref.watch(connectionProvider);
    final snapshots = ref.watch(snapshotProvider);

    // 快照建索引：反查参数别名要用，50 条的量级不建索引也行，
    // 但每条记录都遍历一遍列表没必要
    final snapshotById = <String, WorkflowSnapshot>{
      for (final s in snapshots) s.id: s,
    };

    // 过滤只算一次，不放进 itemBuilder 里重复跑
    final hits =
        HistorySearch.search(
              tasks,
              _keyword,
              // 必须比展示名：旧记录 title 是空串，界面上显示的是补出来的默认名
              displayName: (t) => workflowDisplayNameOr(l, t.title),
              snapshotOf: (id) => snapshotById[id],
            )
            .where(
              (h) => HistorySearch.passesFilter(_statusFilter, h.task.status),
            )
            .toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          l.historyTitle,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          if (configState.isConnected)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: l.historySyncTooltip,
              onPressed: () {
                // 与工作流页刷新按钮一致：向服务器对账未终结任务的状态
                ref.read(taskManagerProvider.notifier).reconcilePendingTasks();
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text(l.historySynced)));
              },
            ),
          ConnectionStatusBadge(
            // 直接进服务器连接页，而不是只切到「设置」Tab
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ServerConfigView()),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: tasks.isEmpty
          ? Center(
              child: Text(
                l.historyEmpty,
                style: TextStyle(color: context.textSecondary),
              ),
            )
          : Column(
              children: [
                _buildSearchField(l),
                _buildFilterChips(l),
                const SizedBox(height: 6),
                Expanded(
                  child: hits.isEmpty
                      ? Center(
                          child: Text(
                            l.historySearchEmpty,
                            style: TextStyle(color: context.textSecondary),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          itemCount: hits.length,
                          itemBuilder: (context, index) {
                            final hit = hits[index];
                            // key 必须跟着记录走：删掉一条后按下标复用元素，
                            // 会把上一条的「已收拢」状态串给下一条（上一版闪烁的另一半原因）
                            return _CollapsibleRow(
                              key: ValueKey<String>(hit.task.promptId),
                              collapsed: _collapsing.contains(
                                hit.task.promptId,
                              ),
                              child: _buildHistoryCard(hit, snapshots, l),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }

  /// 缩略图方框：有出图就显示首图（多图时右下角标数量），没有就给占位。
  ///
  /// 尺寸从 72 收到 56 —— 它是卡片高度的主要来源，56 仍认得出画面。
  Widget _buildThumbnail(
    TaskHistory task,
    Color statusColor,
    AppLocalizations l,
  ) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: context.containerFill,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.borderColor),
      ),
      clipBehavior: Clip.hardEdge,
      child: task.images.isNotEmpty
          ? Stack(
              fit: StackFit.expand,
              children: [
                _isVideo(task.images[0]['filename'])
                    ? Center(
                        child: Icon(
                          Icons.videocam,
                          color: context.textSecondary,
                        ),
                      )
                    : Hero(
                        tag: thumbHeroTagOf(task),
                        child: _thumbnail(task.images[0]),
                      ),
                if (task.images.length > 1)
                  Positioned(
                    right: 3,
                    bottom: 3,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${task.images.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            )
          : Center(child: _noOutputPlaceholder(task, statusColor, l)),
    );
  }

  /// 单张生成记录卡片。
  ///
  /// 紧凑行：56 缩略图 + 两行文字（名字 / 状态·时间），操作收成右上角两个图标。
  /// [hit.summary] 非空时（有关键词且靠参数内容命中）补一行命中摘要，
  /// 让用户一眼看出这条为什么被匹配。
  Widget _buildHistoryCard(
    HistoryHit hit,
    List<WorkflowSnapshot> snapshots,
    AppLocalizations l,
  ) {
    final task = hit.task;
    final statusColor = _statusColor(task.status);
    final progress = task.progressMax > 0
        ? (task.progressValue / task.progressMax)
        : 0.0;

    // 记录里有 snapshotId 还不够，必须快照当前真的存在——
    // 用户可能已经在设置页把它删掉了
    final canRerun =
        task.snapshotId != null &&
        snapshots.any((s) => s.id == task.snapshotId);

    // 阶段说明单独一行：跟时间挤在一行会互相截断
    final detail = taskStageDetail(l, task);

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: context.borderColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 状态色条：一屏内快速区分成功/失败/中断/进行中
            Container(width: 4, color: statusColor),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => _openViewer(
                        task,
                        0,
                        heroTag: _HistoryViewState.thumbHeroTagOf(task),
                      ),
                      child: _buildThumbnail(task, statusColor, l),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            workflowDisplayNameOr(l, task.title),
                            // 锁行高：默认行高会让 14 号字占掉 20px，行高压不下来
                            style: TextStyle(
                              fontSize: 14,
                              height: 1.2,
                              fontWeight: FontWeight.w500,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          // 命中摘要：说明这条为什么被搜到。
                          // 只在有关键词且靠参数内容命中时出现，靠名称命中的不重复展示
                          if (hit.summary != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              hit.summary!,
                              style: TextStyle(
                                fontSize: 11,
                                height: 1.2,
                                color: context.textSecondary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                          const SizedBox(height: 2),
                          Text(
                            // 第二行固定「状态 · 时间」：时间不许被阶段文案挤掉
                            '${taskStatusLabel(l, task.status)} · ${_formatTime(task.timestamp)}',
                            style: TextStyle(
                              fontSize: 11,
                              height: 1.2,
                              color: statusColor,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (detail.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              detail,
                              style: TextStyle(
                                fontSize: 11,
                                height: 1.2,
                                color: context.textSecondary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                          // 终结态不再显示进度条（失败/中断时它是条永远不动的空槽）
                          if (task.status.isPending) ...[
                            const SizedBox(height: 4),
                            // 进度是服务端「跳着」报的（20% → 35%），直接画会一格一格蹦。
                            // 补一次 400ms 的过渡，读起来像水在往前走；数值本身不加工，
                            // 只把超出 0~1 的乱序值夹掉。
                            TweenAnimationBuilder<double>(
                              tween: Tween<double>(
                                end: progress.clamp(0.0, 1.0),
                              ),
                              duration: const Duration(milliseconds: 400),
                              curve: Curves.easeOut,
                              builder: (context, value, _) =>
                                  LinearProgressIndicator(
                                    value: value,
                                    backgroundColor: context.containerFill,
                                    color: statusColor,
                                    minHeight: 3,
                                  ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    // 操作收成右侧两个图标：去掉底部按钮条和分隔线，
                    // 一条省下 37px。它们竖着撑满行高，不吃文字的行高
                    _IconAction(
                      icon: Icons.replay,
                      // 用沉一点的成功色而非品牌亮绿，小图标不至于抢过内容
                      color: canRerun
                          ? context.stateSuccess
                          : context.textSecondary,
                      tooltip: l.historyRerun,
                      // 置灰但仍可点：点击会说明具体原因，而不是静默无反应
                      onTap: () => runTaskAgain(context, ref, task),
                    ),
                    if (task.status.isPending)
                      _stopOrDeleteAction(task, l)
                    else
                      _IconAction(
                        icon: Icons.delete_outline,
                        color: context.stateDanger,
                        tooltip: l.delete,
                        onTap: () => _confirmDelete(task),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 删除前的收拢：卡片留在原地，按高度被裁短，而不是把内容换成空白。
///
/// ⚠️ 上一版写的是 `_collapsing ? SizedBox() : card`：卡片在**收拢第一帧就消失**，
/// 之后缩的是一段空白。实测逐帧日志里 t=160ms 还有 3 张 78 高的卡，
/// t=200ms 就只剩 2 张 —— 内容"没了"，没有任何"被抽走"的过程，所以既看不出、又闪。
class _CollapsibleRow extends StatefulWidget {
  const _CollapsibleRow({
    super.key,
    required this.collapsed,
    required this.child,
  });

  final bool collapsed;
  final Widget child;

  @override
  State<_CollapsibleRow> createState() => _CollapsibleRowState();
}

class _CollapsibleRowState extends State<_CollapsibleRow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _HistoryViewState._collapseDuration,
    // 控制器 1 = 完整高度、0 = 收拢到底。正常行进列表时必须是 1，
    // 写成 0 整张列表会全部零高（上一版就在这里翻过车）
    value: widget.collapsed ? 0 : 1,
  );

  @override
  void didUpdateWidget(covariant _CollapsibleRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.collapsed != oldWidget.collapsed) {
      // 收起 1→0（先慢后快，像被抽走）；万一被撤销则 0→1 原路退回
      widget.collapsed ? _controller.reverse() : _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: SizeTransition(
        sizeFactor: CurvedAnimation(
          parent: _controller,
          curve: Curves.easeInCubic,
        ),
        // 顶边不动、底边向上收
        alignment: Alignment.topCenter,
        child: widget.child,
      ),
    );
  }
}

/// 右侧的操作图标。
///
/// 40 的热区在 56 高的行里不占额外高度，所以压行高不必牺牲点击面积。
class _IconAction extends StatelessWidget {
  const _IconAction({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      padding: EdgeInsets.zero,
      iconSize: 18,
      constraints: const BoxConstraints.tightFor(width: 40, height: 40),
      visualDensity: VisualDensity.compact,
      icon: Icon(icon, color: color),
      tooltip: tooltip,
      onPressed: onTap,
    );
  }
}

// 独立的媒体全屏浏览器
//
// 一条记录的图分两组：**输出**（服务端出的图 / 视频）和 **输入**（这次喂进去的参考图）。
// 两组各自记「当前页」，长按只做一件事：临时翻到另一组的当前页，松手回来。
// ⚠️ 刻意不做「输出第 N 张 ↔ 参考图第 N 张」这类配对 —— 输出与参考图之间是 1:N / N:M，
// 任何自动配对都是我们替用户猜（§方案 2.3 ⑤）。
class MediaViewer extends ConsumerStatefulWidget {
  final List<Map<String, dynamic>> mediaList;
  final int initialIndex;
  final String Function(Map<String, dynamic>) urlBuilder;
  final bool Function(String) isVideoChecker;

  /// 与列表缩略图共用的共享元素标签；只在 [initialIndex] 那一页挂。
  final String? heroTag;

  /// 本次生成用到的参考图。空列表 → rail 整条不出现，查看器与加这个功能之前一致。
  final List<ReferenceImage> referenceImages;

  /// 拼参考图地址用的服务器地址。
  ///
  /// ⚠️ 必须是**这条记录所属服务器**的地址，不能图省事用当前 `comfyUrl`：
  /// 换了服务器之后文件名在对面根本不存在，必然 404，看起来像"图丢了"。
  /// null = 那台服务器已被移除。
  final String? refBaseUrl;

  const MediaViewer({
    super.key,
    required this.mediaList,
    required this.initialIndex,
    required this.urlBuilder,
    required this.isVideoChecker,
    this.heroTag,
    this.referenceImages = const [],
    this.refBaseUrl,
  });

  @override
  ConsumerState<MediaViewer> createState() => _MediaViewerState();
}

class _MediaViewerState extends ConsumerState<MediaViewer> {
  late PageController _pageController;
  late int _currentIndex;

  /// 两组各自的当前页。**互不覆盖** —— 这是"长按看另一张"能成立的前提：
  /// 回到另一组时落在你离开时那一页，而不是永远第 1 张。
  late int _outputPage;
  int _refPage = 0;

  bool _saving = false;

  /// 当前图是否处于放大态：放大时要把 PageView 的翻页关掉，
  /// 否则横拖是「平移图片」还是「翻页」会打架。
  bool _zoomed = false;

  /// 正在"按住对比"的目标页（绝对下标）；null = 没在对比。
  int? _peekIndex;

  int get _outputCount => widget.mediaList.length;
  int get _refCount => widget.referenceImages.length;
  int get _total => _outputCount + _refCount;

  bool _isRef(int index) => index >= _outputCount;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _outputPage = widget.initialIndex < _outputCount ? widget.initialIndex : 0;
    _pageController = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  /// 这条媒体有没有已经存到本地画廊的文件（有就直接读，不必再走网络）。
  File? _localFileOf(Map<String, dynamic> media) {
    final path = media['localPath'];
    if (path is! String || path.isEmpty) return null;
    final f = File(path);
    return f.existsSync() ? f : null;
  }

  void _jumpTo(int index) {
    if (index < 0 || index >= _total) return;
    if (index == _currentIndex) return;
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  /// 另一组的当前页；另一组不存在时返回 -1。
  int _otherGroupIndex() {
    if (_isRef(_currentIndex)) {
      return _outputCount == 0 ? -1 : _outputPage.clamp(0, _outputCount - 1);
    }
    return _refCount == 0 ? -1 : _outputCount + _refPage.clamp(0, _refCount - 1);
  }

  void _startPeek(int target) {
    // 放大态下按住多半是想平移图片，这时候换图会吓人 —— 直接不响应
    if (_zoomed) return;
    if (target < 0 || target >= _total) return;
    if (target == _currentIndex) return; // 同一张，没有对比的意义
    // 长按的震动走受控入口：之前这一震来自 InkResponse 的框架默认行为
    // （HapticFeedback.vibrate），设置里全关也拦不住。
    // 放在早退之后：没真的换图就不震，别让手上有感觉、屏幕没动静。
    hapticFeedback(ref, HapticCategory.press, strength: HapticStrength.medium);
    setState(() => _peekIndex = target);
  }

  void _endPeek() {
    if (_peekIndex == null) return;
    setState(() => _peekIndex = null);
  }

  void _handleZoomChanged(bool zoomed) {
    if (_zoomed == zoomed) return;
    setState(() => _zoomed = zoomed);
  }

  Future<void> _saveToLocal() async {
    if (_saving) return;
    final l = AppLocalizations.of(context);
    setState(() => _saving = true);
    try {
      final bytes = await _bytesOfCurrent();
      if (!mounted) return;

      final saved = await MediaSaver.save(
        context,
        bytes: bytes,
        filename: _currentFilename(),
      );
      if (saved && mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l.historySavedToAlbum)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l.historySaveFailed)));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _currentFilename() {
    if (_isRef(_currentIndex)) {
      return widget.referenceImages[_refPage].ref.filename;
    }
    return widget.mediaList[_currentIndex]['filename']?.toString() ?? 'image.png';
  }

  /// 当前页的字节。本地已有就直接读，读不到才走网络——
  /// 与画廊页行为一致，不为了存一张已经在本地的图再下载一遍。
  Future<Uint8List> _bytesOfCurrent() async {
    const timeout = Duration(seconds: 60);
    if (_isRef(_currentIndex)) {
      final base = widget.refBaseUrl;
      if (base == null) throw StateError('server removed');
      final url = imageViewUrl(
        base,
        widget.referenceImages[_refPage].ref,
      );
      return http.readBytes(Uri.parse(url)).timeout(timeout);
    }
    final media = widget.mediaList[_currentIndex];
    final localFile = _localFileOf(media);
    if (localFile != null) return localFile.readAsBytes();
    return http
        .readBytes(Uri.parse(widget.urlBuilder(media)))
        .timeout(timeout);
  }

  /// 一页的内容：视频 / 出图 / 参考图。
  ///
  /// [withHero] 传 false 用于对比覆盖层：同一张图在 PageView 里可能已经挂过
  /// 同标签的 Hero，两个同标签共享元素同时在场会直接断言失败。
  Widget _pageContent(
    BuildContext context,
    int index, {
    bool withHero = true,
  }) {
    final l = AppLocalizations.of(context);

    if (_isRef(index)) {
      final ref = widget.referenceImages[index - _outputCount];
      final base = widget.refBaseUrl;
      final child = base == null
          ? _LoadFailed(text: l.historyRefServerRemoved)
          : _RemoteImage(
              url: imageViewUrl(base, ref.ref),
              failedText: l.historyRefUnavailable,
            );
      return ZoomableImage(
        onZoomChanged: _handleZoomChanged,
        child: Center(child: child),
      );
    }

    final media = widget.mediaList[index];
    final url = widget.urlBuilder(media);
    if (widget.isVideoChecker(media['filename'])) {
      return _VideoItem(url: url);
    }
    // 与缩略图一致：已经存进画廊的图直接读本地文件，
    // 不再为了看一眼就把整张原图从服务器重新拉一遍
    final localFile = _localFileOf(media);
    final tag = withHero && index == widget.initialIndex
        ? widget.heroTag
        : null;
    Widget image = localFile != null
        ? Image.file(
            localFile,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => _LoadFailed(text: l.historyImageLoadFailed),
          )
        : _RemoteImage(url: url, failedText: l.historyImageLoadFailed);
    // 只给首帧挂 Hero：翻到第二张时不能有两个同标签的共享元素
    if (tag != null) image = Hero(tag: tag, child: image);
    return ZoomableImage(
      onZoomChanged: _handleZoomChanged,
      child: Center(child: image),
    );
  }

  /// rail 里的出图缩略图。视频没有可用封面，给个图标。
  Widget _outputThumb() {
    if (widget.mediaList.isEmpty) return const SizedBox.shrink();
    final media = widget.mediaList.first;
    if (widget.isVideoChecker(media['filename'])) {
      return const ColoredBox(
        color: Colors.white10,
        child: Center(child: Icon(Icons.videocam, size: 16, color: Colors.white54)),
      );
    }
    final localFile = _localFileOf(media);
    if (localFile != null) {
      return Image.file(
        localFile,
        fit: BoxFit.cover,
        cacheWidth: 108,
        errorBuilder: (_, _, _) => _brokenThumb(),
      );
    }
    return Image.network(
      widget.urlBuilder(media),
      fit: BoxFit.cover,
      cacheWidth: 108,
      errorBuilder: (_, _, _) => _brokenThumb(),
    );
  }

  /// rail 里的参考图缩略图。服务端转成 webp，一张约 45KB。
  Widget _refThumb(ReferenceImage ref) {
    final base = widget.refBaseUrl;
    if (base == null) return _brokenThumb();
    return Image.network(
      imageViewUrl(base, ref.ref, preview: 'webp;75'),
      fit: BoxFit.cover,
      cacheWidth: 108,
      errorBuilder: (_, _, _) => _brokenThumb(),
    );
  }

  Widget _brokenThumb() => const ColoredBox(
    color: Colors.white10,
    child: Center(
      child: Icon(Icons.broken_image, size: 16, color: Colors.white38),
    ),
  );

  /// 底部缩略图条：出图组（带张数角标）+ 竖分隔 + 参考图。
  Widget _buildRail() {
    if (_refCount == 0) return const SizedBox.shrink();
    final onRefPage = _isRef(_currentIndex);

    final items = <RailItem>[
      RailItem(
        thumb: _outputThumb(),
        badge: '$_outputCount',
        selected: !onRefPage,
        onTap: () => _jumpTo(_outputPage),
        onLongPressStart: () => _startPeek(_outputPage),
      ),
      for (var i = 0; i < _refCount; i++)
        RailItem(
          thumb: _refThumb(widget.referenceImages[i]),
          selected: onRefPage && _refPage == i,
          onTap: () => _jumpTo(_outputCount + i),
          onLongPressStart: () => _startPeek(_outputCount + i),
        ),
    ];

    return ReferenceRail(items: items, dividerAfter: 0, onPeekEnd: _endPeek);
  }

  String _titleText(AppLocalizations l) {
    if (_isRef(_currentIndex)) {
      return '${l.historyRefGroupLabel} ${_refPage + 1} / $_refCount';
    }
    // 分母是总数：与"实际翻得动的页数"一致，不会出现划到第 6 页却写着 1 / 5
    return '${_outputPage + 1} / $_total';
  }

  /// 对比提示条。**必须带页码** —— 它是"我正在看哪一张"的唯一凭证。
  Widget _peekHint(AppLocalizations l) {
    final target = _peekIndex!;
    final text = _isRef(target)
        ? l.historyRefPeekToInput(target - _outputCount + 1, _refCount)
        : l.historyRefPeekToOutput(target + 1, _total);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 12, color: Colors.white),
      ),
    );
  }

  Widget _peekOverlay(AppLocalizations l) {
    final target = _peekIndex;
    if (target == null) return const SizedBox.shrink();
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(
          color: Colors.black,
          child: Center(
            child: _pageContent(context, target, withHero: false),
          ),
        ),
        Positioned(top: 14, left: 0, right: 0, child: Center(child: _peekHint(l))),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final onRefPage = _isRef(_currentIndex);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        centerTitle: true,
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _titleText(l),
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            if (onRefPage)
              // 节点官方名：不翻译、不改写（同名节点也不加后缀，靠画面区分）
              Text(
                widget.referenceImages[_refPage].label,
                style: const TextStyle(fontSize: 12, color: Colors.white70),
              ),
          ],
        ),
      ),
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            // 放大态下禁止翻页：横拖应该平移图片，而不是滑走
            physics: _zoomed ? const NeverScrollableScrollPhysics() : null,
            onPageChanged: (idx) => setState(() {
              _currentIndex = idx;
              if (_isRef(idx)) {
                _refPage = idx - _outputCount;
              } else {
                _outputPage = idx;
              }
              // 换页时清掉放大标记：新一页是新的缩放状态
              _zoomed = false;
              _peekIndex = null;
            }),
            itemCount: _total,
            itemBuilder: (context, index) {
              return GestureDetector(
                // 按住 = 临时翻到另一组的当前页。滚动手势要移动才 claim，
                // 长按停住 500ms 一般能赢竞技场（真机验过；不灵还有 rail 长按兜底）
                onLongPressStart: (_) => _startPeek(_otherGroupIndex()),
                onLongPressEnd: (_) => _endPeek(),
                onLongPressCancel: _endPeek,
                child: _pageContent(context, index),
              );
            },
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 120),
                child: _peekIndex == null
                    ? const SizedBox.shrink()
                    : KeyedSubtree(
                        key: ValueKey<int>(_peekIndex!),
                        child: _peekOverlay(l),
                      ),
              ),
            ),
          ),
          // 悬浮在主图区底部：不占布局，出图页与参考图页的主图区几何完全一致
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _buildRail(),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: context.accent,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
              ),
              onPressed: _saving ? null : _saveToLocal,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.save_alt),
              label: Text(
                _saving ? l.historySaving : l.historySaveToLocal,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            ),
        ),
      ),
    );
  }
}

/// 走网络加载的大图：给进度与失败提示，避免慢网下黑屏干等。
class _RemoteImage extends StatelessWidget {
  const _RemoteImage({required this.url, required this.failedText});

  final String url;
  final String failedText;

  @override
  Widget build(BuildContext context) {
    return Image.network(
      url,
      fit: BoxFit.contain,
      loadingBuilder: (_, child, progress) {
        // progress 为 null 表示字节已收完，直接显示图
        if (progress == null) return child;
        final total = progress.expectedTotalBytes;
        return Center(
          child: CircularProgressIndicator(
            color: Colors.white,
            value: total != null && total > 0
                ? progress.cumulativeBytesLoaded / total
                : null,
          ),
        );
      },
      errorBuilder: (_, _, _) => _LoadFailed(text: failedText),
    );
  }
}

/// 加载失败的占位：说明状态，不再留一片黑。
class _LoadFailed extends StatelessWidget {
  const _LoadFailed({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.broken_image, size: 40, color: Colors.white70),
        const SizedBox(height: 10),
        Text(text, style: const TextStyle(color: Colors.white70)),
      ],
    );
  }
}

// 视频播放组件：使用 video_player 进行真实的视频播放
class _VideoItem extends StatefulWidget {
  final String url;
  const _VideoItem({required this.url});

  @override
  State<_VideoItem> createState() => _VideoItemState();
}

class _VideoItemState extends State<_VideoItem> {
  VideoPlayerController? _controller;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final controller = VideoPlayerController.networkUrl(
        Uri.parse(widget.url),
      );
      await controller.initialize();
      await controller.setLooping(true);
      if (!mounted) {
        controller.dispose();
        return;
      }
      setState(() => _controller = controller);
      controller.play();
    } catch (e) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return Center(
        child: Text(
          AppLocalizations.of(context).historyVideoLoadFailed,
          style: const TextStyle(color: Colors.white70),
        ),
      );
    }
    final controller = _controller;
    if (controller == null) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }
    return Center(
      child: AspectRatio(
        aspectRatio: controller.value.aspectRatio,
        child: Stack(
          alignment: Alignment.center,
          children: [
            VideoPlayer(controller),
            // 点击播放/暂停
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() {
                controller.value.isPlaying
                    ? controller.pause()
                    : controller.play();
              }),
              child: AnimatedOpacity(
                opacity: controller.value.isPlaying ? 0.0 : 1.0,
                duration: const Duration(milliseconds: 200),
                child: const Icon(
                  Icons.play_circle_fill,
                  size: 64,
                  color: Colors.white70,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
