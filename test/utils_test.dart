import 'package:flutter_test/flutter_test.dart';
import 'package:comfyui_mobilepocket/utils.dart';

void main() {
  group('workflowDisplayName', () {
    test('本地工作流显示为“本地导入”', () {
      expect(workflowDisplayName('local_abc123'), '本地导入');
    });

    test('线上工作流去掉 _api.json 后缀', () {
      expect(workflowDisplayName('txt2img_api.json'), 'txt2img');
    });

    test('无后缀名原样返回', () {
      expect(workflowDisplayName('foo'), 'foo');
    });
  });

  group('stableHash', () {
    test('相同输入产生相同哈希', () {
      expect(stableHash('hello'), stableHash('hello'));
    });

    test('不同输入产生不同哈希（大概率）', () {
      expect(stableHash('hello'), isNot(stableHash('world')));
    });

    test('哈希非负且在 30 位范围内（Web 平台安全）', () {
      final h = stableHash('some json content');
      expect(h, greaterThanOrEqualTo(0));
      expect(h, lessThan(1 << 30));
    });
  });

  group('normalizeWorkflowJson', () {
    test('prompt 包装格式被解包为扁平节点 Map', () {
      final wrapped = {
        'prompt': {
          '3': {'class_type': 'KSampler', 'inputs': {'seed': 1}},
        },
        'extra_data': {'foo': 'bar'},
      };
      final result = normalizeWorkflowJson(wrapped);
      expect(result.containsKey('3'), isTrue);
      expect(result.containsKey('prompt'), isFalse);
    });

    test('顶层即为节点结构时原样返回', () {
      final flat = {
        '3': {'class_type': 'KSampler', 'inputs': {'seed': 1}},
      };
      expect(normalizeWorkflowJson(flat), flat);
    });

    test('空 Map 原样返回', () {
      expect(normalizeWorkflowJson({}), isEmpty);
    });
  });
}
