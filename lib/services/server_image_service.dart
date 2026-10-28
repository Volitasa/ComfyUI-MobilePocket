import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'image_ref.dart';

/// 一次列目录的结果。
class ServerImageListing {
  const ServerImageListing({
    required this.images,
    this.degraded = false,
  });

  final List<ImageRef> images;

  /// true = `/internal/files` 用不了，列表改由 `/history` 反推
  /// （只能列出生成过的图，页面要如实说明）。
  final bool degraded;
}

/// 列服务器上的图片，给「从服务器选图」用。
///
/// 数据源按可靠性分两层：
/// 1. `GET /internal/files/{type}` —— 官方内部接口，能列整个目录、自带 `[output]` 注解、
///    服务端已按时间倒序。**官方 README 明示不保证稳定**，所以必须能降级。
/// 2. `GET /history` —— 只有生成过的图，但稳定。internal 404 / 超时 / 返回不是数组时用它。
class ServerImageService {
  ServerImageService({
    http.Client? client,
    this.timeout = const Duration(seconds: 6),
    this.historyTimeout = const Duration(seconds: 10),
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final Duration timeout;
  final Duration historyTimeout;

  /// 探测结论按服务器缓存：一个老版本服务端不该每开一次选图页就白等一次超时。
  /// value = true 表示 internal 可用。
  static final Map<String, bool> _internalUsable = {};

  /// 仅测试用：清掉探测缓存，避免用例互相污染。
  static void resetProbeCache() => _internalUsable.clear();

  Future<ServerImageListing> list(
    String baseUrl, {
    required String type,
  }) async {
    final base = baseUrl.replaceAll(RegExp(r'/+$'), '');
    if (_internalUsable[base] != false) {
      try {
        final internal = await _listInternal(base, type);
        _internalUsable[base] = true;
        return ServerImageListing(images: internal);
      } catch (_) {
        // 宁可降级也不要把整页报错给用户：老版本服务端只会在这一步失败
        _internalUsable[base] = false;
      }
    }
    final fallback = await _listFromHistory(base);
    return ServerImageListing(images: fallback, degraded: true);
  }

  Future<List<ImageRef>> _listInternal(String base, String type) async {
    final uri = Uri.parse('$base/internal/files/$type');
    final res = await _client.get(uri).timeout(timeout);
    if (res.statusCode != 200) {
      throw http.ClientException('internal/files ${res.statusCode}', uri);
    }
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    if (decoded is! List) {
      throw const FormatException('internal/files 返回的不是数组');
    }

    final out = <ImageRef>[];
    for (final item in decoded) {
      if (item is! String) continue;
      final ref = parseImageRef(item);
      if (ref == null || !isImageFilename(ref.filename)) continue;
      out.add(ref);
    }
    return out;
  }

  /// `/history` 的形状：`{promptId: {outputs: {nodeId: {images: [{filename, subfolder, type}]}}}}`
  Future<List<ImageRef>> _listFromHistory(String base) async {
    final uri = Uri.parse('$base/history?max_items=200');
    final res = await _client.get(uri).timeout(historyTimeout);
    if (res.statusCode != 200) {
      throw http.ClientException('history ${res.statusCode}', uri);
    }
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    if (decoded is! Map) throw const FormatException('history 返回的不是对象');

    final seen = <String>{};
    final out = <ImageRef>[];
    for (final entry in decoded.values) {
      if (entry is! Map) continue;
      final outputs = entry['outputs'];
      if (outputs is! Map) continue;
      for (final nodeOut in outputs.values) {
        if (nodeOut is! Map) continue;
        final images = nodeOut['images'];
        if (images is! List) continue;
        for (final img in images) {
          if (img is! Map) continue;
          final filename = img['filename'];
          if (filename is! String || !isImageFilename(filename)) continue;
          // 服务端理论上只回 input/output/temp，但不认识的值不能让它断言崩掉
          final rawType = img['type'];
          final type = (rawType == 'input' || rawType == 'output' || rawType == 'temp')
              ? rawType as String
              : 'output';
          final ref = ImageRef(
            filename: filename,
            subfolder: (img['subfolder'] as String?) ?? '',
            type: type,
          );
          if (seen.add(ref.value)) out.add(ref);
        }
      }
    }
    return out;
  }
}
