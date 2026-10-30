import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../image_ref.dart';
import 'ai_client.dart';

/// 取 ComfyUI 上的**原图**。缩略图会丢细节，换装/保姿势这类任务必须用原图。
///
/// 两种来源：
/// - 本地新选的图：调用方直接拿运行页内存里的原始字节，不经过这里；
/// - 服务器上的图：`/view` **不带 `preview`** 就是原文件（实测 1.23MB / 约 11ms）。
///
/// 缓存按 `(serverId, 图片引用)` 做 LRU（仅内存），「再来一版」不重复下载。
class OriginalImageFetcher {
  OriginalImageFetcher({
    this.client,
    this.cacheSize = 4,
    this.timeout = const Duration(seconds: 20),
  });

  /// 测试注入；为 null 时每次自建连接。
  final http.Client? client;
  final int cacheSize;
  final Duration timeout;

  final LinkedHashMap<String, Uint8List> _cache = LinkedHashMap();

  static String cacheKey(String serverId, ImageRef ref) =>
      '$serverId|${ref.value}';

  Future<Uint8List> fetch({
    required String baseUrl,
    required ImageRef ref,
    required String serverId,
  }) async {
    final key = cacheKey(serverId, ref);
    final hit = _cache.remove(key);
    if (hit != null) {
      _cache[key] = hit; // 命中后移到队尾，维持 LRU
      return hit;
    }

    final httpClient = client ?? http.Client();
    final owns = client == null;
    try {
      // ⚠️ 不加 preview：加了就是服务端转码后的小图
      final uri = Uri.parse(imageViewUrl(baseUrl, ref));
      final response = await httpClient.get(uri).timeout(timeout);
      if (response.statusCode != 200) {
        throw AiException(
          kind: response.statusCode == 404
              ? AiErrorKind.notFound
              : AiErrorKind.network,
          status: response.statusCode,
          detail: 'image ${response.statusCode}',
        );
      }
      final bytes = response.bodyBytes;
      if (bytes.isEmpty) {
        throw const AiException(
          kind: AiErrorKind.network,
          detail: 'empty image body',
        );
      }
      _cache[key] = bytes;
      while (_cache.length > cacheSize) {
        _cache.remove(_cache.keys.first);
      }
      return bytes;
    } on TimeoutException catch (e) {
      throw AiException(kind: AiErrorKind.timeout, detail: '$e');
    } on AiException {
      rethrow;
    } catch (e) {
      throw AiException(kind: AiErrorKind.network, detail: '$e');
    } finally {
      if (owns) httpClient.close();
    }
  }

  void clear() => _cache.clear();
}
