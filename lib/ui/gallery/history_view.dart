import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';
import 'dart:io';
import 'dart:typed_data';
import '../../theme.dart';
import '../../services/media_saver.dart';
import '../../providers/task_manager.dart';
import '../../providers/connection_provider.dart';
import '../../models/task_history.dart';
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

  // 任务状态 → 展示色（成功绿 / 失败红 / 中断灰 / 进行中橙）
  Color _statusColor(String status) {
    switch (status) {
      case '已完成':
        return AppColors.success;
      case '已失败':
        return AppColors.danger;
      case '已中断':
        return AppColors.neutral;
      default:
        return AppColors.warning;
    }
  }

  // 无输出时的缩略图占位：终结态给出明确结果，只有进行中才转圈
  Widget _noOutputPlaceholder(String status, Color statusColor) {
    switch (status) {
      case '已完成':
        return const Text('无图', style: TextStyle(fontSize: 12, color: Colors.grey));
      case '已失败':
        return Icon(Icons.error_outline, size: 22, color: statusColor);
      case '已中断':
        return Icon(Icons.remove_circle_outline, size: 22, color: statusColor);
      default:
        // 排队中 / 生成中：确实还在等输出
        return const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
    }
  }

  // 本地化的时间显示（yyyy-MM-dd HH:mm）
  String _formatTime(int timestamp) {
    final dt = DateTime.fromMillisecondsSinceEpoch(timestamp);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}';
  }

  // 删除确认：让用户选择是否连带删除画廊里对应的本地图片
  Future<void> _confirmDelete(TaskHistory task) async {
    final hasLocal = task.images.any((img) {
      final p = img['localPath'];
      return p is String && p.isNotEmpty;
    });

    final choice = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除记录'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('确定删除「${task.title}」这条生成记录吗？'),
            if (hasLocal) ...[
              const SizedBox(height: 10),
              const Text(
                '选择"同时删除画廊图片"会一并移除该记录已保存到画廊的本地图片，'
                '此操作不可恢复；仅删除记录则保留画廊图片。',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, null), child: const Text('取消')),
          if (hasLocal)
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('仅删除记录'),
            ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(hasLocal ? '同时删除画廊图片' : '删除'),
          ),
        ],
      ),
    );

    if (choice == null || !mounted) return;
    ref
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
        child: const Center(child: Icon(Icons.broken_image, size: 20, color: Colors.grey)),
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
    final tasks = ref.watch(taskManagerProvider).history;
    final configState = ref.watch(connectionProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('生成记录', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          if (configState.isConnected)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: '同步任务状态',
              onPressed: () {
                // 与工作流页刷新按钮一致：向服务器对账未终结任务的状态
                ref.read(taskManagerProvider.notifier).reconcilePendingTasks();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已同步任务状态')),
                );
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
          ? const Center(child: Text('暂无生成记录', style: TextStyle(color: Colors.grey)))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: tasks.length,
              itemBuilder: (context, index) {
                final task = tasks[index];
                final isDone = task.status == '已完成';
                // 终结态：任务已结束、不会再有输出（失败/中断同样如此），
                // 不能继续显示加载动画，否则会永久转圈
                final isTerminal =
                    isDone || task.status == '已失败' || task.status == '已中断';
                final statusColor = _statusColor(task.status);
                final progress = task.progressMax > 0 ? (task.progressValue / task.progressMax) : 0.0;

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
                          child: Padding(
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
                                        task.title,
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        '${task.status} · ${task.nodeInfo}',
                                        style: TextStyle(fontSize: 13, color: statusColor),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      // 终结态不再显示进度条（失败/中断时它是条永远不动的空槽）
                                      if (!isTerminal) ...[
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
                                        style: const TextStyle(fontSize: 11, color: Colors.grey),
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
                                          border: Border.all(color: Colors.grey.shade300),
                                        ),
                                        clipBehavior: Clip.hardEdge,
                                        child: task.images.isNotEmpty
                                            ? Stack(
                                                fit: StackFit.expand,
                                                children: [
                                                  _isVideo(task.images[0]['filename'])
                                                      ? const Center(child: Icon(Icons.videocam, color: Colors.grey))
                                                      : _thumbnail(task.images[0]),
                                                  if (task.images.length > 1)
                                                    Positioned(
                                                      right: 4,
                                                      bottom: 4,
                                                      child: Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                        decoration: BoxDecoration(
                                                          color: Colors.black.withValues(alpha: 0.6),
                                                          borderRadius: BorderRadius.circular(10),
                                                        ),
                                                        child: Text('${task.images.length}', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                                                      ),
                                                    )
                                                ],
                                              )
                                            : Center(child: _noOutputPlaceholder(task.status, statusColor)),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    // 删除按钮移到底部，避免紧贴标题误触
                                    InkWell(
                                      onTap: () => _confirmDelete(task),
                                      borderRadius: BorderRadius.circular(4),
                                      child: const Padding(
                                        padding: EdgeInsets.all(2),
                                        child: Icon(Icons.delete_outline, size: 16, color: Colors.grey),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
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
    setState(() => _saving = true);
    try {
      final currentMedia = widget.mediaList[_currentIndex];
      final filename = currentMedia['filename']?.toString() ?? 'image.png';

      // 优先读取已本地化的文件（避免重复下载，且与画廊页行为一致）；
      // 没有本地文件（未下载过或已被删除）时才回退网络
      final localPath = currentMedia['localPath'];
      Uint8List bytes;
      if (localPath is String && localPath.isNotEmpty && File(localPath).existsSync()) {
        bytes = await File(localPath).readAsBytes();
      } else {
        bytes = await http.readBytes(Uri.parse(widget.urlBuilder(currentMedia)));
      }
      if (!mounted) return;

      // 与画廊页共用保存逻辑：PNG 可选「带工作流原图」或「剔除信息」
      final saved = await MediaSaver.save(context, bytes: bytes, filename: filename);
      if (saved && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ 已保存到手机相册')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('保存失败')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
            child: Center(
              child: Image.network(url, fit: BoxFit.contain),
            ),
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
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
            ),
            onPressed: _saving ? null : _saveToLocal,
            icon: _saving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.save_alt),
            label: Text(_saving ? '保存中...' : '保存到本地', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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
      final controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
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
      return const Center(child: Text('视频加载失败', style: TextStyle(color: Colors.white70)));
    }
    final controller = _controller;
    if (controller == null) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
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
                controller.value.isPlaying ? controller.pause() : controller.play();
              }),
              child: AnimatedOpacity(
                opacity: controller.value.isPlaying ? 0.0 : 1.0,
                duration: const Duration(milliseconds: 200),
                child: const Icon(Icons.play_circle_fill, size: 64, color: Colors.white70),
              ),
            ),
          ],
        ),
      ),
    );
  }
}