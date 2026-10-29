import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:comfyui_mobilepocket/l10n/app_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';

import 'dart:io';

import '../../theme.dart';
import '../../services/media_saver.dart';
import '../../providers/task_manager.dart';
import '../../providers/connection_provider.dart';
import '../../providers/snapshot_provider.dart';
import '../../models/task_history.dart';
import '../../models/task_status.dart';
import '../../models/workflow_snapshot.dart';
import '../../utils.dart';
import '../../utils/history_search.dart';
import '../../utils/task_display.dart';
import '../../utils/task_stop.dart';
import '../widgets/compact_search_field.dart';
import '../widgets/connection_status_badge.dart';
import '../builder/run_view.dart';
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

  /// 正在收拢（准备删除）的记录：卡片先缩到零高，再真的从列表里去掉。
  ///
  /// 不做这一步的话，删掉的一瞬间整行消失、下面的记录直接顶上来，
  /// 手指还停在原处，很容易误判成「删错了」。
  final Set<String> _collapsing = {};

  /// 收起动画时长；与 [AnimatedSize] 里的值必须一致，否则会在动画中途就删掉。
  static const Duration _collapseDuration = Duration(milliseconds: 220);

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

  /// 「再次运行」：凭这条记录留下的快照还原表单，并预填当时的参数。
  Future<void> _runAgain(TaskHistory task) async {
    final l = AppLocalizations.of(context);
    final snapshotId = task.snapshotId;

    if (snapshotId == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l.historyNoSnapshot)));
      return;
    }

    final snapshot = ref.read(snapshotProvider.notifier).byId(snapshotId);
    if (snapshot == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l.historySnapshotDeleted)));
      return;
    }

    // 服务器一致性：环境不同，模型/节点可能缺失，先让用户知情
    final config = ref.read(connectionProvider);
    final currentId = config.activeServerId;
    if (task.serverId != currentId) {
      String nameOf(String? id) {
        if (id == null) return l.historyUnknownServer;
        for (final s in config.servers) {
          if (s.id == id) return s.name;
        }
        return l.historyUnknownServer;
      }

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l.historyServerMismatchTitle),
          content: Text(
            l.historyServerMismatchBody(
              nameOf(task.serverId),
              nameOf(currentId),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l.historyRunAnyway),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RunView(
          workflowId: task.workflowId,
          snapshotId: snapshotId,
          initialParams: task.params,
        ),
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
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(hasLocal ? l.historyDeleteWithImages : l.delete),
          ),
        ],
      ),
    );

    if (choice == null || !mounted) return;
    // 先让这张卡片收拢，再真的删：顺序反过来就看不到任何过渡
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

  void _openViewer(
    List<Map<String, dynamic>> images,
    int initialIndex, {
    String? heroTag,
  }) {
    if (images.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MediaViewer(
          mediaList: images,
          initialIndex: initialIndex,
          urlBuilder: _getMediaUrl,
          isVideoChecker: _isVideo,
          // 首图与列表里那张缩略图之间做共享元素：点开时图自己长大，
          // 关掉时缩回原位，而不是「黑一下再出现」。
          heroTag: heroTag,
        ),
        fullscreenDialog: true,
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
                            // 删除前先收拢：卡片缩到零高，下面的记录再补位
                            return ClipRect(
                              child: AnimatedSize(
                                duration: _collapseDuration,
                                curve: Curves.easeInCubic,
                                alignment: Alignment.topCenter,
                                child: _collapsing.contains(hit.task.promptId)
                                    ? const SizedBox(width: double.infinity)
                                    : _buildHistoryCard(hit, snapshots, l),
                              ),
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
                        task.images,
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
                      onTap: () => _runAgain(task),
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
class MediaViewer extends StatefulWidget {
  final List<Map<String, dynamic>> mediaList;
  final int initialIndex;
  final String Function(Map<String, dynamic>) urlBuilder;
  final bool Function(String) isVideoChecker;

  /// 与列表缩略图共用的共享元素标签；只在 [initialIndex] 那一页挂。
  final String? heroTag;

  const MediaViewer({
    super.key,
    required this.mediaList,
    required this.initialIndex,
    required this.urlBuilder,
    required this.isVideoChecker,
    this.heroTag,
  });

  @override
  State<MediaViewer> createState() => _MediaViewerState();
}

class _MediaViewerState extends State<MediaViewer> {
  late PageController _pageController;
  late int _currentIndex;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
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

  Future<void> _saveToLocal() async {
    if (_saving) return;
    final l = AppLocalizations.of(context);
    setState(() => _saving = true);
    try {
      final currentMedia = widget.mediaList[_currentIndex];
      final filename = currentMedia['filename']?.toString() ?? 'image.png';

      // 优先读取已本地化的文件（避免重复下载，且与画廊页行为一致）；
      // 没有本地文件（未下载过或已被删除）时才回退网络
      final localFile = _localFileOf(currentMedia);
      final bytes = localFile != null
          ? await localFile.readAsBytes()
          : await http
                .readBytes(Uri.parse(widget.urlBuilder(currentMedia)))
                .timeout(const Duration(seconds: 60));
      if (!mounted) return;

      // 与画廊页共用保存逻辑：PNG 可选「带工作流原图」或「剔除信息」
      final saved = await MediaSaver.save(
        context,
        bytes: bytes,
        filename: filename,
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

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('${_currentIndex + 1} / ${widget.mediaList.length}'),
        centerTitle: true,
      ),
      body: PageView.builder(
        controller: _pageController,
        onPageChanged: (idx) => setState(() => _currentIndex = idx),
        itemCount: widget.mediaList.length,
        itemBuilder: (context, index) {
          final media = widget.mediaList[index];
          final url = widget.urlBuilder(media);

          if (widget.isVideoChecker(media['filename'])) {
            return _VideoItem(url: url);
          }
          // 与缩略图一致：已经存进画廊的图直接读本地文件，
          // 不再为了看一眼就把整张原图从服务器重新拉一遍
          final localFile = _localFileOf(media);
          final tag = index == widget.initialIndex ? widget.heroTag : null;
          Widget image = localFile != null
              ? Image.file(
                  localFile,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) =>
                      _LoadFailed(text: l.historyImageLoadFailed),
                )
              : _RemoteImage(url: url, failedText: l.historyImageLoadFailed);
          // 只给首帧挂 Hero：翻到第二张时不能有两个同标签的共享元素
          if (tag != null) image = Hero(tag: tag, child: image);
          return InteractiveViewer(child: Center(child: image));
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
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
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
