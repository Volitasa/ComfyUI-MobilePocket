import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:comfyui_mobilepocket/l10n/app_localizations.dart';
import 'package:comfyui_mobilepocket/models/workflow_node.dart';
import 'package:comfyui_mobilepocket/services/workflow_node_parser.dart';
import 'package:comfyui_mobilepocket/utils.dart';

AppLocalizations _zh() => lookupAppLocalizations(const Locale('zh'));

List<String> _keys(List<WorkflowNode> nodes) =>
    nodes.map((n) => n.key).toList();

List<String> _exposed(List<WorkflowNode> nodes) =>
    nodes.where((n) => n.exposed).map((n) => n.key).toList();

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

void main() {
  final l = _zh();

  group('默认勾选：命中规则', () {
    test('规则指定了默认勾选时，只有指定的默认勾上', () {
      final nodes = WorkflowNodeParser.parse(
        _node('7', 'ReActorFaceSwap', {
          'enabled': true,
          'swap_model': 'inswapper_128.onnx',
          'facedetection': 'retinaface_resnet50',
          'codeformer_weight': 0.5,
        }),
        l: l,
      );
      expect(_exposed(nodes), ['enabled', 'swap_model']);
    });

    test('规则没指定默认勾选时全部默认勾上（能进规则表的都值得调）', () {
      final nodes = WorkflowNodeParser.parse(
        _node('3', 'KSampler', {
          'seed': 123,
          'steps': 20,
          'cfg': 7.0,
          'sampler_name': 'euler',
          'scheduler': 'normal',
          'denoise': 1,
        }),
        l: l,
      );
      expect(_exposed(nodes), _keys(nodes));
      expect(_exposed(nodes), contains('denoise'));
    });

    test('规则没写 keys 但写了默认勾选时沿用「全部默认勾」，与改前一致', () {
      // ControlNetApplyAdvanced 形态：keys 为 null、defaultExposedKeys 非 null。
      // 收紧兜底不能顺手改掉这类节点的既有行为
      final nodes = WorkflowNodeParser.parse(
        _node('5', 'ControlNetApplyAdvanced', {
          'strength': 1,
          'start_percent': 0.0,
          'end_percent': 1.0,
        }),
        l: l,
      );
      expect(_exposed(nodes), _keys(nodes));
    });
  });

  group('默认勾选：未命中规则', () {
    test('只默认勾高频参数，其余保持可见但不勾', () {
      final nodes = WorkflowNodeParser.parse(
        _node('9', 'SomeRandomCustomNode', {
          'text': 'hello', // 高频
          'seed': 7, // 高频
          'weird_param_a': 1, // 非高频
          'weird_param_b': 'x', // 非高频
        }),
        l: l,
      );
      expect(_exposed(nodes), ['text', 'seed']);
      // 关键：不能因为不默认勾就从列表里消失，否则用户想调也调不到
      expect(_keys(nodes), contains('weird_param_a'));
      expect(_keys(nodes), contains('weird_param_b'));
    });

    test('高频参数集合本身参与默认勾选', () {
      final nodes = WorkflowNodeParser.parse(
        _node('9', 'SomeRandomCustomNode', {'steps': 20, 'cfg': 7.0}),
        l: l,
      );
      expect(_exposed(nodes), ['steps', 'cfg']);
      for (final key in _exposed(nodes)) {
        expect(highFreqParams, contains(key));
      }
    });

    test('图片上传框不会因为收紧兜底而消失', () {
      final nodes = WorkflowNodeParser.parse(
        _node('2', 'LoadImage', {'image': 'a.png', 'upload': 'image'}),
        l: l,
      );
      final image = nodes.firstWhere((n) => n.key == 'image');
      expect(image.paramType, ParamType.image);
      expect(image.exposed, isTrue);
      // upload 是按钮而非可填参数，不应默认勾上
      expect(nodes.firstWhere((n) => n.key == 'upload').exposed, isFalse);
    });
  });

  group('基础行为（收紧兜底不应影响）', () {
    test('连线引用不出现在结果里', () {
      final nodes = WorkflowNodeParser.parse(
        _node('3', 'KSampler', {
          'seed': 1,
          'model': ['1', 0],
          'positive': ['1', 1],
        }),
        l: l,
      );
      expect(_keys(nodes), ['seed']);
    });

    test('强制类型优先于按值推断：denoise 的字面整数仍识别为小数', () {
      final nodes = WorkflowNodeParser.parse(
        _node('3', 'KSampler', {'denoise': 1}),
        l: l,
      );
      expect(nodes.single.paramType, ParamType.float);
    });

    test('自定义节点标题进入别名', () {
      final nodes = WorkflowNodeParser.parse(
        _node('4', 'CLIPTextEncode', {'text': 'a cat'}, title: '正面提示词'),
        l: l,
      );
      expect(nodes.single.alias, '正面提示词');
    });

    test('class_type 缺失的节点被跳过，不抛异常', () {
      final nodes = WorkflowNodeParser.parse({
        '1': {
          'inputs': {'text': 'x'},
        },
      }, l: l);
      expect(nodes, isEmpty);
    });
  });
}
