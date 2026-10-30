import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../models/ai_provider_config.dart';

/// 失败分类。UI 按它决定文案与「下一步动作」，不在调用点拼字符串。
enum AiErrorKind {
  /// 401 / 403
  unauthorized,

  /// 404：地址或模型名不对
  notFound,

  /// 429
  rateLimited,

  /// 5xx
  server,

  /// 连不上
  network,

  /// 超时
  timeout,

  /// 其它 4xx（含「该模型不支持图片」这类）
  badRequest,
}

class AiException implements Exception {
  const AiException({
    required this.kind,
    this.status,
    this.detail = '',
  });

  final AiErrorKind kind;
  final int? status;

  /// 服务端原文。只用于小字展示，**绝不包含我们的 apiKey**。
  final String detail;

  @override
  String toString() => 'AiException($kind, status=$status)';
}

AiErrorKind _kindFor(int status) {
  if (status == 401 || status == 403) return AiErrorKind.unauthorized;
  if (status == 404) return AiErrorKind.notFound;
  if (status == 429) return AiErrorKind.rateLimited;
  if (status >= 500) return AiErrorKind.server;
  return AiErrorKind.badRequest;
}

/// 按文件头判断 MIME。供应商按内容嗅探，但 data URL 里写对更稳妥。
String imageMimeOf(List<int> bytes) {
  bool startsWith(List<int> sig, [int offset = 0]) {
    if (bytes.length < offset + sig.length) return false;
    for (var i = 0; i < sig.length; i++) {
      if (bytes[offset + i] != sig[i]) return false;
    }
    return true;
  }

  if (startsWith(const [0x89, 0x50, 0x4E, 0x47])) return 'image/png';
  if (startsWith(const [0xFF, 0xD8, 0xFF])) return 'image/jpeg';
  if (startsWith(const [0x47, 0x49, 0x46])) return 'image/gif';
  if (startsWith(const [0x52, 0x49, 0x46, 0x46]) &&
      startsWith(const [0x57, 0x45, 0x42, 0x50], 8)) {
    return 'image/webp';
  }
  return 'image/png';
}

/// OpenAI 兼容的流式客户端。
///
/// 只做三件事：拼请求、按行解析 SSE、把失败归一成 [AiException]。
/// 业务语义（模板、上下文、校验）放在 payload builder 与 UI 里。
class AiClient {
  AiClient({this.client});

  /// 测试注入。为 null 时每次请求自建连接并在结束时关闭。
  final http.Client? client;

  /// 一次对话。文本增量逐块 yield，结束后返回自然结束。
  ///
  /// [userParts] 是 OpenAI 的 content 数组（text / image_url 混排），
  /// 图片块只能出现在 user 消息里。
  Stream<String> streamChat({
    required AiProviderConfig provider,
    required String systemPrompt,
    required List<Map<String, dynamic>> userParts,
    void Function(String model)? onModel,
  }) async* {
    final httpClient = client ?? http.Client();
    final ownsClient = client == null;
    final timeout = Duration(seconds: provider.timeoutSec);

    final body = <String, dynamic>{
      'model': provider.model,
      'stream': true,
      'temperature': provider.temperature,
      'max_tokens': provider.maxTokens,
      'messages': [
        {'role': 'system', 'content': systemPrompt},
        {'role': 'user', 'content': userParts},
      ],
    };

    final request = http.Request('POST', Uri.parse(provider.endpoint))
      ..headers.addAll({
        'Content-Type': 'application/json',
        'Accept': 'text/event-stream',
        if (provider.apiKey.trim().isNotEmpty)
          'Authorization': 'Bearer ${provider.apiKey.trim()}',
      })
      ..body = jsonEncode(body);

    final raw = StringBuffer();
    var sawEvent = false;
    var reportedModel = false;

    try {
      final response = await httpClient.send(request).timeout(timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final text = await response.stream.bytesToString();
        throw AiException(
          kind: _kindFor(response.statusCode),
          status: response.statusCode,
          detail: text,
        );
      }

      final lines = response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .timeout(timeout);

      await for (final line in lines) {
        raw.write(line);
        raw.write('\n');
        if (!line.startsWith('data:')) continue;

        final data = line.substring(5).trim();
        if (data.isEmpty) continue;
        if (data == '[DONE]') {
          sawEvent = true;
          break;
        }
        sawEvent = true;
        // 供应商会在每个事件里带 `model`。把它透出来，界面才能回答
        // 「这次到底是谁跑的」——`deepseek-chat` 这类是别名，不是具体快照。
        if (!reportedModel) {
          final name = _modelOf(data);
          if (name != null && name.isNotEmpty) {
            reportedModel = true;
            onModel?.call(name);
          }
        }
        final delta = _deltaOf(data);
        if (delta != null && delta.isNotEmpty) yield delta;
      }

      // 有些兼容服务忽略 stream:true，直接回整包 JSON。这时没有 data: 行，
      // 用累积的原文兜底解析一次，避免"什么都没返回"。
      if (!sawEvent) {
        final whole = _contentOfWholeBody(raw.toString());
        if (whole != null && whole.isNotEmpty) yield whole;
      }
    } on TimeoutException catch (e) {
      throw AiException(kind: AiErrorKind.timeout, detail: '$e');
    } on AiException {
      rethrow;
    } on http.ClientException catch (e) {
      throw AiException(kind: AiErrorKind.network, detail: e.message);
    } catch (e) {
      // SocketException 在 web 上类型不同，这里统一按网络错误处理
      throw AiException(kind: AiErrorKind.network, detail: '$e');
    } finally {
      if (ownsClient) httpClient.close();
    }
  }

  /// 取事件里的 `model` 字段（供应商实际使用的模型名）。
  static String? _modelOf(String data) {
    try {
      final json = jsonDecode(data);
      if (json is Map && json['model'] is String) {
        return json['model'] as String;
      }
    } catch (_) {}
    return null;
  }

  /// 解析一个 `data:` 负载，取 `choices[0].delta.content`。
  static String? _deltaOf(String data) {
    try {
      final json = jsonDecode(data);
      if (json is! Map) return null;
      final choices = json['choices'];
      if (choices is! List || choices.isEmpty) return null;
      final first = choices.first;
      if (first is! Map) return null;
      final delta = first['delta'];
      if (delta is Map) {
        final content = delta['content'];
        if (content is String) return content;
      }
      // 少数服务把增量放在 message.content（非流式兼容模式）
      final message = first['message'];
      if (message is Map && message['content'] is String) {
        return message['content'] as String;
      }
    } catch (_) {
      // 单条事件坏了不该中断整个流
    }
    return null;
  }

  /// 整包 JSON（非流式响应）的兜底解析。
  static String? _contentOfWholeBody(String text) {
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start < 0 || end <= start) return null;
    try {
      final json = jsonDecode(text.substring(start, end + 1));
      if (json is! Map) return null;
      final choices = json['choices'];
      if (choices is! List || choices.isEmpty) return null;
      final message = (choices.first as Map)['message'];
      if (message is Map && message['content'] is String) {
        return message['content'] as String;
      }
    } catch (_) {}
    return null;
  }
}
