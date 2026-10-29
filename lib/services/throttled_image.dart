import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// 全局图片并发闸门。
///
/// **为什么必须全局、必须有上限**：ComfyUI 的 `/view?preview=` 是**在 async
/// handler 里同步**做 `Image.open` + `save(webp)` 的（`server.py`，没有
/// `run_in_executor`、没有缓存）。真实 HTTP 实测（960×1280 PNG）：
///
/// | 方式 | 耗时 | 体积 |
/// |---|---|---|
/// | `preview=webp;75` | **约 250ms** | 31.5KB |
/// | `preview=webp;50` | 约 250ms（**没有更快**）| 23.5KB |
/// | 不带 preview（`FileResponse`）| **约 11ms** | 1.23MB |
///
/// 也就是说每个带 preview 的请求都会独占一次 asyncio 事件循环 **250ms**，
/// 而质量参数对耗时几乎没有影响 —— 想省时间只能不转码（代价是流量）。
/// 这里选择保留转码 + 严格限流：不能假设用户都在千兆局域网。
///
/// 不设限的时候，滚动列表等于同时甩几十个连接过去：服务端 backlog 被占满，
/// 客户端等不到响应而超时断开 → Windows 侧 RST → `ProactorEventLoop.accept_coro`
/// 抛 `WinError 64` → accept loop 被终结 → 之后整个服务端「无法连接」，
/// 只能重启 ComfyUI。2026-10-29 实测确认过这条链。
///
/// 串行化**不会减少服务端的总 CPU 时间**（那是同步转码的固有成本），
/// 它保证的是**连接层不被自己打爆** —— 这才是真正让服务端挂掉的原因。
class ImageFetchGate {
  ImageFetchGate({this.maxConcurrent = kImageFetchConcurrency});

  /// 同时最多几个在飞。3 = 选图页正好一行。
  final int maxConcurrent;

  static final ImageFetchGate instance = ImageFetchGate();

  int _active = 0;
  final Queue<_GateWaiter> _waiters = Queue<_GateWaiter>();

  /// 仅测试用
  @visibleForTesting
  int get activeCount => _active;

  /// 仅测试用
  @visibleForTesting
  int get waitingCount => _waiters.length;

  /// 申请一个并发名额。
  ///
  /// 返回 true 表示可以发请求，用完必须 [release]；
  /// 返回 false 表示**该请求所属页面已经离开**，直接放弃即可（不要再发请求）。
  ///
  /// [scope] 用于「离开页面时只取消本页还在排队的请求」。
  Future<bool> acquire(String scope) async {
    if (_active < maxConcurrent) {
      _active++;
      return true;
    }
    final waiter = _GateWaiter(scope);
    _waiters.add(waiter);
    return waiter.completer.future;
  }

  /// 归还名额。**只有 acquire 返回 true 的调用方才能调这里。**
  void release() {
    if (_active > 0) _active--;
    _pump();
  }

  void _pump() {
    while (_active < maxConcurrent && _waiters.isNotEmpty) {
      final w = _waiters.removeFirst();
      _active++;
      w.completer.complete(true);
    }
  }

  /// 取消该 scope 名下**还在排队**的请求。
  ///
  /// ⚠️ 已经在飞的**不打断** —— 主动 abort 连接会产生 RST，正是把服务端
  /// accept loop 打挂的那个动作。让它们自然跑完（最多几个 × 200ms）。
  void cancelScope(String scope) {
    if (_waiters.isEmpty) return;
    final keep = Queue<_GateWaiter>();
    while (_waiters.isNotEmpty) {
      final w = _waiters.removeFirst();
      if (w.scope == scope) {
        w.completer.complete(false);
      } else {
        keep.add(w);
      }
    }
    _waiters.addAll(keep);
  }
}

/// 同时最多几个缩略图在飞。
const int kImageFetchConcurrency = 3;

/// 单张缩略图的整体超时。
///
/// 正常一张 `preview` 约 250ms；就算前面排了两个、服务端同时在跑生成任务，
/// 也在 2s 内。给到 10s 是「宁可慢也不要误杀」——
/// 太激进会主动断连，反而制造 RST（那正是把服务端 accept loop 打挂的动作）。
const Duration kImageFetchTimeout = Duration(seconds: 10);

class _GateWaiter {
  _GateWaiter(this.scope);
  final String scope;
  final Completer<bool> completer = Completer<bool>();
}

/// 被「页面已离开」取消掉的加载。会被 `errorBuilder` 吞掉，不冒泡成崩溃。
class ImageFetchCancelled implements Exception {
  const ImageFetchCancelled();
  @override
  String toString() => 'ImageFetchCancelled';
}

/// 带全局并发闸门和超时的网络图片。
///
/// 为什么不用 `Image.network`：它内部无法插队/限流，一旦 widget 建出来请求就
/// 出去了，滚动快的时候会瞬间发出几十个（`maxConnectionsPerHost` 默认无上限）。
///
/// 契约：同一个 [url] 的缓存键相同（[operator ==] 只比 url）——
/// 因此**不要**把 scope / timeout 算进相等性，否则同一个 URL 会被重复下载。
/// 需要不同解码尺寸时套 `ResizeImage`，由它负责把尺寸算进缓存键。
@immutable
class ThrottledNetworkImage extends ImageProvider<ThrottledNetworkImage> {
  const ThrottledNetworkImage(
    this.url, {
    this.scope = '',
    this.timeout = kImageFetchTimeout,
  });

  final String url;

  /// 发起方标识，仅用于「离开页面时取消本页排队中的请求」。
  final String scope;

  final Duration timeout;

  static final HttpClient _client = () {
    final c = HttpClient();
    // 略大于闸门上限，留出余量；真正的限流在 ImageFetchGate
    c.maxConnectionsPerHost = kImageFetchConcurrency + 3;
    c.connectionTimeout = const Duration(seconds: 8);
    c.idleTimeout = const Duration(seconds: 15);
    c.userAgent = 'comfyui_mobilepocket';
    return c;
  }();

  @override
  Future<ThrottledNetworkImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<ThrottledNetworkImage>(this);

  @override
  ImageStreamCompleter loadImage(
    ThrottledNetworkImage key,
    ImageDecoderCallback decode,
  ) {
    return MultiFrameImageStreamCompleter(
      codec: _loadAsync(key, decode),
      scale: 1,
      debugLabel: key.url,
      informationCollector: () => <DiagnosticsNode>[
        DiagnosticsProperty<ImageProvider>('Image provider', this),
        DiagnosticsProperty<String>('URL', url),
      ],
    );
  }

  Future<ui.Codec> _loadAsync(
    ThrottledNetworkImage key,
    ImageDecoderCallback decode,
  ) async {
    final gate = ImageFetchGate.instance;
    final granted = await gate.acquire(scope);
    if (!granted) {
      // 页面已经离开：不要发请求，交给 errorBuilder 显示占位
      throw const ImageFetchCancelled();
    }
    try {
      final bytes = await _fetch(key.url, key.timeout);
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      return await decode(buffer);
    } finally {
      gate.release();
    }
  }

  Future<Uint8List> _fetch(String url, Duration timeout) async {
    final uri = Uri.parse(url);
    final request = await _client.getUrl(uri).timeout(timeout);
    try {
      final response = await request.close().timeout(timeout);
      if (response.statusCode != HttpStatus.ok) {
        throw NetworkImageLoadException(
          statusCode: response.statusCode,
          uri: uri,
        );
      }
      final builder = BytesBuilder(copy: false);
      await for (final chunk in response.timeout(timeout)) {
        builder.add(chunk);
      }
      return builder.takeBytes();
    } catch (_) {
      // 超时 / 出错时把连接收掉，别把 socket 挂在服务端
      request.abort();
      rethrow;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is ThrottledNetworkImage && other.url == url;

  @override
  int get hashCode => url.hashCode;

  @override
  String toString() => 'ThrottledNetworkImage("$url")';
}
