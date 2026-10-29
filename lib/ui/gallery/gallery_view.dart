import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:comfyui_mobilepocket/l10n/app_localizations.dart';

import '../../providers/gallery_revision_provider.dart';
import '../../services/gallery_store.dart';
import '../../services/media_saver.dart';

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
          ? const Center(child: CircularProgressIndicator())
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
      MaterialPageRoute(
        builder: (_) => _GalleryViewer(
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
        onPageChanged: (idx) => setState(() => _currentIndex = idx),
        itemCount: widget.images.length,
        itemBuilder: (context, index) {
          final image = Center(
            child: Image.file(widget.images[index], fit: BoxFit.contain),
          );
          return InteractiveViewer(
            // 只给首帧挂 Hero：翻到第二张时不能有两个同标签的共享元素
            child: index == widget.initialIndex && widget.heroTag != null
                ? Hero(tag: widget.heroTag!, child: image)
                : image,
          );
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
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ),
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
