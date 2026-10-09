import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import '../../providers/task_manager.dart';
import '../../services/gallery_store.dart';
import '../../services/png_metadata_stripper.dart';

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
    // 监听任务列表：新增生成图 / 删除记录（连带删图）后自动刷新画廊，
    // 避免列表残留已删除的文件导致保存时报错
    ref.listen(taskManagerProvider, (_, _) {
      _refresh();
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('画廊', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
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
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.photo_library_outlined, size: 48, color: Colors.grey),
                      SizedBox(height: 12),
                      Text('还没有生成图片', style: TextStyle(color: Colors.black54, fontSize: 16)),
                      SizedBox(height: 4),
                      Text('生成成功后图片会自动保存到这里', style: TextStyle(color: Colors.grey, fontSize: 12)),
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
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.file(
                            file,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => Container(
                              color: Colors.grey.shade200,
                              child: const Icon(Icons.broken_image, color: Colors.grey),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }

  void _openViewer(int index) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _GalleryViewer(
          images: _images,
          initialIndex: index,
        ),
      ),
    );
  }
}

/// 画廊大图查看器
class _GalleryViewer extends StatefulWidget {
  final List<File> images;
  final int initialIndex;
  const _GalleryViewer({required this.images, required this.initialIndex});

  @override
  State<_GalleryViewer> createState() => _GalleryViewerState();
}

class _GalleryViewerState extends State<_GalleryViewer> {
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
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('图片已不存在，请刷新画廊')));
        }
        return;
      }

      final hasAccess = await Gal.requestAccess();
      if (!hasAccess) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('需要相册权限')));
        return;
      }

      final bytes = await _current.readAsBytes();
      final ext = _current.path.split('.').last.toLowerCase();

      if (ext == 'png') {
        // PNG 支持元数据选择
        final choice = await _showMetadataChoice();
        if (choice == null) return; // 用户取消

        Uint8List finalBytes = bytes;
        if (choice == 'plain') {
          finalBytes = PngMetadataStripper.strip(bytes);
        }
        await Gal.putImageBytes(finalBytes, name: 'comfy_${DateTime.now().millisecondsSinceEpoch}.png');
      } else {
        // 视频走 putVideo，其它图片直接存
        if (['mp4', 'webm', 'mov'].contains(ext)) {
          final tmpDir = await getTemporaryDirectory();
          final tmp = File('${tmpDir.path}/tmp_$ext');
          await tmp.writeAsBytes(bytes);
          await Gal.putVideo(tmp.path);
          try {
            await tmp.delete();
          } catch (_) {}
        } else {
          await Gal.putImageBytes(bytes, name: 'comfy_${DateTime.now().millisecondsSinceEpoch}.$ext');
        }
      }
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ 已保存到手机相册')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('保存失败')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // 返回 'with_workflow' 或 'plain'，取消返回 null
  Future<String?> _showMetadataChoice() {
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('保存到相册'),
        content: const Text('这张 PNG 内嵌了工作流信息。选择保存方式：'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'plain'),
            child: const Text('普通图片（剔除信息）'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.green),
            onPressed: () => Navigator.pop(ctx, 'with_workflow'),
            child: const Text('带工作流原图'),
          ),
        ],
      ),
    );
  }

  void _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除图片'),
        content: const Text('确定从画廊删除这张图片吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      await GalleryStore.instance.deleteFile(_current.path);
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
            tooltip: '分享',
            onPressed: _share,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
            tooltip: '删除',
            onPressed: _delete,
          ),
        ],
      ),
      body: PageView.builder(
        controller: _pageController,
        onPageChanged: (idx) => setState(() => _currentIndex = idx),
        itemCount: widget.images.length,
        itemBuilder: (context, index) {
          return InteractiveViewer(
            child: Center(
              child: Image.file(widget.images[index], fit: BoxFit.contain),
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
            onPressed: _saving ? null : _saveToGallery,
            icon: _saving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.save_alt),
            label: Text(_saving ? '保存中...' : '保存到相册', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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
        const SnackBar(content: Text('分享功能即将上线')),
      );
    }
  }
}
