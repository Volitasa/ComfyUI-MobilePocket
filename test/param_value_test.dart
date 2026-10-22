import 'package:flutter_test/flutter_test.dart';

import 'package:comfyui_mobilepocket/models/workflow_node.dart';
import 'package:comfyui_mobilepocket/utils.dart';

WorkflowNode _node(String key, ParamType type, dynamic value) => WorkflowNode(
  id: '9',
  classType: 'CLIPLoader',
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
        text: '',
        widgetValue: 'qwen_image',
      );
      expect(v, 'qwen_image');
    });

    test('普通 text 参数没有下拉状态时用文本', () {
      final v = resolveParamValue(
        node: _node('filename_prefix', ParamType.text, 'ComfyUI'),
        text: 'my_prefix',
      );
      expect(v, 'my_prefix');
    });

    test('整数解析不出来时退回工作流原值', () {
      final v = resolveParamValue(
        node: _node('steps', ParamType.intType, 20),
        text: 'abc',
      );
      expect(v, 20);
    });

    test('小数与布尔照常', () {
      expect(
        resolveParamValue(
          node: _node('cfg', ParamType.float, 8.0),
          text: '1.5',
        ),
        1.5,
      );
      expect(
        resolveParamValue(
          node: _node('enabled', ParamType.boolType, false),
          text: '',
          widgetValue: true,
        ),
        true,
      );
    });
  });
}
