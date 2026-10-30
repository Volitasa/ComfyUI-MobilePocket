import 'package:flutter_test/flutter_test.dart';

import 'package:comfyui_mobilepocket/services/ai/ai_response_parser.dart';

void main() {
  test('纯 JSON 正常解析', () {
    final r = parseAiResult(
      '{"patches":[{"node":"5","key":"prompt","value":"a cat"}],"notes":"ok"}',
    );
    expect(r.structured, isTrue);
    expect(r.patches, hasLength(1));
    expect(r.patches.first.node, '5');
    expect(r.patches.first.value, 'a cat');
    expect(r.notes, 'ok');
  });

  test('带 ```json 围栏也能解析', () {
    final r = parseAiResult('```json\n{"patches":[{"node":"1","key":"text","value":"x"}]}\n```');
    expect(r.structured, isTrue);
    expect(r.patches.single.value, 'x');
  });

  test('前后有废话时取第一个 { 到最后一个 }', () {
    final r = parseAiResult(
      '好的，结果如下：\n{"patches":[{"node":"1","key":"text","value":"y"}]}\n希望有帮助',
    );
    expect(r.structured, isTrue);
    expect(r.patches.single.value, 'y');
  });

  test('多条 patch 全部保留', () {
    final r = parseAiResult(
      '{"patches":[{"node":"1","key":"a","value":"1"},{"node":"2","key":"b","value":"2"}]}',
    );
    expect(r.patches, hasLength(2));
  });

  test('缺字段的项被跳过', () {
    final r = parseAiResult(
      '{"patches":[{"node":"1","key":"a"},{"node":"2","key":"b","value":"2"}]}',
    );
    expect(r.patches, hasLength(1));
    expect(r.patches.single.node, '2');
  });

  test('非法 JSON 退回纯文本', () {
    const raw = '这不是 JSON，只是一段提示词';
    final r = parseAiResult(raw);
    expect(r.structured, isFalse);
    expect(r.patches, isEmpty);
    expect(r.rawText, raw);
  });

  test('空 patches 视为未结构化', () {
    final r = parseAiResult('{"patches":[]}');
    expect(r.structured, isFalse);
    expect(r.rawText, contains('patches'));
  });

  test('空字符串返回 empty', () {
    final r = parseAiResult('   ');
    expect(r.rawText, isEmpty);
    expect(r.patches, isEmpty);
  });
}
