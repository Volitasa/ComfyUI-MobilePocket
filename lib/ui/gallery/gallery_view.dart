import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:comfyui_mobilepocket/l10n/app_localizations.dart';

import '../../models/task_history.dart';
import '../../providers/gallery_revision_provider.dart';
import '../../providers/snapshot_provider.dart';
import '../../providers/task_manager.dart';
import '../../services/gallery_store.dart';
import '../../services/media_saver.dart';
import '../../services/image_ref.dart';
import '../../services/reference_image.dart';
import '../../utils/task_references.dart';
import '../../utils/task_run.dart';
import '../widgets/image_viewer.dart';
import '../widgets/media_route.dart';
import '../widgets/reference_rail.dart';
import '../widgets/zoomable_image.dart';
import '../widgets/skeleton.dart';

import '../../theme.dart';

/// 画廊：浏览所有本地化保存的生成图片。
/// 图片以原始文件保存在 App 沙盒，内嵌 ComfyUI 工作流元数据，
/// 拖回 ComfyUI 即可复现。
class GalleryView extends ConsumerStatefulWidget {
  const GalleryView({super.key});

  @override
  ConsumerState<GalleryView> createState() => _GalleryViewState();
}

class _GalleryViewState extends ConsumerState<GalleryView> {
  List<File> _images = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final imgs = await GalleryStore.instance.listImages();
    if (!mounted) return;
    setState(() {
      _images = imgs;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    // 只在「画廊目录真的动过」时才重扫。生成中的进度推送每秒好几次，
    // 跟着全量列目录 + 整页重建纯属浪费（IndexedStack 常驻，不在前台也照跑）。
    // 计数由落盘/删盘的地方负责递增，不靠比较任务状态的前后快照 —— 记录对象是
    // 可变的，前后两帧共享同一批实例，差值永远为 0（2026-10-24 修）。
    ref.listen(galleryRevisionProvider, (prev, next) {
      if (prev != null && next != prev) _refresh();
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(
          AppLocalizations.of(context).navGallery,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: AppLocalizations.of(context).galleryRefreshTooltip,
            onPressed: () {
              setState(() => _loading = true);
              _refresh();
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _loading
          ? const GalleryGridSkeleton()
          : _images.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.photo_library_outlined,
                    size: 48,
                    color: context.textSecondary,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    AppLocalizations.of(context).galleryEmptyTitle,
                    style: TextStyle(color: context.textSecondary, fontSize: 16),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    AppLocalizations.of(context).galleryEmptyHint,
                    style: TextStyle(
                      color: context.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _refresh,
              child: GridView.builder(
                padding: const EdgeInsets.all(12),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemCount: _images.length,
                itemBuilder: (context, index) {
                  final file = _images[index];
                  return GestureDetector(
                    onTap: () => _openViewer(index),
                    // 共享元素：点了之后这张小图自己长大铺满全屏，
                    // 退出时再缩回格子里，中间不黑屏。
                    child: Hero(
                      tag: _heroTagOf(file),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(
                          file,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(
                            color: context.containerFill,
                            child: Icon(
                              Icons.broken_image,
                              color: context.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }

  /// 网格 ↔ 大图共用的标签。用文件路径而不是下标：删图后下标会整体前移，
  /// 用下标会让「点这张、飞那张」。
  static String _heroTagOf(File file) => 'gallery-${file.path}';

  void _openViewer(int index) {
    // 查看器里可能删图；删完由它递增画廊计数，本页自动跟着重扫，
    // 不需要再靠返回值手动刷一次
    Navigator.push(
      context,
      mediaViewerRoute(
        (_) => _GalleryViewer(
          images: _images,
          initialIndex: index,
          heroTag: _heroTagOf(_images[index]),
        ),
      ),
    );
  }
}

/// 画廊大图查看器
class _GalleryViewer extends ConsumerStatefulWidget {
  final List<File> images;
  final int initialIndex;

  /// 与网格里那张图共用的共享元素标签；只挂在 [initialIndex] 那一页。
  final String? heroTag;
  const _GalleryViewer({
    required this.images,
    required this.initialIndex,
    this.heroTag,
  });

  @override
  ConsumerState<_GalleryViewer> createState() => _GalleryViewerState();
}

class _GalleryViewerState extends ConsumerState<_GalleryViewer> {
  late PageController _pageController;
  late int _currentIndex;
  bool _saving = false;

  /// 放大态：放大时把翻页关掉，否则横拖是「平移图片」还是「翻页」会打架。
  bool _zoomed = false;

  /// 当前这一张反查到的生成记录。null = 查不到（记录被删了，或超过 50 条被截断）。
  TaskHistory? _task;

  /// 那次生成喂进去的参考图。
  List<ReferenceImage> _refs = const [];

  /// 拼参考图地址用的服务器；null = 原服务器已移除。
  String? _refBaseUrl;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: _currentIndex);
    _syncTaskContext();
  }

  /// 画廊里前后两张可能来自**不同**的任务，翻页就得重算。
  ///
  /// 反查走 `taskByLocalPath`（预建的表，O(1)），不在 build 里扫记录列表。
  void _syncTaskContext() {
    final task = ref
        .read(taskManagerProvider.notifier)
        .taskByLocalPath(_current.path);
    final refs = task == null ? const <ReferenceImage>[] : referenceImagesOf(ref, task);
    _task = task;
    _refs = refs;
    _refBaseUrl = refs.isEmpty ? null : baseUrlForServer(ref, task!.serverId);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  File get _current => widget.images[_currentIndex];

  // 保存到系统相册：让用户选择「带工作流原图」或「剔除元数据的普通图」
  Future<void> _saveToGallery() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      // 校验文件仍存在（列表残留或已被删除时给出明确提示）
      if (!_current.existsSync()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context).galleryImageMissing),
            ),
          );
        }
        return;
      }

      final bytes = await _current.readAsBytes();
      if (!mounted) return;

      // 保存逻辑与生成记录页共用，保证两处行为一致
      final saved = await MediaSaver.save(
        context,
        bytes: bytes,
        filename: _current.path.split('/').last,
      );
      if (saved && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).gallerySaved)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).gallerySaveFailed),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(ctx).galleryDeleteTitle),
        content: Text(AppLocalizations.of(ctx).galleryDeleteBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(AppLocalizations.of(ctx).cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(AppLocalizations.of(ctx).delete),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      await GalleryStore.instance.deleteFile(_current.path);
      // 递增计数而不是带返回值回去：画廊页据此重扫，避免列表残留已删文件
      ref.read(galleryRevisionProvider.notifier).state++;
      if (mounted) Navigator.pop(context);
    }
  }

  void _handleZoomChanged(bool zoomed) {
    if (_zoomed == zoomed) return;
    setState(() => _zoomed = zoomed);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('${_currentIndex + 1} / ${widget.images.length}'),
        centerTitle: true,
        actions: [
          // 只有"这张图能反查到生成记录、且快照还在"时才出现——
          // 查不到就整个不建（不置灰），免得用户反复点、猜原因
          if (_canRunAgain)
            IconButton(
              icon: Icon(Icons.replay, color: context.stateSuccess),
              tooltip: AppLocalizations.of(context).historyRerun,
              onPressed: _runAgain,
            ),
          IconButton(
            icon: const Icon(Icons.share),
            tooltip: AppLocalizations.of(context).galleryShareTooltip,
            onPressed: _share,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
            tooltip: AppLocalizations.of(context).delete,
            onPressed: _delete,
          ),
        ],
      ),
      body: PageView.builder(
        controller: _pageController,
        // 放大态下禁止翻页：横拖应该平移图片，而不是滑走
        physics: _zoomed ? const NeverScrollableScrollPhysics() : null,
        onPageChanged: (idx) => setState(() {
          _currentIndex = idx;
          // 换页时清掉放大标记：新一页是新的缩放状态
          _zoomed = false;
          // 下一张可能来自另一条记录：重新反查，rail 与「再次运行」跟着变
          _syncTaskContext();
        }),
        itemCount: widget.images.length,
        itemBuilder: (context, index) {
          final image = Center(
            child: Image.file(widget.images[index], fit: BoxFit.contain),
          );
          return ZoomableImage(
            onZoomChanged: _handleZoomChanged,
            // 只给首帧挂 Hero：翻到第二张时不能有两个同标签的共享元素
            child: index == widget.initialIndex && widget.heroTag != null
                ? Hero(tag: widget.heroTag!, child: image)
                : image,
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildRail(context),
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: context.accent,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
                onPressed: _saving ? null : _saveToGallery,
                icon: _saving
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          color: context.onAccent,
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(Icons.save_alt),
                label: Text(
                  _saving
                      ? AppLocalizations.of(context).gallerySaving
                      : AppLocalizations.of(context).gallerySaveToAlbum,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 当前这张图能不能「再次运行」。
  ///
  /// 两个条件缺一不可：反查得到记录（`_task`）+ 那条记录的快照还在
  /// （用户可能在设置页把快照删了）。缺任一条就**不提供入口**。
  bool get _canRunAgain {
    final id = _task?.snapshotId;
    if (id == null) return false;
    return ref.read(snapshotProvider.notifier).exists(id);
  }

  Future<void> _runAgain() async {
    final task = _task;
    if (task == null) return;
    final l = AppLocalizations.of(context);
    // 画廊里点"再次运行"最容易被误解成"复现这张"：出图是随机的，说清楚一次
    await runTaskAgain(context, ref, task, notice: l.galleryRerunNotice);
  }

  /// 底部 rail：**只做入口**，不并入画廊的翻页。
  ///
  /// 画廊的 PageView 是"全库图片"的连续列表，而参考图是跟着当前页变的；
  /// 一旦并进去，页码会被不属于这一页的内容污染，翻到下一张还会凭空少几页。
  /// 所以点 rail 里的参考图 = 用单图查看器盖一层打开。
  Widget _buildRail(BuildContext context) {
    if (_refs.isEmpty) return const SizedBox.shrink();

    final items = <RailItem>[
      for (final ref in _refs)
        RailItem(
          thumb: _refThumb(ref),
          onTap: () => _openRef(ref),
        ),
    ];
    return ReferenceRail(items: items);
  }

  Widget _refThumb(ReferenceImage ref) {
    final base = _refBaseUrl;
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

  void _openRef(ReferenceImage ref) {
    final base = _refBaseUrl;
    if (base == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).historyRefServerRemoved),
        ),
      );
      return;
    }
    openImageViewer(
      context,
      url: imageViewUrl(base, ref.ref),
      title: ref.label,
    );
  }

  Future<void> _share() async {
    // 分享功能：Flutter 无内置，留待接入 share_plus 插件。
    // 当前先提示。
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).galleryShareSoon)),
      );
    }
  }
}
