import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// 本地画廊存储服务：把生成的图片下载到 App 沙盒，保留原始文件
/// （内嵌 workflow/prompt 元数据，可拖回 ComfyUI 复现）。
class GalleryStore {
  GalleryStore._();
  static final GalleryStore instance = GalleryStore._();

  /// 仅测试用：指定根目录，跳过 `path_provider`。
  ///
  /// 走 path_provider 的话，widget 测试里得去 mock 平台通道（Windows 上还是
  /// ffi 实现的），为了测一个"能不能列出文件"不值当。生产代码不碰它。
  @visibleForTesting
  static Directory? debugDirectoryOverride;

  /// 仅测试用：清掉目录缓存（多个用例用不同根目录时必须调）。
  @visibleForTesting
  void resetCachedDir() => _dir = null;

  Directory? _dir;
  Future<Directory> _ensureDir() async {
    if (_dir != null) return _dir!;
    final docs = debugDirectoryOverride ?? await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/comfy_gallery');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _dir = dir;
    return dir;
  }

  /// 生成一个本地文件名（基于原文件名 + 时间戳，避免冲突）
  String localFileName(String remoteName) {
    final safe = remoteName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    return '${DateTime.now().millisecondsSinceEpoch}_$safe';
  }

  /// 把已下载的字节保存到本地，返回本地文件绝对路径
  Future<String> saveBytes(Uint8List bytes, String remoteName) async {
    final dir = await _ensureDir();
    final file = File('${dir.path}/${localFileName(remoteName)}');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  /// 删除本地文件（文件不存在时静默忽略）
  Future<void> deleteFile(String path) async {
    if (path.isEmpty) return;
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  /// 列出本地所有图片文件（按修改时间倒序）
  Future<List<File>> listImages() async {
    final dir = await _ensureDir();
    final files = await dir.list().where((e) => e is File).toList();
    final imgs = files.cast<File>().where((f) => _isImage(f.path)).toList();
    imgs.sort((a, b) => b.path.compareTo(a.path)); // 文件名含时间戳，倒序即最新在前
    return imgs;
  }

  bool _isImage(String path) {
    final ext = path.split('.').last.toLowerCase();
    return [
      'png',
      'jpg',
      'jpeg',
      'webp',
      'gif',
      'mp4',
      'webm',
      'mov',
    ].contains(ext);
  }
}
