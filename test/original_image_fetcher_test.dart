import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:comfyui_mobilepocket/services/ai/ai_client.dart';
import 'package:comfyui_mobilepocket/services/ai/original_image_fetcher.dart';
import 'package:comfyui_mobilepocket/services/image_ref.dart';

const ref = ImageRef(filename: 'a.png', type: 'input');

void main() {
  test('请求地址不带 preview（要原图）', () async {
    late Uri captured;
    final client = MockClient((request) async {
      captured = request.url;
      return http.Response.bytes(Uint8List.fromList([1, 2, 3]), 200);
    });

    final bytes = await OriginalImageFetcher(
      client: client,
    ).fetch(baseUrl: 'http://host:8190', ref: ref, serverId: 's1');

    expect(bytes, [1, 2, 3]);
    expect(captured.queryParameters.containsKey('preview'), isFalse);
    expect(captured.queryParameters['filename'], 'a.png');
    expect(captured.queryParameters['type'], 'input');
  });

  test('同一张图第二次走缓存，不再发请求', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      return http.Response.bytes(Uint8List.fromList([9]), 200);
    });
    final fetcher = OriginalImageFetcher(client: client);

    await fetcher.fetch(baseUrl: 'http://h', ref: ref, serverId: 's1');
    await fetcher.fetch(baseUrl: 'http://h', ref: ref, serverId: 's1');

    expect(calls, 1);
  });

  test('不同服务器视作不同缓存项', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      return http.Response.bytes(Uint8List.fromList([1]), 200);
    });
    final fetcher = OriginalImageFetcher(client: client);

    await fetcher.fetch(baseUrl: 'http://h', ref: ref, serverId: 'a');
    await fetcher.fetch(baseUrl: 'http://h', ref: ref, serverId: 'b');

    expect(calls, 2);
  });

  test('404 抛 notFound，且带状态码', () async {
    final client = MockClient((request) async => http.Response('gone', 404));
    await expectLater(
      OriginalImageFetcher(
        client: client,
      ).fetch(baseUrl: 'http://h', ref: ref, serverId: 's'),
      throwsA(
        isA<AiException>()
            .having((e) => e.kind, 'kind', AiErrorKind.notFound)
            .having((e) => e.status, 'status', 404),
      ),
    );
  });

  test('buildImageRef 目录注解被保留', () async {
    final outputRef = parseImageRef('x.png [output]')!;
    late Uri captured;
    final client = MockClient((request) async {
      captured = request.url;
      return http.Response.bytes(Uint8List.fromList([1]), 200);
    });

    await OriginalImageFetcher(
      client: client,
    ).fetch(baseUrl: 'http://h', ref: outputRef, serverId: 's');

    expect(captured.queryParameters['type'], 'output');
  });
}
