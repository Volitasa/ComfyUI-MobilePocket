import 'package:flutter_test/flutter_test.dart';
import 'package:comfyui_mobilepocket/utils.dart';
import 'package:comfyui_mobilepocket/models/workflow_node.dart';

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

  group('isLinkReference', () {
    test('连线引用 ["节点id", 索引] 识别为 true', () {
      expect(isLinkReference(['4', 0]), isTrue);
    });

    test('普通列表不是连线引用', () {
      expect(isLinkReference(['euler', 'ddim']), isFalse);
      expect(isLinkReference([1, 2, 3]), isFalse);
      expect(isLinkReference('abc'), isFalse);
    });
  });

  group('inferParamType', () {
    test('bool → boolType', () {
      expect(inferParamType('x', true), ParamType.boolType);
    });
    test('int → intType', () {
      expect(inferParamType('steps', 20), ParamType.intType);
    });
    test('double → float', () {
      expect(inferParamType('cfg', 7.5), ParamType.float);
    });
    test('字符串列表 → enumType', () {
      expect(inferParamType('sampler', ['euler', 'ddim']), ParamType.enumType);
    });
    test('字符串 → text', () {
      expect(inferParamType('text', 'a cat'), ParamType.text);
    });
    test('连线引用 → null（不暴露）', () {
      expect(inferParamType('model', ['4', 0]), isNull);
    });
    test('嵌套列表 → null', () {
      expect(inferParamType('x', [
        [1, 2]
      ]), isNull);
    });
  });

  group('isDefaultExposed', () {
    test('高频参数默认暴露', () {
      expect(isDefaultExposed('seed', 'KSampler'), isTrue);
      expect(isDefaultExposed('cfg', 'KSampler'), isTrue);
      expect(isDefaultExposed('text', 'CLIPTextEncode'), isTrue);
    });
    test('低频参数默认不暴露', () {
      expect(isDefaultExposed('denoise', 'KSampler'), isFalse);
      expect(isDefaultExposed('width', 'EmptyLatentImage'), isFalse);
    });
  });

  group('WorkflowNode 序列化兼容', () {
    test('旧配置无 paramType 时兜底为 text', () {
      final node = WorkflowNode.fromJson({
        'id': '1',
        'classType': 'KSampler',
        'key': 'seed',
        'alias': '种子',
        'exposed': true,
      });
      expect(node.paramType, ParamType.text);
      expect(node.options, isEmpty);
      expect(node.value, isNull);
    });

    test('完整序列化往返', () {
      final node = WorkflowNode(
        id: '1',
        classType: 'KSampler',
        key: 'sampler_name',
        alias: '采样器',
        exposed: true,
        paramType: ParamType.enumType,
        options: ['euler'],
        value: 'euler',
      );
      final restored = WorkflowNode.fromJson(node.toJson());
      expect(restored.paramType, ParamType.enumType);
      expect(restored.options, ['euler']);
      expect(restored.value, 'euler');
    });
  });
}
