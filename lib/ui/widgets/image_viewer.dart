import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:comfyui_mobilepocket/l10n/app_localizations.dart';

import 'media_route.dart';
import 'zoomable_image.dart';

/// 单图全屏查看器：卡片里的缩略图小，看细节得点开这里。
///
/// 与画廊页 / 生成记录页那两个查看器分开：那两个绑着分享、删除、保存到相册、
/// 视频播放等业务操作，参数预览只需要「能放大看清楚」。
///
/// 纯黑底不跟随明暗主题 —— 看图场景要的是暗环境，代码里有意为之。
class FullscreenImageViewer extends StatelessWidget {
  const FullscreenImageViewer({
    super.key,
    this.bytes,
    this.url,
    this.title,
  });

  final Uint8List? bytes;
  final String? url;
  final String? title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: title == null
            ? null
            : Text(
                title!,
                style: const TextStyle(fontSize: 14),
                overflow: TextOverflow.ellipsis,
              ),
        centerTitle: true,
      ),
      body: SafeArea(
        // 双击放大走共用控件：手势仲裁、落点、复位都在里面处理
        child: ZoomableImage(
          maxScale: 6,
          child: Center(
            child: bytes != null
                ? Image.memory(bytes!)
                : Image.network(
                    url!,
                    loadingBuilder: (_, child, progress) {
                      if (progress == null) return child;
                      return const SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(
                          color: Colors.white54,
                          strokeWidth: 2,
                        ),
                      );
                    },
                    errorBuilder: (_, _, _) => Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        AppLocalizations.of(context).imageViewerLoadFailed,
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

/// 打开查看器。数据源二选一：本地字节（还没上传）或服务器地址。
void openImageViewer(
  BuildContext context, {
  Uint8List? bytes,
  String? url,
  String? title,
}) {
  Navigator.of(context).push<void>(
    // 与列表里的大图共用一个路由：黑底不会跟着转场一起切进来
    mediaViewerRoute(
      (_) => FullscreenImageViewer(bytes: bytes, url: url, title: title),
    ),
  );
}
