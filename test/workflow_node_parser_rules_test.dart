import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';

import 'package:comfyui_mobilepocket/l10n/app_localizations.dart';
import 'package:comfyui_mobilepocket/models/workflow_node.dart';
import 'package:comfyui_mobilepocket/services/object_info_service.dart';
import 'package:comfyui_mobilepocket/services/workflow_node_parser.dart';

AppLocalizations _zh() => lookupAppLocalizations(const Locale('zh'));

Map<String, dynamic> _node(
  String id,
  String classType,
  Map<String, dynamic> inputs, {
  String? title,
}) => {
  id: {
    'inputs': inputs,
    'class_type': classType,
    if (title != null) '_meta': {'title': title},
  },
};

List<String> _keys(List<WorkflowNode> nodes) => nodes.map((n) => n.key).toList();

List<String> _exposed(List<WorkflowNode> nodes) =>
    nodes.where((n) => n.exposed).map((n) => n.key).toList();

void main() {
  final l = _zh();

  group('暴露规则表：节点规则优先于参数规则', () {
    test('规则给了 keys 但没给 defaultExposedKeys → 按 keys 勾', () {
      // RMBG 形态：keys = {model, sensitivity, process_res}，无 defaultExposedKeys
      final nodes = WorkflowNodeParser.parse(
        _node('21', 'RMBG', {
          'model': 'RMBG-2.0',
          'sensitivity': 1.0,
          'process_res': 512,
          'background_color': 0,
        }),
        l: l,
      );
      expect(_exposed(nodes), ['model', 'sensitivity', 'process_res']);
      // 不在 keys 里的参数照样可见，只是不默认勾
      expect(_keys(nodes), contains('background_color'));
    });

    test('只给了 defaultExposedKeys 没给 keys → 只勾这些（修掉的短路缺陷）', () {
      // ControlNetApplyAdvanced 形态。
      // ⚠️ 原写法 `if (rule.keys == null || ...) return true` 会短路成「全勾」，
      //    与规则字面意思相反。同中招的还有 IPAdapter / IPAdapterFaceID / IPAdapterNoise。
      final nodes = WorkflowNodeParser.parse(
        _node('5', 'ControlNetApplyAdvanced', {
          'strength': 1,
          'start_percent': 0.0,
          'end_percent': 1.0,
        }),
        l: l,
      );
      expect(_exposed(nodes), ['strength']);
    });

    test('⚠️ 回归：IPAdapter 不再全勾（原本 ~20 个参数全勾）', () {
      final nodes = WorkflowNodeParser.parse(
        _node('22', 'IPAdapter', {
          'weight': 1.0,
          'start_at': 0.0,
          'end_at': 1.0,
          'noise': 0.0,
          'weight_type': 'standard',
          'combine_embeds': 'concat',
          'embeds_scaling': 'V only',
        }),
        l: l,
      );
      expect(_exposed(nodes), ['weight']);
      // 其余参数没勾，但依然可见
      expect(_keys(nodes), contains('weight_type'));
      expect(_exposed(nodes).length, lessThan(_keys(nodes).length));
    });

    test('两个集合都没指定 → 该节点全部默认勾', () {
      final nodes = WorkflowNodeParser.parse(
        _node('3', 'KSampler', {'seed': 1, 'steps': 20, 'cfg': 7.0}),
        l: l,
      );
      expect(_exposed(nodes), _keys(nodes));
    });

    test('未命中规则的节点 → 只勾高频参数，其余可见不勾', () {
      final nodes = WorkflowNodeParser.parse(
        _node('9', 'SomeRandomCustomNode', {
          'text': 'hello', // 高频
          'seed': 7, // 高频
          'weird_param_a': 1, // 非高频
        }),
        l: l,
      );
      expect(_exposed(nodes), ['text', 'seed']);
      expect(_keys(nodes), contains('weird_param_a'));
    });
  });

  group('控件判定（方案 §3.4）', () {
    test('1 图片参数 → upload，优先于说明书结论', () {
      // 服务器把 LoadImage.image 声明成 COMBO（139 项文件名），
      // 若被当成普通下拉，用户就再也传不了新图了。
      const spec = NodeInputSpec(
        isCombo: true,
        declaredType: 'COMBO',
        options: ['a.png'],
      );
      expect(
        WorkflowNodeParser.resolveControl(
          key: 'image',
          rawValue: 'a.png',
          paramType: ParamType.image,
          spec: spec,
        ),
        ParamControl.upload,
      );
      // 即使 paramType 推断不出来（退化成 text），也必须是上传框
      expect(
        WorkflowNodeParser.resolveControl(
          key: 'image',
          rawValue: 'a.png',
          paramType: ParamType.text,
          spec: spec,
        ),
        ParamControl.upload,
      );
    });

    test('1b 种子 → seed，优先于说明书结论', () {
      // 回归：ComfyUI 的说明书把 `seed` 声明成 INT，C2「按说明书定型」之后
      // 一进 INT 分支就返回 number / slider，「换一个随机值」的骰子就没了。
      // 断网拿不到说明书时反而正常（走 `_controlFromParamType` 认出 seed），
      // 所以这个回归平时极难发现 —— 只有真机上对着 KSampler 才看得见。
      expect(
        WorkflowNodeParser.resolveControl(
          key: 'seed',
          rawValue: 123,
          paramType: ParamType.seed,
          spec: const NodeInputSpec(isCombo: false, declaredType: 'INT'),
        ),
        ParamControl.seed,
      );
      // 档位再少也不能退化成滑块：种子要的是骰子，不是拖动条
      expect(
        WorkflowNodeParser.resolveControl(
          key: 'noise_seed',
          rawValue: 1,
          paramType: ParamType.seed,
          spec: const NodeInputSpec(
            isCombo: false,
            declaredType: 'INT',
            min: 0,
            max: 100,
            step: 1,
          ),
        ),
        ParamControl.seed,
      );
    });

    test('1c 非种子的数值参数不受影响', () {
      // steps 0–100 共 99 档 ≤ kSliderMaxDivisions → 仍然是滑块
      expect(
        WorkflowNodeParser.resolveControl(
          key: 'steps',
          rawValue: 20,
          paramType: ParamType.intType,
          spec: const NodeInputSpec(
            isCombo: false,
            declaredType: 'INT',
            min: 1,
            max: 100,
            step: 1,
          ),
        ),
        ParamControl.slider,
      );
    });

    test('2 COMBO → select', () {
      expect(
        WorkflowNodeParser.resolveControl(
          key: 'aspect_ratio',
          rawValue: '1:1',
          paramType: ParamType.text,
          spec: const NodeInputSpec(
            isCombo: true,
            declaredType: 'COMBO',
            options: ['1:1', '16:9'],
          ),
        ),
        ParamControl.select,
      );
    });

    test('2b 声明了 COMBO 却没给 options → 不当下拉', () {
      expect(
        WorkflowNodeParser.resolveControl(
          key: 'x',
          rawValue: 'v',
          paramType: ParamType.text,
          spec: const NodeInputSpec(isCombo: false, declaredType: 'COMBO'),
        ),
        ParamControl.text,
      );
    });

    test('3 BOOLEAN → toggle', () {
      expect(
        WorkflowNodeParser.resolveControl(
          key: 'enabled',
          rawValue: true,
          paramType: ParamType.boolType,
          spec: const NodeInputSpec(isCombo: false, declaredType: 'BOOLEAN'),
        ),
        ParamControl.toggle,
      );
    });

    test('4 数值且档位 ≤100 → slider', () {
      // denoise 0–1，step 0.01 → 100 档
      expect(
        WorkflowNodeParser.resolveControl(
          key: 'denoise',
          rawValue: 1,
          paramType: ParamType.float,
          spec: const NodeInputSpec(
            isCombo: false,
            declaredType: 'FLOAT',
            min: 0,
            max: 1,
            step: 0.01,
          ),
        ),
        ParamControl.slider,
      );
    });

    test('5 数值档位过多 → number（steps 1–10000 有 9999 档）', () {
      expect(
        WorkflowNodeParser.resolveControl(
          key: 'steps',
          rawValue: 20,
          paramType: ParamType.intType,
          spec: const NodeInputSpec(
            isCombo: false,
            declaredType: 'INT',
            min: 1,
            max: 10000,
            step: 1,
          ),
        ),
        ParamControl.number,
      );
    });

    test('6 STRING → text', () {
      expect(
        WorkflowNodeParser.resolveControl(
          key: 'filename_prefix',
          rawValue: 'ComfyUI',
          paramType: ParamType.text,
          spec: const NodeInputSpec(isCombo: false, declaredType: 'STRING'),
        ),
        ParamControl.text,
      );
    });

    test('7 没有说明书 → 按 paramType 推断', () {
      expect(
        WorkflowNodeParser.resolveControl(
          key: 'seed',
          rawValue: 1,
          paramType: ParamType.seed,
        ),
        ParamControl.seed,
      );
      expect(
        WorkflowNodeParser.resolveControl(
          key: 'enabled',
          rawValue: true,
          paramType: ParamType.boolType,
        ),
        ParamControl.toggle,
      );
    });

    test('⚠️ 参数类型无法归类 → null（该参数不会进表单）', () {
      expect(
        WorkflowNodeParser.resolveControl(
          key: 'x',
          rawValue: <Object>{}, // 既不是值也不是连线引用
          paramType: null,
        ),
        isNull,
      );
    });
  });

  group('collectClassTypes', () {
    test('去重且保持出现顺序', () {
      final types = WorkflowNodeParser.collectClassTypes({
        ..._node('1', 'KSampler', {'seed': 1}),
        ..._node('2', 'CLIPTextEncode', {'text': 'a'}),
        ..._node('3', 'KSampler', {'steps': 20}),
      });
      expect(types, ['KSampler', 'CLIPTextEncode']);
    });

    test('跳过没有 inputs 的条目', () {
      final types = WorkflowNodeParser.collectClassTypes({
        '1': {'class_type': 'Note'},
        ..._node('2', 'KSampler', {'seed': 1}),
      });
      expect(types, ['KSampler']);
    });

    test('空工作流 → 空列表（不发起任何请求）', () {
      expect(WorkflowNodeParser.collectClassTypes(const {}), isEmpty);
    });
  });

  group('computeIssues（方案 §3.7）', () {
    final nodes = [
      WorkflowNode(id: '1', classType: 'A', key: 'x', alias: 'x'),
      WorkflowNode(id: '2', classType: 'B', key: 'y', alias: 'y'),
      WorkflowNode(id: '3', classType: 'C', key: 'z', alias: 'z'),
    ];

    test('⚠️ 取数失败（整个 classType 没问到）不算缺失', () {
      // 这正是「failure 与 empty 必须分开」的落点：
      // 不知道 ≠ 服务器上没有，此时不标黄、不拦。
      final issues = WorkflowNodeParser.computeIssues(nodes, {
        'A': {'x': const NodeInputSpec(isCombo: false)},
      });
      expect(issues.isNodeMissing('B'), isFalse);
      expect(issues.isParamMissing('2', 'y'), isFalse);
      expect(issues.isParamMissing('3', 'z'), isFalse);
    });

    test('服务器 200 回 {} → 该节点整个缺失', () {
      final issues = WorkflowNodeParser.computeIssues(nodes, {
        'A': const {},
        'B': const {},
        'C': {'z': const NodeInputSpec(isCombo: false)},
      });
      expect(issues.isNodeMissing('A'), isTrue);
      expect(issues.isNodeMissing('B'), isTrue);
      expect(issues.isNodeMissing('C'), isFalse);
    });

    test('有 spec 但缺这个 key → 该参数缺失', () {
      final issues = WorkflowNodeParser.computeIssues(nodes, {
        'A': {'other': const NodeInputSpec(isCombo: false)},
        'B': {'y': const NodeInputSpec(isCombo: false)},
        'C': {'z': const NodeInputSpec(isCombo: false)},
      });
      expect(issues.isParamMissing('1', 'x'), isTrue);
      expect(issues.isParamMissing('2', 'y'), isFalse);
      expect(issues.isParamMissing('3', 'z'), isFalse);
    });

    test('全对得上 → 没有 issue', () {
      final issues = WorkflowNodeParser.computeIssues(nodes, {
        for (final n in nodes)
          n.classType: {n.key: const NodeInputSpec(isCombo: false)},
      });
      expect(issues.isEmpty, isTrue);
    });
  });
}
