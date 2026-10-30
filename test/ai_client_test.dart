import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:comfyui_mobilepocket/models/ai_provider_config.dart';
import 'package:comfyui_mobilepocket/services/ai/ai_client.dart';

const provider = AiProviderConfig(
  id: 't',
  name: 't',
  baseUrl: 'https://example.test',
  model: 'm',
  apiKey: 'sk-test',
  temperature: 0.2,
  maxTokens: 64,
  timeoutSec: 5,
);

void main() {
  test('SSE 分块解析并按顺序拼接', () async {
    final client = MockClient.streaming((request, body) async {
      final chunks = [
        'data: {"choices":[{"delta":{"content":"你"}}]}\n',
        '\ndata: {"choices":[{"delta":{"content":"好"}}]}\n\n',
        'data: [DONE]\n\n',
      ].map(utf8.encode).toList();
      return http.StreamedResponse(Stream.fromIterable(chunks), 200);
    });

    final text = await AiClient(
      client: client,
    ).streamChat(provider: provider, systemPrompt: 's', userParts: [
      {'type': 'text', 'text': 'u'},
    ]).join();

    expect(text, '你好');
  });

  test('把响应里的 model 透出来', () async {
    String? seen;
    final client = MockClient.streaming((request, body) async {
      return http.StreamedResponse(
        Stream.value(
          utf8.encode(
            'data: {"model":"m-1","choices":[{"delta":{"content":"x"}}]}\n\ndata: [DONE]\n\n',
          ),
        ),
        200,
      );
    });
    await AiClient(client: client).streamChat(
      provider: provider,
      systemPrompt: 's',
      userParts: const [],
      onModel: (m) => seen = m,
    ).drain<void>();
    expect(seen, 'm-1');
  });

  test('请求头带 Bearer，body 含模型与 system/user', () async {
    late http.Request captured;
    final client = MockClient.streaming((request, body) async {
      captured = request as http.Request;
      return http.StreamedResponse(
        Stream.value(utf8.encode('data: [DONE]\n\n')),
        200,
      );
    });

    await AiClient(
      client: client,
    ).streamChat(provider: provider, systemPrompt: 'SYS', userParts: [
      {'type': 'text', 'text': 'USER'},
    ]).drain<void>();

    expect(captured.url.toString(), 'https://example.test/chat/completions');
    expect(captured.headers['Authorization'], 'Bearer sk-test');
    final body = jsonDecode(captured.body) as Map<String, dynamic>;
    expect(body['model'], 'm');
    expect(body['stream'], true);
    expect(body['max_tokens'], 64);
    final messages = body['messages'] as List;
    expect((messages.first as Map)['content'], 'SYS');
    expect((messages.last as Map)['role'], 'user');
  });

  test('401 映射为 unauthorized 并带服务端原文', () async {
    final client = MockClient.streaming((request, body) async {
      return http.StreamedResponse(
        Stream.value(utf8.encode('{"error":"invalid key"}')),
        401,
      );
    });

    await expectLater(
      AiClient(
        client: client,
      ).streamChat(provider: provider, systemPrompt: 's', userParts: []).drain<void>(),
      throwsA(
        isA<AiException>()
            .having((e) => e.kind, 'kind', AiErrorKind.unauthorized)
            .having((e) => e.status, 'status', 401)
            .having((e) => e.detail, 'detail', contains('invalid key')),
      ),
    );
  });

  test('429 映射为 rateLimited', () async {
    final client = MockClient.streaming((request, body) async {
      return http.StreamedResponse(const Stream.empty(), 429);
    });
    await expectLater(
      AiClient(
        client: client,
      ).streamChat(provider: provider, systemPrompt: 's', userParts: []).drain<void>(),
      throwsA(isA<AiException>().having((e) => e.kind, 'kind', AiErrorKind.rateLimited)),
    );
  });

  test('服务端忽略 stream 回整包 JSON 时仍能取到内容', () async {
    final client = MockClient.streaming((request, body) async {
      return http.StreamedResponse(
        Stream.value(
          utf8.encode(
            '{"choices":[{"message":{"role":"assistant","content":"整包结果"}}]}',
          ),
        ),
        200,
      );
    });

    final text = await AiClient(
      client: client,
    ).streamChat(provider: provider, systemPrompt: 's', userParts: []).join();
    expect(text, '整包结果');
  });

  test('图片 MIME 按文件头判断', () {
    expect(imageMimeOf([0x89, 0x50, 0x4E, 0x47, 1]), 'image/png');
    expect(imageMimeOf([0xFF, 0xD8, 0xFF, 1]), 'image/jpeg');
    expect(imageMimeOf([0x47, 0x49, 0x46, 1]), 'image/gif');
  });
}
