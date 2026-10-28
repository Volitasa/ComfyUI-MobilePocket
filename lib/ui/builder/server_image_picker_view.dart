import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../services/image_ref.dart';
import '../../services/server_image_service.dart';
import '../../theme.dart';
import '../widgets/page_title.dart';

/// 「从服务器选图」页：输出 / 输入两个目录各一页网格，点一张即返回 [ImageRef]。
///
/// 为什么不复用本地相册式的多选：ComfyUI 的图片参数只接受一张图，
/// 多选没有落点，反而多一步确认。
class ServerImagePickerView extends StatelessWidget {
  const ServerImagePickerView({
    super.key,
    required this.baseUrl,
    this.service,
  });

  final String baseUrl;

  /// 测试注入用；正常走默认实现
  final ServerImageService? service;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final svc = service ?? ServerImageService();

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l.serverImageTitle, style: kSubPageTitleStyle),
          bottom: TabBar(
            tabs: [
              Tab(text: l.serverImageTabOutput),
              Tab(text: l.serverImageTabInput),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _ImageGrid(
              key: const ValueKey('output'),
              baseUrl: baseUrl,
              type: 'output',
              service: svc,
            ),
            _ImageGrid(
              key: const ValueKey('input'),
              baseUrl: baseUrl,
              type: 'input',
              service: svc,
            ),
          ],
        ),
      ),
    );
  }
}

class _ImageGrid extends StatefulWidget {
  const _ImageGrid({
    super.key,
    required this.baseUrl,
    required this.type,
    required this.service,
  });

  final String baseUrl;
  final String type;
  final ServerImageService service;

  @override
  State<_ImageGrid> createState() => _ImageGridState();
}

class _ImageGridState extends State<_ImageGrid>
    with AutomaticKeepAliveClientMixin {
  // 切 Tab 不重新拉一次：两个目录都可能上千张
  @override
  bool get wantKeepAlive => true;

  ServerImageListing? _listing;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final listing = await widget.service.list(
        widget.baseUrl,
        type: widget.type,
      );
      if (!mounted) return;
      setState(() {
        _listing = listing;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _failed = true;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final l = AppLocalizations.of(context);

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_failed) {
      return _Hint(
        icon: Icons.cloud_off_outlined,
        text: l.serverImageFailed,
        action: TextButton(onPressed: _load, child: Text(l.serverImageRetry)),
      );
    }

    final listing = _listing!;
    if (listing.images.isEmpty) {
      return _Hint(
        icon: Icons.image_outlined,
        text: l.serverImageEmpty,
      );
    }

    return Column(
      children: [
        if (listing.degraded) _DegradedNote(text: l.serverImageDegraded),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
            ),
            itemCount: listing.images.length,
            itemBuilder: (context, i) {
              final ref = listing.images[i];
              return _ThumbTile(
                url: imageViewUrl(
                  widget.baseUrl,
                  ref,
                  preview: 'webp;75',
                ),
                onTap: () => Navigator.of(context).pop(ref),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// 网格里的一格：固定正方形 + cover 裁切（浏览场景要整齐好扫，
/// 跟卡片里"完整不裁切"的目标相反）。
class _ThumbTile extends StatelessWidget {
  const _ThumbTile({required this.url, required this.onTap});

  final String url;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: ColoredBox(
          color: context.containerFill,
          child: Image.network(
            url,
            fit: BoxFit.cover,
            // 一格约 110dp 宽，解到两倍足够清晰，又不会为缩略图吃满内存
            cacheWidth: 240,
            errorBuilder: (_, _, _) => Icon(
              Icons.broken_image_outlined,
              size: 22,
              color: context.iconMuted,
            ),
            loadingBuilder: (context, child, progress) =>
                progress == null ? child : const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }
}

class _DegradedNote extends StatelessWidget {
  const _DegradedNote({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      color: context.containerFill,
      child: Text(
        text,
        style: TextStyle(fontSize: 12, color: context.textSecondary),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.icon, required this.text, this.action});

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 40, color: context.iconMuted),
          const SizedBox(height: 12),
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: context.textSecondary),
          ),
          if (action != null) ...[const SizedBox(height: 4), action!],
        ],
      ),
    );
  }
}
