import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:comfyui_mobilepocket/l10n/app_localizations.dart';
import 'package:comfyui_mobilepocket/l10n/app_localizations_zh.dart';
import 'package:comfyui_mobilepocket/models/release_info.dart';
import 'package:comfyui_mobilepocket/services/update_service.dart';

final AppLocalizations _l10n = AppLocalizationsZh();

/// 构造一个 release JSON
String _releaseJson({
  String tag = 'v1.0.6',
  List<Map<String, dynamic>>? assets,
}) {
  return jsonEncode({
    'tag_name': tag,
    'name': tag,
    'body': 'notes',
    'published_at': '2026-10-11T10:52:13Z',
    'assets':
        assets ??
        [
          {
            'name': 'app-release.apk',
            'size': 55967021,
            'url': 'https://api.github.com/repos/o/r/releases/assets/1',
            'browser_download_url':
                'https://github.com/o/r/releases/download/$tag/app-release.apk',
          },
        ],
  });
}

/// 记录每次请求的 URL 与 headers，便于断言是否带了令牌
class _Recorder {
  final List<Uri> urls = [];
  final List<Map<String, String>> headers = [];
}

UpdateService _service(
  _Recorder rec,
  Future<http.Response> Function(http.Request req) handler,
) {
  final previous = UpdateService.client;
  UpdateService.client = MockClient((req) async {
    rec.urls.add(req.url);
    rec.headers.add(req.headers);
    return handler(req);
  });
  addTearDown(() => UpdateService.client = previous);
  return UpdateService.instance;
}

void main() {
  group('私有仓库：匿名访问一律 404', () {
    test('latest 与列表都 404 且未配令牌 → 提示配置令牌，而不是说“没有发布版本”', () async {
      final rec = _Recorder();
      final service = _service(
        rec,
        (_) async => http.Response('Not Found', 404),
      );

      final err = await service
          .fetchLatestRelease(l10n: _l10n)
          .then<Object?>((r) => r)
          .catchError((Object e) => e);

      expect(err, isA<UpdateException>());
      final msg = (err as UpdateException).message;
      expect(msg, contains('私有'));
      expect(msg, contains('GitHub 访问令牌'));
      expect(msg, isNot(contains('还没有发布带安装包的版本')));
      // 确实重试列表接口后才判定
      expect(rec.urls.length, 2);
      expect(rec.urls.last.toString(), UpdateService.releasesUrl);
    });

    test('配了令牌仍 404 → 指向令牌权限问题', () async {
      final rec = _Recorder();
      final service = _service(
        rec,
        (_) async => http.Response('Not Found', 404),
      );

      final err = await service
          .fetchLatestRelease(token: 'github_pat_xxx', l10n: _l10n)
          .then<Object?>((r) => r)
          .catchError((Object e) => e);

      expect(err, isA<UpdateException>());
      expect((err as UpdateException).message, contains('Contents'));
    });

    test('带令牌时请求会附带 Authorization 头', () async {
      final rec = _Recorder();
      final service = _service(
        rec,
        (_) async => http.Response(_releaseJson(), 200),
      );

      await service.fetchLatestRelease(token: 'github_pat_abc123', l10n: _l10n);

      expect(rec.headers.first['Authorization'], 'Bearer github_pat_abc123');
    });

    test('未配置令牌时不发送 Authorization 头', () async {
      final rec = _Recorder();
      final service = _service(
        rec,
        (_) async => http.Response(_releaseJson(), 200),
      );

      await service.fetchLatestRelease(l10n: _l10n);

      expect(rec.headers.first.containsKey('Authorization'), false);
    });
  });

  group('错误码分支', () {
    test('401 → 令牌无效或已过期', () async {
      final rec = _Recorder();
      final service = _service(
        rec,
        (_) async => http.Response('Unauthorized', 401),
      );

      final err = await service
          .fetchLatestRelease(token: 'bad', l10n: _l10n)
          .then<Object?>((r) => r)
          .catchError((Object e) => e);

      expect((err as UpdateException).message, contains('令牌无效或已过期'));
    });

    test('401 后自动匿名重试：仓库转公开的老用户不必手动清令牌', () async {
      final rec = _Recorder();
      final service = _service(rec, (req) async {
        // 模拟「令牌已被回收，但仓库已公开」：带令牌一律 401，匿名正常
        if (req.headers.containsKey('Authorization')) {
          return http.Response('Unauthorized', 401);
        }
        return http.Response(_releaseJson(), 200);
      });

      final release = await service.fetchLatestRelease(
        token: 'github_pat_revoked',
        l10n: _l10n,
      );

      expect(release.version, '1.0.6');
      // 第一次带令牌被拒，第二次匿名成功
      expect(rec.urls.length, 2);
      expect(rec.headers.first['Authorization'], 'Bearer github_pat_revoked');
      expect(rec.headers.last.containsKey('Authorization'), false);
    });

    test('401 后匿名重试也 404 → 指向令牌本身，而不是“没有发布版本”', () async {
      final rec = _Recorder();
      final service = _service(rec, (req) async {
        if (req.headers.containsKey('Authorization')) {
          return http.Response('Unauthorized', 401);
        }
        return http.Response('Not Found', 404);
      });

      final err = await service
          .fetchLatestRelease(token: 'github_pat_revoked', l10n: _l10n)
          .then<Object?>((r) => r)
          .catchError((Object e) => e);

      final msg = (err as UpdateException).message;
      expect(msg, contains('令牌无效或已过期'));
      expect(msg, isNot(contains('还没有发布')));
    });

    test('403 且未配令牌 → 提到匿名限额与配置令牌', () async {
      final rec = _Recorder();
      final service = _service(
        rec,
        (_) async => http.Response('rate limited', 403),
      );

      final err = await service
          .fetchLatestRelease(l10n: _l10n)
          .then<Object?>((r) => r)
          .catchError((Object e) => e);

      final msg = (err as UpdateException).message;
      expect(msg, contains('60 次'));
      expect(msg, contains('访问令牌'));
    });

    test('latest 200 但列表为空时仍按“没有发布”处理', () async {
      final rec = _Recorder();
      final service = _service(rec, (req) async {
        if (req.url.toString() == UpdateService.latestReleaseUrl) {
          return http.Response('Not Found', 404);
        }
        return http.Response('[]', 200);
      });

      final err = await service
          .fetchLatestRelease(l10n: _l10n)
          .then<Object?>((r) => r)
          .catchError((Object e) => e);

      expect((err as UpdateException).message, contains('还没有发布带安装包的版本'));
    });
  });

  group('正常解析', () {
    test('解析出版本、安装包与 API 资产地址', () async {
      final rec = _Recorder();
      final service = _service(
        rec,
        (_) async => http.Response(_releaseJson(), 200),
      );

      final release = await service.fetchLatestRelease(l10n: _l10n);

      expect(release.version, '1.0.6');
      expect(release.tagName, 'v1.0.6');
      expect(release.assetName, 'app-release.apk');
      expect(release.sizeBytes, 55967021);
      expect(release.assetApiUrl, contains('/releases/assets/1'));
      expect(
        UpdateService.compareVersion(release.version, '1.0.4'),
        greaterThan(0),
      );
    });

    test('没有 apk 资产时抛出可读错误', () async {
      final rec = _Recorder();
      final service = _service(
        rec,
        (_) async => http.Response(
          _releaseJson(
            assets: [
              {
                'name': 'source.zip',
                'size': 10,
                'url': 'u',
                'browser_download_url': 'b',
              },
            ],
          ),
          200,
        ),
      );

      final err = await service
          .fetchLatestRelease(l10n: _l10n)
          .then<Object?>((r) => r)
          .catchError((Object e) => e);

      expect((err as UpdateException).message, contains('没有可安装的 APK'));
    });
  });

  group('下载', () {
    test('缺少任何地址时抛出可读错误', () async {
      final rec = _Recorder();
      final service = _service(rec, (_) async => http.Response('', 404));

      const empty = ReleaseInfo(
        version: '1.0.6',
        tagName: 'v1.0.6',
        name: 'v1.0.6',
        notes: '',
        publishedAt: null,
        assetName: '',
        sizeBytes: 0,
        downloadUrl: '',
        assetApiUrl: '',
      );

      final err = await service
          .downloadApk(empty, onProgress: (_) {}, l10n: _l10n)
          .then<Object?>((r) => r)
          .catchError((Object e) => e);

      expect((err as UpdateException).message, contains('安装包地址缺失'));
    });
  });
}
