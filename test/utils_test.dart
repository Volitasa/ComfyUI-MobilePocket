import 'package:flutter_test/flutter_test.dart';
import 'package:comfyui_mobilepocket/l10n/app_localizations_en.dart';
import 'package:comfyui_mobilepocket/l10n/app_localizations_zh.dart';
import 'package:comfyui_mobilepocket/utils.dart';
import 'package:comfyui_mobilepocket/models/local_workflow.dart';
import 'package:comfyui_mobilepocket/models/workflow_node.dart';

void main() {
  group('workflowDisplayName', () {
    // 本地标签由调用方按当前语言传入，函数本身不产出任何文案
    test('本地工作流显示为传入的本地标签', () {
      expect(workflowDisplayName('local_abc123', localLabel: '本地导入'), '本地导入');
      expect(
        workflowDisplayName('local_abc123', localLabel: 'Local import'),
        'Local import',
      );
    });

    test('线上工作流去掉 _api.json 后缀', () {
      expect(
        workflowDisplayName('txt2img_api.json', localLabel: '本地导入'),
        'txt2img',
      );
    });

    test('无后缀名原样返回', () {
      expect(workflowDisplayName('foo', localLabel: '本地导入'), 'foo');
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
          '3': {
            'class_type': 'KSampler',
            'inputs': {'seed': 1},
          },
        },
        'extra_data': {'foo': 'bar'},
      };
      final result = normalizeWorkflowJson(wrapped);
      expect(result.containsKey('3'), isTrue);
      expect(result.containsKey('prompt'), isFalse);
    });

    test('顶层即为节点结构时原样返回', () {
      final flat = {
        '3': {
          'class_type': 'KSampler',
          'inputs': {'seed': 1},
        },
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
      expect(
        inferParamType('x', [
          [1, 2],
        ]),
        isNull,
      );
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
      expect(isDefaultExposed('start_at_step', 'KSamplerAdvanced'), isFalse);
    });
    // 当前设计：尺寸、生成数量与模型加载参数默认暴露（便于在运行页直接换模型/尺寸）
    test('尺寸与模型加载参数默认暴露', () {
      expect(isDefaultExposed('width', 'EmptyLatentImage'), isTrue);
      expect(isDefaultExposed('height', 'EmptyLatentImage'), isTrue);
      expect(isDefaultExposed('unet_name', 'UNETLoader'), isTrue);
    });
  });

  group('WorkflowNode 序列化兼容', () {
    test('旧配置无 paramType 时按 key 推断（seed → seed）', () {
      final node = WorkflowNode.fromJson({
        'id': '1',
        'classType': 'KSampler',
        'key': 'seed',
        'alias': '种子',
        'exposed': true,
      });
      expect(node.paramType, ParamType.seed);
      expect(node.options, isEmpty);
      expect(node.value, isNull);
    });

    test('旧配置无 paramType 且无法推断时兜底为 text', () {
      final node = WorkflowNode.fromJson({
        'id': '2',
        'classType': 'SomeNode',
        'key': 'some_unknown_param',
        'alias': '未知参数',
        'exposed': true,
      });
      expect(node.paramType, ParamType.text);
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

  group('workflowNameForStorage（落盘名，绝不产出翻译文案）', () {
    test('本地工作流命中库里的名字时返回真名', () {
      final known = <LocalWorkflow>[
        LocalWorkflow(
          id: 'local_x1',
          name: '我的工作流',
          createdAt: 0,
          sourceKind: LocalWorkflowSource.importFile,
          workflowJson: const {},
        ),
      ];
      expect(workflowNameForStorage(known, 'local_x1'), '我的工作流');
    });

    test('本地工作流已删除时不猜名字，返回 null', () {
      expect(workflowNameForStorage(<LocalWorkflow>[], 'local_x1'), isNull);
    });

    test('线上工作流沿用文件名规则', () {
      expect(
        workflowNameForStorage(<LocalWorkflow>[], 'txt2img_api.json'),
        'txt2img',
      );
    });
  });

  group('workflowDisplayNameOr（展示名按当前语言补默认名）', () {
    test('磁盘里为空时按语言补', () {
      expect(workflowDisplayNameOr(AppLocalizationsZh(), ''), '本地导入');
      expect(workflowDisplayNameOr(AppLocalizationsEn(), ''), 'Local import');
    });

    test('有真名时原样返回', () {
      expect(workflowDisplayNameOr(AppLocalizationsEn(), '我的工作流'), '我的工作流');
    });
  });

  group('旧数据清洗', () {
    test('旧版本写死的「本地导入」识别为空', () {
      expect(cleanStoredWorkflowName('本地导入'), isNull);
      expect(cleanStoredWorkflowName('Local import'), isNull);
      expect(cleanStoredWorkflowName('我的工作流'), '我的工作流');
    });

    test('旧版本写死的服务器默认名识别为空', () {
      expect(cleanStoredServerName('服务器'), '');
      expect(cleanStoredServerName('Server'), '');
      expect(cleanStoredServerName('服务器 2'), '');
      expect(cleanStoredServerName('Server 3'), '');
      expect(cleanStoredServerName('我的服务器'), '我的服务器');
    });
  });

  group('图片参数的下发来源', () {
    test('本地新选的图优先走上传', () {
      expect(
        imageValueSource(
          hasLocalPick: true,
          serverValue: 'old.png [input]',
        ),
        ImageValueSource.local,
      );
    });

    test('从服务器目录选的图要原样下发', () {
      // 这是修掉的 bug：选完服务器图后本地那份被清掉，
      // 以前走到这里会被当成"没改过"直接跳过，服务器仍在用旧图。
      expect(
        imageValueSource(
          hasLocalPick: false,
          serverValue: 'ComfyUI_00001_.png [output]',
        ),
        ImageValueSource.server,
      );
    });

    test('没改过时沿用工作流原值', () {
      expect(
        imageValueSource(hasLocalPick: false, serverValue: null),
        ImageValueSource.unchanged,
      );
      expect(
        imageValueSource(hasLocalPick: false, serverValue: ''),
        ImageValueSource.unchanged,
      );
    });

    test('上传成功后写入的名字，下次就是 server 来源', () {
      // `_handleExecute` 上传完会把名字写回 `_widgetValues`
      expect(
        imageValueSource(hasLocalPick: false, serverValue: 'new_00001_.png'),
        ImageValueSource.server,
      );
    });
  });
}
