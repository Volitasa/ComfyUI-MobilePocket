import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:comfyui_mobilepocket/services/server_image_service.dart';

const _base = 'http://h:8190';

http.Response _json(Object body) => http.Response(
  jsonEncode(body),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  setUp(ServerImageService.resetProbeCache);

  test('internal 可用时按目录列，过滤占位文件、丢掉非图片', () async {
    final service = ServerImageService(
      client: MockClient((req) async {
        expect(req.url.path, '/internal/files/output');
        return _json([
          'ComfyUI_2.png [output]',
          'ComfyUI_1.png [output]',
          '_output_images_will_be_put_here',
          'notes.txt [output]',
        ]);
      }),
    );

    final listing = await service.list(_base, type: 'output');
    expect(listing.degraded, isFalse);
    expect(listing.images.map((e) => e.filename), ['ComfyUI_2.png', 'ComfyUI_1.png']);
    // 服务端已按时间倒序，客户端不再排
    expect(listing.images.first.type, 'output');
  });

  test('internal 404 时降级到 /history，并标记 degraded', () async {
    var internalCalls = 0;
    final service = ServerImageService(
      client: MockClient((req) async {
        if (req.url.path.startsWith('/internal/')) {
          internalCalls++;
          return http.Response('not found', 404);
        }
        expect(req.url.path, '/history');
        return _json({
          'p1': {
            'outputs': {
              '9': {
                'images': [
                  {'filename': 'a.png', 'subfolder': '', 'type': 'output'},
                  {'filename': 'b.png', 'subfolder': 'sub', 'type': 'output'},
                  // 同一张图在两个任务里各出现一次，不能重复列
                  {'filename': 'a.png', 'subfolder': '', 'type': 'output'},
                  {'filename': 'bad.txt', 'subfolder': '', 'type': 'output'},
                ],
              },
            },
          },
        });
      }),
    );

    final listing = await service.list(_base, type: 'input');
    expect(listing.degraded, isTrue);
    expect(listing.images.map((e) => e.value), [
      'a.png [output]',
      'sub/b.png [output]',
    ]);

    // 探测结果按服务器缓存：再开一次不要再撞 404
    await service.list(_base, type: 'output');
    expect(internalCalls, 1);
  });

  test('internal 返回的不是数组也降级', () async {
    final service = ServerImageService(
      client: MockClient((req) async {
        if (req.url.path.startsWith('/internal/')) return _json({'oops': 1});
        return _json({});
      }),
    );

    final listing = await service.list(_base, type: 'output');
    expect(listing.degraded, isTrue);
    expect(listing.images, isEmpty);
  });

  test('两层都挂时抛错，由页面显示重试', () async {
    final service = ServerImageService(
      client: MockClient((req) async => http.Response('boom', 500)),
    );

    await expectLater(
      service.list(_base, type: 'output'),
      throwsA(isA<http.ClientException>()),
    );
  });

  test('不认识的历史 type 兜底成 output，不触发断言', () async {
    final service = ServerImageService(
      client: MockClient((req) async {
        if (req.url.path.startsWith('/internal/')) {
          return http.Response('', 404);
        }
        return _json({
          'p1': {
            'outputs': {
              '9': {
                'images': [
                  {'filename': 'a.png', 'subfolder': '', 'type': 'weird'},
                ],
              },
            },
          },
        });
      }),
    );

    final listing = await service.list(_base, type: 'output');
    expect(listing.images.single.type, 'output');
  });
}
