import 'dart:convert';

import '../../models/ai_task.dart';

/// 解析模型返回。**容错优先**：拿不到结构化就退回纯文本，绝不因为格式问题丢结果。
///
/// 处理顺序：
/// 1. 去掉首尾的 ``` 围栏；
/// 2. 取第一个 `{` 到最后一个 `}`；
/// 3. 解 JSON → `patches` 必须是非空数组且每项含 node/key/value 字符串。
AiTaskResult parseAiResult(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return AiTaskResult.empty;

  final unfenced = _stripFence(text);
  final start = unfenced.indexOf('{');
  final end = unfenced.lastIndexOf('}');

  if (start >= 0 && end > start) {
    final jsonText = unfenced.substring(start, end + 1);
    try {
      final decoded = jsonDecode(jsonText);
      final patches = _patchesOf(decoded);
      if (patches.isNotEmpty) {
        return AiTaskResult(
          rawText: text,
          patches: patches,
          notes: _notesOf(decoded),
          structured: true,
        );
      }
    } catch (_) {
      // 落到纯文本
    }
  }

  return AiTaskResult(rawText: text, patches: const []);
}

String _stripFence(String text) {
  var t = text;
  if (t.startsWith('```')) {
    final firstLineEnd = t.indexOf('\n');
    t = firstLineEnd >= 0 ? t.substring(firstLineEnd + 1) : '';
  }
  if (t.endsWith('```')) {
    t = t.substring(0, t.length - 3);
  }
  return t.trim();
}

List<AiPatch> _patchesOf(dynamic decoded) {
  if (decoded is! Map) return const [];
  final raw = decoded['patches'];
  if (raw is! List) return const [];

  final out = <AiPatch>[];
  for (final item in raw) {
    if (item is! Map) continue;
    final node = item['node'];
    final key = item['key'];
    final value = item['value'];
    if (node is! String || key is! String || value is! String) continue;
    if (node.trim().isEmpty || key.trim().isEmpty) continue;
    out.add(AiPatch(node: node.trim(), key: key.trim(), value: value));
  }
  return out;
}

String? _notesOf(dynamic decoded) {
  if (decoded is! Map) return null;
  final notes = decoded['notes'];
  if (notes is String && notes.trim().isNotEmpty) return notes.trim();
  return null;
}
