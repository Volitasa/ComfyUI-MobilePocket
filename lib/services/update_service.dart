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

  /// HTTP 客户端。抽成可替换字段，便于测试注入 MockClient
  /// （本功能的失败分支——私有仓库 404、令牌失效、限流——都发生在这一层）。
  static http.Client client = http.Client();

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

  /// 查询最新 Release。
  /// [token] 用于访问私有仓库；为空则按匿名请求处理（仅公开仓库可用）。
  /// 没有可用安装包时抛 UpdateException。
  Future<ReleaseInfo> fetchLatestRelease({String? token}) async {
    final hasToken = token != null && token.trim().isNotEmpty;
    final latest = await _request(latestReleaseUrl, token: token);

    Map<String, dynamic>? data;
    if (latest.statusCode == 200 && latest.json is Map<String, dynamic>) {
      data = latest.json as Map<String, dynamic>;
    } else if (latest.statusCode == 404) {
      // 两种可能：① latest 接口排除草稿与预发布，仓库只发了这类；
      //           ② 仓库是私有的（GitHub 对无权限访问一律回 404，
      //              不会回 403，以免泄露仓库是否存在）。
      // 退回列表接口再找一次，用它的结果区分这两种情况。
      final list = await _request(releasesUrl, token: token);
      if (list.statusCode == 200 && list.json is List) {
        final items = (list.json as List)
            .whereType<Map<String, dynamic>>()
            .where((r) => r['draft'] != true)
            .toList();
        data = items.isEmpty ? null : items.first;
      } else if (list.statusCode == 404) {
        // 列表也 404 —— 基本可以断定是无权访问，而不是「没有发布」
        throw UpdateException(
          hasToken
              ? '仓库不可访问：请确认令牌对该仓库有 Contents 读取权限，且未过期'
              : '仓库不可访问。若该仓库是私有的，请在「设置 → GitHub 访问令牌」'
                  '中填入只读令牌后重试',
        );
      }
    } else if (latest.statusCode == 401) {
      // 仓库若已转为公开，清除令牌即可恢复匿名访问，不必重新生成
      throw UpdateException(
        'GitHub 令牌无效或已过期。可在「设置 → GitHub 访问令牌」中更新；'
        '若仓库已公开，直接清除令牌即可',
      );
    } else if (latest.statusCode == 403) {
      throw UpdateException(
        hasToken
            ? 'GitHub 拒绝了请求（令牌权限不足或触发限流），请稍后再试'
            : 'GitHub 接口访问受限（匿名请求每小时 60 次），配置访问令牌可放宽限额',
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
      assetApiUrl: (asset['url'] ?? '').toString(),
    );
  }

  /// 统一 GET：网络类异常直接转成可读的 UpdateException。
  /// 404 / 401 / 403 不抛异常，交由调用方按场景给出准确原因。
  Future<_ApiResp> _request(String url, {String? token}) async {
    try {
      final headers = <String, String>{
        'Accept': 'application/vnd.github+json',
        // GitHub 要求请求带 User-Agent，否则会拒绝
        'User-Agent': '$repoName-App',
      };
      final t = token?.trim();
      if (t != null && t.isNotEmpty) {
        headers['Authorization'] = 'Bearer $t';
      }

      final resp =
          await client.get(Uri.parse(url), headers: headers).timeout(_timeout);

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
  ///
  /// 私有仓库必须携带 [token]：此时走 API 资产地址拿 302，再对签名地址发起
  /// 不带 Authorization 的请求 —— 否则 S3 会因「只允许一种鉴权方式」而拒绝。
  Future<String> downloadApk(
    ReleaseInfo release, {
    required void Function(double progress) onProgress,
    String? token,
  }) async {
    final t = token?.trim();
    final useApi = t != null && t.isNotEmpty && release.assetApiUrl.isNotEmpty;
    final url = useApi ? release.assetApiUrl : release.downloadUrl;

    // 先校验地址再碰文件系统：配置缺失应该立刻报错，不必先建临时目录
    if (url.isEmpty) {
      throw UpdateException('安装包地址缺失，请稍后重试');
    }

    final dir = await getTemporaryDirectory();
    final savePath = '${dir.path}/update_${release.version}.apk';
    final file = File(savePath);

    http.StreamedResponse response;
    try {
      final request = http.Request('GET', Uri.parse(url));
      request.headers['User-Agent'] = '$repoName-App';
      if (useApi) {
        request.headers['Accept'] = 'application/octet-stream';
        request.headers['Authorization'] = 'Bearer $t';
        // 手动跟随重定向，避免把 Authorization 带给 S3 签名地址
        request.followRedirects = false;
      }

      response = await client.send(request).timeout(_timeout);

      final location = response.headers['location'];
      if (useApi &&
          response.statusCode >= 300 &&
          response.statusCode < 400 &&
          location != null) {
        final redirect = http.Request('GET', Uri.parse(location));
        redirect.headers['User-Agent'] = '$repoName-App';
        response = await client.send(redirect).timeout(_timeout);
      }
    } on TimeoutException {
      throw UpdateException('下载超时，请检查网络后重试');
    } on SocketException {
      throw UpdateException('下载失败，网络连接已中断');
    } catch (_) {
      throw UpdateException('下载失败，请检查网络后重试');
    }

    if (response.statusCode == 404) {
      throw UpdateException(
        useApi ? '安装包下载失败（404），请确认令牌仍有该仓库的读取权限' : '安装包下载失败（404）',
      );
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
