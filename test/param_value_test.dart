import 'package:flutter_test/flutter_test.dart';

import 'package:comfyui_mobilepocket/models/workflow_node.dart';
import 'package:comfyui_mobilepocket/services/object_info_service.dart';
import 'package:comfyui_mobilepocket/utils.dart';

WorkflowNode _node(
  String key,
  ParamType type,
  dynamic value, {
  String classType = 'CLIPLoader',
}) => WorkflowNode(
  id: '9',
  classType: classType,
  key: key,
  alias: key,
  exposed: true,
  title: '加载CLIP',
  paramType: type,
  options: const [],
  value: value,
);

void main() {
  group('提交取值：下拉选中的值不能丢', () {
    test('text 参数被渲染成下拉时，取下拉里的值而不是空文本', () {
      // type / device / weight_dtype 的 paramType 是 text，控件却是下拉，
      // 只看控制器文本的话改动会被静默丢掉。
      final v = resolveParamValue(
        node: _node('type', ParamType.text, 'lumina2'),
        control: ParamControl.select,
        text: '',
        widgetValue: 'qwen_image',
      );
      expect(v, 'qwen_image');
    });

    test('普通 text 参数没有下拉状态时用文本', () {
      final v = resolveParamValue(
        node: _node('filename_prefix', ParamType.text, 'ComfyUI'),
        control: ParamControl.text,
        text: 'my_prefix',
      );
      expect(v, 'my_prefix');
    });

    test('整数解析不出来时退回工作流原值', () {
      final v = resolveParamValue(
        node: _node('steps', ParamType.intType, 20),
        control: ParamControl.number,
        text: 'abc',
      );
      expect(v, 20);
    });

    test('小数与布尔照常', () {
      expect(
        resolveParamValue(
          node: _node('cfg', ParamType.float, 8.0),
          control: ParamControl.number,
          text: '1.5',
        ),
        1.5,
      );
      expect(
        resolveParamValue(
          node: _node('enabled', ParamType.boolType, false),
          control: ParamControl.toggle,
          text: '',
          widgetValue: true,
        ),
        true,
      );
    });
  });

  group('提交取值：形态按 control，不按 paramType', () {
    test('值是整数但控制成下拉时，选中值不会被 paramType 顶掉', () {
      // 这是一个真实的静默丢值路径：bit_depth 在工作流里是整数 8 →
      // paramType 判成 intType；说明书说它是 COMBO → control 是 select。
      // select 不建 TextEditingController，text 恒为空；
      // 若还按 intType 走 num.tryParse('') 就会退回 node.value（8），
      // 用户选的 10 被静默丢掉。
      final v = resolveParamValue(
        node: _node('bit_depth', ParamType.intType, 8),
        control: ParamControl.select,
        text: '',
        widgetValue: '10',
      );
      expect(v, '10'); // 没有说明书时至少要把选中的串提交上去
    });

    test('下拉提交选项原始类型：选 8 提交整数 8，不是 "8"', () {
      const spec = NodeInputSpec(
        isCombo: true,
        declaredType: 'COMBO',
        options: ['auto', '8', '10'],
        rawOptions: ['auto', 8, 10],
      );
      final v = resolveParamValue(
        node: _node('bit_depth', ParamType.intType, 8),
        control: ParamControl.select,
        text: '',
        widgetValue: '8',
        spec: spec,
      );
      expect(v, 8);
      expect(v, isA<int>());
    });

    test('原始值里找不到时原样返回显示值，不把值弄丢', () {
      const spec = NodeInputSpec(isCombo: true, options: ['a']);
      final v = resolveParamValue(
        node: _node('ckpt_name', ParamType.text, 'a'),
        control: ParamControl.select,
        text: '',
        widgetValue: 'moved.safetensors',
        spec: spec,
      );
      expect(v, 'moved.safetensors');
    });
  });
}
