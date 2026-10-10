import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../models/release_info.dart';

/// 接口返回的原始结果（状态码 + 已解析的 JSON）
class _ApiResp {
  final int statusCode;
  final dynamic json;
  const _ApiResp(this.statusCode, this.json);
}

/// 更新失败的可读原因，直接展示给用户。
class UpdateException implements Exception {
  final String message;
  UpdateException(this.message);

  @override
  String toString() => message;
}

/// 从 GitHub Releases 查询最新版本并下载安装包。
class UpdateService {
  UpdateService._();

  static final UpdateService instance = UpdateService._();

  // 仓库地址集中在此，将来换仓库/换镜像只改这里
  static const String repoOwner = 'Volitasa';
  static const String repoName = 'ComfyUI-MobilePocket';

  static const String latestReleaseUrl =
      'https://api.github.com/repos/$repoOwner/$repoName/releases/latest';
  static const String releasesUrl =
      'https://api.github.com/repos/$repoOwner/$repoName/releases';
  static const String repoHomeUrl =
      'https://github.com/$repoOwner/$repoName';

  static const Duration _timeout = Duration(seconds: 20);

  /// 查询最新 Release。没有可用安装包时抛 UpdateException。
  Future<ReleaseInfo> fetchLatestRelease() async {
    final latest = await _request(latestReleaseUrl);

    Map<String, dynamic>? data;
    if (latest.statusCode == 200 && latest.json is Map<String, dynamic>) {
      data = latest.json as Map<String, dynamic>;
    } else if (latest.statusCode == 404) {
      // latest 接口会排除草稿与预发布版本：仓库可能只有这类发布。
      // 退回列表接口再找一次，避免把「没有 latest」误报成「没发过版本」。
      final list = await _request(releasesUrl);
      if (list.statusCode == 200 && list.json is List) {
        final items = (list.json as List)
            .whereType<Map<String, dynamic>>()
            .where((r) => r['draft'] != true)
            .toList();
        data = items.isEmpty ? null : items.first;
      }
    } else if (latest.statusCode == 403) {
      throw UpdateException(
        'GitHub 接口访问受限（未认证请求每小时 60 次），请稍后再试',
      );
    } else if (latest.statusCode != 200) {
      throw UpdateException('查询更新失败（HTTP ${latest.statusCode}）');
    }

    if (data == null) {
      // 注意：git tag 不等于 GitHub Release，只有 Release 才带安装包
      throw UpdateException(
        '该仓库还没有发布带安装包的版本（仅有 git tag 不会被识别）',
      );
    }

    final decoded = data;

    final tag = (decoded['tag_name'] ?? '').toString();
    final version = normalizeVersion(tag);
    if (version.isEmpty) {
      throw UpdateException('发布版本号无法识别（$tag）');
    }

    final asset = _pickApkAsset(decoded['assets']);

    return ReleaseInfo(
      version: version,
      tagName: tag,
      name: (decoded['name'] ?? tag).toString(),
      notes: (decoded['body'] ?? '').toString().trim(),
      publishedAt: DateTime.tryParse((decoded['published_at'] ?? '').toString()),
      assetName: (asset['name'] ?? '').toString(),
      sizeBytes: (asset['size'] is num) ? (asset['size'] as num).toInt() : 0,
      downloadUrl: (asset['browser_download_url'] ?? '').toString(),
    );
  }

  /// 统一 GET：网络类异常直接转成可读的 UpdateException。
  /// 404 不抛异常，交由调用方决定是否回退到列表接口。
  Future<_ApiResp> _request(String url) async {
    try {
      final resp = await http
          .get(
            Uri.parse(url),
            headers: {
              'Accept': 'application/vnd.github+json',
              // GitHub 要求请求带 User-Agent，否则会拒绝
              'User-Agent': '$repoName-App',
            },
          )
          .timeout(_timeout);

      dynamic json;
      if (resp.body.isNotEmpty) {
        try {
          json = jsonDecode(resp.body);
        } catch (_) {
          json = null;
        }
      }
      return _ApiResp(resp.statusCode, json);
    } on TimeoutException {
      throw UpdateException('连接 GitHub 超时，请检查网络后重试');
    } on SocketException {
      throw UpdateException('无法连接 GitHub，请检查网络后重试');
    } catch (_) {
      throw UpdateException('查询更新失败，请检查网络后重试');
    }
  }

  /// 选择安装包：只有一个 APK 就直接用；多个时优先 arm64（绝大多数现代机型）。
  Map<String, dynamic> _pickApkAsset(dynamic assets) {
    if (assets is! List) {
      throw UpdateException('该版本没有附带安装包');
    }
    final apks = assets
        .whereType<Map<String, dynamic>>()
        .where((a) => (a['name'] ?? '').toString().toLowerCase().endsWith('.apk'))
        .toList();

    if (apks.isEmpty) {
      throw UpdateException('该版本没有可安装的 APK');
    }
    if (apks.length == 1) return apks.first;

    for (final a in apks) {
      final n = (a['name'] ?? '').toString().toLowerCase();
      if (n.contains('arm64') || n.contains('arm64-v8a')) return a;
    }
    return apks.first;
  }

  /// 下载安装包到应用缓存目录，通过 onProgress 回报 0.0~1.0。
  /// 返回本地文件路径（缓存目录，open_filex 的 FileProvider 已覆盖该路径）。
  Future<String> downloadApk(
    ReleaseInfo release, {
    required void Function(double progress) onProgress,
  }) async {
    final dir = await getTemporaryDirectory();
    final savePath = '${dir.path}/update_${release.version}.apk';
    final file = File(savePath);

    final request = http.Request('GET', Uri.parse(release.downloadUrl));
    request.headers['User-Agent'] = '$repoName-App';

    http.StreamedResponse response;
    try {
      response = await request.send().timeout(_timeout);
    } on TimeoutException {
      throw UpdateException('下载超时，请检查网络后重试');
    } on SocketException {
      throw UpdateException('下载失败，网络连接已中断');
    } catch (_) {
      throw UpdateException('下载失败，请检查网络后重试');
    }

    if (response.statusCode != 200) {
      throw UpdateException('下载失败（HTTP ${response.statusCode}）');
    }

    final total = response.contentLength ?? 0;
    final sink = file.openWrite();
    int received = 0;

    try {
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) {
          onProgress((received / total).clamp(0.0, 1.0));
        }
      }
    } catch (_) {
      throw UpdateException('下载中断，请重试');
    } finally {
      await sink.flush();
      await sink.close();
    }

    if (!await file.exists()) {
      throw UpdateException('安装包写入失败');
    }
    return savePath;
  }

  /// 去掉 v 前缀与 +build 后缀，得到纯版本号。
  static String normalizeVersion(String raw) {
    var v = raw.trim();
    if (v.startsWith('v') || v.startsWith('V')) v = v.substring(1);
    final plus = v.indexOf('+');
    if (plus >= 0) v = v.substring(0, plus);
    return v.trim();
  }

  /// 语义化版本比较：a > b 返回正数，相等返回 0。
  static int compareVersion(String a, String b) {
    final pa = _parts(a);
    final pb = _parts(b);
    final len = pa.length > pb.length ? pa.length : pb.length;
    for (var i = 0; i < len; i++) {
      final x = i < pa.length ? pa[i] : 0;
      final y = i < pb.length ? pb[i] : 0;
      if (x != y) return x.compareTo(y);
    }
    return 0;
  }

  static List<int> _parts(String v) {
    final s = normalizeVersion(v);
    if (s.isEmpty) return const [0];
    return s
        .split(RegExp(r'[.-]'))
        .map((e) => int.tryParse(e) ?? 0)
        .toList();
  }
}
