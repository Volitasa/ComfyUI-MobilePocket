import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../services/image_ref.dart';
import '../../services/server_image_service.dart';
import '../../services/throttled_image.dart';
import '../../theme.dart';
import '../widgets/page_title.dart';

/// 选图页每批「放出来」多少张。
///
/// 不是「一页只能看这么多」——`GridView.builder` 本来就只建可见项，这个数字
/// 是给**并发闸门**兜底的：滚得快时 Flutter 会连续建一批 item，
/// 若一次把 1117 张全交给列表，闸门里会排出上千个等待者，离开页面也清不干净。
const int kPickerBatchSize = 12;

/// 「从服务器选图」页：输出 / 输入两个目录各一页网格，点一张即返回 [ImageRef]。
///
/// 为什么不复用本地相册式的多选：ComfyUI 的图片参数只接受一张图，
/// 多选没有落点，反而多一步确认。
///
/// ⚠️ **性能约束（2026-10-29 定）**：所有缩略图都必须走
/// [ThrottledNetworkImage]（全局并发 3）。
/// ComfyUI 的 `/view?preview=` 是**同步转码**（真实 HTTP 实测 ≈250ms/张，
/// 与质量参数几乎无关），并发不设限会把服务端事件循环打满，
/// 最终触发 accept loop 崩溃 → 整个服务端连不上。见 `throttled_image.dart`。
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

  /// 已「放出来」给列表的张数。分批增长，见 [kPickerBatchSize]。
  int _visible = kPickerBatchSize;

  /// 分批节流：滚得快时每帧都触发，不加节流会一次放太多。
  DateTime _lastGrow = DateTime.fromMillisecondsSinceEpoch(0);

  /// 本页在并发闸门里的标识：离开时只取消自己的排队者，
  /// 不去打扰运行页 / 画廊正在加载的图。
  late final String _scope = 'picker:${widget.type}:${identityHashCode(this)}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    // 离开页面：把**还在排队**的缩略图请求全部作废（还没发出去的）。
    // ⚠️ 已经在飞的 3 个不打断 —— 主动断连会产生 RST，
    // 正是触发服务端 WinError 64 的那个动作。让它们自然跑完。
    ImageFetchGate.instance.cancelScope(_scope);
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
      _visible = kPickerBatchSize;
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

  /// 接近底部时再放一批出来。不用「加载更多」按钮：
  /// 这里限的是闸门排队长度，不是用户能看多少，打断滚动反而更烦。
  void _growVisible(int total) {
    if (_visible >= total) return;
    final now = DateTime.now();
    if (now.difference(_lastGrow) < const Duration(milliseconds: 200)) return;
    _lastGrow = now;
    setState(() => _visible = math.min(_visible + kPickerBatchSize, total));
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

    final total = listing.images.length;
    final shown = math.min(_visible, total);

    return Column(
      children: [
        if (listing.degraded) _DegradedNote(text: l.serverImageDegraded),
        Expanded(
          child: NotificationListener<ScrollNotification>(
            onNotification: (n) {
              if (n.metrics.pixels >= n.metrics.maxScrollExtent - 400) {
                _growVisible(total);
              }
              return false;
            },
            child: GridView.builder(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 6,
                crossAxisSpacing: 6,
              ),
              itemCount: shown,
              itemBuilder: (context, i) {
                final ref = listing.images[i];
                return _ThumbTile(
                  url: imageViewUrl(
                    widget.baseUrl,
                    ref,
                    // 保持 75：实测 q=75 与 q=50 的**服务端耗时几乎一样**
                    // （251ms vs 244ms，真实 HTTP 三轮复测 262 vs 252ms），
                    // 降质量只换来 25% 流量（31.5KB → 23.5KB），不值得牺牲画质。
                    preview: 'webp;75',
                  ),
                  scope: _scope,
                  onTap: () => Navigator.of(context).pop(ref),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// 网格里的一格：固定正方形 + cover 裁切（浏览场景要整齐好扫，
/// 跟卡片里"完整不裁切"的目标相反）。
class _ThumbTile extends StatelessWidget {
  const _ThumbTile({
    required this.url,
    required this.scope,
    required this.onTap,
  });

  final String url;
  final String scope;
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
          child: Image(
            // 一格约 110dp 宽，解到两倍足够清晰，又不会为缩略图吃满内存。
            // 尺寸交给 ResizeImage 算进缓存键，请求本身由 ThrottledNetworkImage 限流。
            image: ResizeImage(
              ThrottledNetworkImage(url, scope: scope),
              width: 240,
            ),
            fit: BoxFit.cover,
            // 被「页面已离开」取消的加载走这里，显示占位即可
            errorBuilder: (_, _, _) => Icon(
              Icons.broken_image_outlined,
              size: 22,
              color: context.iconMuted,
            ),
            frameBuilder: (context, child, frame, wasSync) {
              if (frame == null && !wasSync) return const SizedBox.shrink();
              return child;
            },
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
