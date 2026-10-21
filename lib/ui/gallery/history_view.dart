import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:comfyui_mobilepocket/l10n/app_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';

import 'dart:io';
import 'dart:typed_data';

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

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// 卡片底部的操作区：左右各占一半，仅用图标颜色做轻度区分，不加重装饰
  Widget _buildActionBar(
    TaskHistory task,
    List<WorkflowSnapshot> snapshots,
    AppLocalizations l,
  ) {
    // 记录里有 snapshotId 还不够，必须快照当前真的存在——
    // 用户可能已经在设置页把它删掉了
    final canRerun =
        task.snapshotId != null &&
        snapshots.any((s) => s.id == task.snapshotId);

    return Row(
      children: [
        _ActionKey(
          icon: Icons.replay,
          label: l.historyRerun,
          // 用沉一点的成功色而非品牌亮绿，小图标不至于抢过内容
          color: AppColors.success,
          // 置灰但仍可点：点击会说明具体原因，而不是静默无反应
          enabled: canRerun,
          onTap: () => _runAgain(task),
        ),
        _ActionKey(
          icon: Icons.delete_outline,
          label: l.delete,
          color: AppColors.danger,
          enabled: true,
          onTap: () => _confirmDelete(task),
        ),
      ],
    );
  }

  /// 搜索框：按工作流名 / 填入的文本 / 参数别名过滤。
  ///
  /// 样式与配置页的搜索框保持一致（圆角 8、图标 18、dense）。
  Widget _buildSearchField(AppLocalizations l) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      child: TextField(
        controller: _searchController,
        onChanged: (v) => setState(() => _keyword = v.trim()),
        decoration: InputDecoration(
          isDense: true,
          hintText: l.historySearchHint,
          prefixIcon: const Icon(Icons.search, size: 18),
          suffixIcon: _keyword.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _keyword = '');
                  },
                ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 12,
          ),
        ),
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
                  color: selected ? AppColors.primary : Colors.grey.shade300,
                  width: selected ? 1.2 : 1,
                ),
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  color: selected ? AppColors.primary : Colors.grey.shade700,
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
    TaskStatus.completed => AppColors.success,
    TaskStatus.failed => AppColors.danger,
    TaskStatus.interrupted => AppColors.neutral,
    TaskStatus.queued || TaskStatus.running => AppColors.warning,
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
        style: const TextStyle(fontSize: 12, color: Colors.grey),
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
                style: const TextStyle(fontSize: 12, color: Colors.grey),
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
    await ref
        .read(taskManagerProvider.notifier)
        .removeTask(task.promptId, deleteLocalImages: choice);
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
        color: Colors.grey.shade200,
        child: const Center(
          child: Icon(Icons.broken_image, size: 20, color: Colors.grey),
        ),
      ),
    );
  }

  bool _isVideo(String? filename) {
    if (filename == null) return false;
    final ext = filename.split('.').last.toLowerCase();
    return ['mp4', 'webm', 'mov'].contains(ext);
  }

  void _openViewer(List<Map<String, dynamic>> images, int initialIndex) {
    if (images.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MediaViewer(
          mediaList: images,
          initialIndex: initialIndex,
          urlBuilder: _getMediaUrl,
          isVideoChecker: _isVideo,
        ),
        fullscreenDialog: true,
      ),
    );
  }

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
                style: const TextStyle(color: Colors.grey),
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
                            style: const TextStyle(color: Colors.grey),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          itemCount: hits.length,
                          itemBuilder: (context, index) =>
                              _buildHistoryCard(hits[index], snapshots, l),
                        ),
                ),
              ],
            ),
    );
  }

  /// 单张生成记录卡片。
  ///
  /// [hit.summary] 非空时（有关键词且靠参数内容命中）在工作流名下方
  /// 补一行命中摘要，让用户一眼看出这条为什么被匹配。
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

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 状态色条：一屏内快速区分成功/失败/中断/进行中
            Container(width: 4, color: statusColor),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(14.0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                workflowDisplayNameOr(l, task.title),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              // 命中摘要：说明这条为什么被搜到。
                              // 只在有关键词且靠参数内容命中时出现，靠名称命中的不重复展示
                              if (hit.summary != null) ...[
                                const SizedBox(height: 5),
                                Text(
                                  hit.summary!,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                              const SizedBox(height: 6),
                              Text(
                                '${taskStatusLabel(l, task.status)} · ${taskNodeText(l, task)}',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: statusColor,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              // 终结态不再显示进度条（失败/中断时它是条永远不动的空槽）
                              if (task.status.isPending) ...[
                                const SizedBox(height: 8),
                                LinearProgressIndicator(
                                  value: progress,
                                  backgroundColor: Colors.grey.shade200,
                                  color: statusColor,
                                  minHeight: 4,
                                ),
                              ],
                              const SizedBox(height: 6),
                              Text(
                                _formatTime(task.timestamp),
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 14),
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            GestureDetector(
                              onTap: () => _openViewer(task.images, 0),
                              child: Container(
                                width: 72,
                                height: 72,
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: Colors.grey.shade300,
                                  ),
                                ),
                                clipBehavior: Clip.hardEdge,
                                child: task.images.isNotEmpty
                                    ? Stack(
                                        fit: StackFit.expand,
                                        children: [
                                          _isVideo(task.images[0]['filename'])
                                              ? const Center(
                                                  child: Icon(
                                                    Icons.videocam,
                                                    color: Colors.grey,
                                                  ),
                                                )
                                              : _thumbnail(task.images[0]),
                                          if (task.images.length > 1)
                                            Positioned(
                                              right: 4,
                                              bottom: 4,
                                              child: Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 6,
                                                      vertical: 2,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: Colors.black
                                                      .withValues(alpha: 0.6),
                                                  borderRadius:
                                                      BorderRadius.circular(10),
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
                                    : Center(
                                        child: _noOutputPlaceholder(
                                          task,
                                          statusColor,
                                          l,
                                        ),
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  // 操作区放在卡片底部左右排开，不再挤在缩略图下方：
                  // 两个按钮各占一半宽度，触控目标也更大
                  _buildActionBar(task, snapshots, l),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 底部操作项：图标 + 文字，无底色无阴影，仅靠图标颜色区分语义。
/// 用 InkWell 提供点击涟漪，保持与列表其它区域的观感一致。
class _ActionKey extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool enabled;
  final VoidCallback onTap;

  const _ActionKey({
    required this.icon,
    required this.label,
    required this.color,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // 只有图标带语义色，文字统一中性灰，让操作区整体后退
    final iconColor = enabled ? color : Colors.grey.shade400;
    final textColor = enabled ? Colors.grey.shade600 : Colors.grey.shade400;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 36,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: iconColor),
              const SizedBox(width: 5),
              Text(label, style: TextStyle(fontSize: 12, color: textColor)),
            ],
          ),
        ),
      ),
    );
  }
}

// 独立的媒体全屏浏览器
class MediaViewer extends StatefulWidget {
  final List<Map<String, dynamic>> mediaList;
  final int initialIndex;
  final String Function(Map<String, dynamic>) urlBuilder;
  final bool Function(String) isVideoChecker;

  const MediaViewer({
    super.key,
    required this.mediaList,
    required this.initialIndex,
    required this.urlBuilder,
    required this.isVideoChecker,
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

  Future<void> _saveToLocal() async {
    if (_saving) return;
    final l = AppLocalizations.of(context);
    setState(() => _saving = true);
    try {
      final currentMedia = widget.mediaList[_currentIndex];
      final filename = currentMedia['filename']?.toString() ?? 'image.png';

      // 优先读取已本地化的文件（避免重复下载，且与画廊页行为一致）；
      // 没有本地文件（未下载过或已被删除）时才回退网络
      final localPath = currentMedia['localPath'];
      Uint8List bytes;
      if (localPath is String &&
          localPath.isNotEmpty &&
          File(localPath).existsSync()) {
        bytes = await File(localPath).readAsBytes();
      } else {
        bytes = await http.readBytes(
          Uri.parse(widget.urlBuilder(currentMedia)),
        );
      }
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
          return InteractiveViewer(
            child: Center(child: Image.network(url, fit: BoxFit.contain)),
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.green,
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
