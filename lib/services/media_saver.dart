import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:comfyui_mobilepocket/l10n/app_localizations.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';

import 'png_metadata_stripper.dart';

/// 统一的媒体保存入口：画廊页与生成记录页共用，保证行为一致。
///
/// - 图片：PNG 会先询问「保留内嵌工作流信息 / 剔除为普通图片」
/// - 视频：写入临时文件后走 Gal.putVideo
/// - 返回是否真的保存了（用户取消或权限被拒时为 false，便于调用方决定是否提示）
class MediaSaver {
  MediaSaver._();

  static const List<String> videoExts = ['mp4', 'webm', 'mov'];

  static Future<bool> save(
    BuildContext context, {
    required Uint8List bytes,
    required String filename,
  }) async {
    final hasAccess = await Gal.requestAccess();
    if (!hasAccess) {
      if (context.mounted) {
        _toast(context, AppLocalizations.of(context).saveAlbumPermission);
      }
      return false;
    }

    final ext = filename.contains('.')
        ? filename.split('.').last.toLowerCase()
        : 'png';

    if (videoExts.contains(ext)) {
      final tmpDir = await getTemporaryDirectory();
      final tmp = File(
        '${tmpDir.path}/tmp_save_${DateTime.now().millisecondsSinceEpoch}.$ext',
      );
      await tmp.writeAsBytes(bytes);
      try {
        await Gal.putVideo(tmp.path);
      } finally {
        try {
          await tmp.delete();
        } catch (_) {}
      }
      return true;
    }

    Uint8List finalBytes = bytes;
    if (ext == 'png') {
      if (!context.mounted) return false;
      final choice = await showMetadataChoice(context);
      if (choice == null) return false; // 用户取消
      if (choice == 'plain') {
        finalBytes = PngMetadataStripper.strip(bytes);
      }
    }

    await Gal.putImageBytes(
      finalBytes,
      name: 'comfy_${DateTime.now().millisecondsSinceEpoch}.$ext',
    );
    return true;
  }

  /// PNG 元数据保存方式选择：
  /// 返回 'with_workflow'（保留原图）或 'plain'（剔除元数据），取消为 null。
  static Future<String?> showMetadataChoice(BuildContext context) {
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(ctx).saveAlbumTitle),
        content: Text(AppLocalizations.of(ctx).saveAlbumBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(AppLocalizations.of(ctx).cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'plain'),
            child: Text(AppLocalizations.of(ctx).saveAlbumPlain),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.green),
            onPressed: () => Navigator.pop(ctx, 'with_workflow'),
            child: Text(AppLocalizations.of(ctx).saveAlbumWithWorkflow),
          ),
        ],
      ),
    );
  }

  static void _toast(BuildContext context, String text) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }
}
