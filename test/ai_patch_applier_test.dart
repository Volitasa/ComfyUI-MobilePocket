import 'package:flutter_test/flutter_test.dart';

import 'package:comfyui_mobilepocket/models/ai_task.dart';
import 'package:comfyui_mobilepocket/models/workflow_node.dart';
import 'package:comfyui_mobilepocket/services/ai/ai_patch_applier.dart';

WorkflowNode node({
  String id = '5',
  String key = 'prompt',
  ParamType type = ParamType.text,
  ParamControl? control,
}) => WorkflowNode(
  id: id,
  classType: 'TextEncodeQwen',
  key: key,
  alias: key,
  paramType: type,
  control: control,
);

void main() {
  test('正常写入通过', () {
    final check = validateAiPatch(
      patch: const AiPatch(node: '5', key: 'prompt', value: 'hi'),
      nodes: [node()],
      allowedParamKeys: {'5:prompt'},
    );
    expect(check.ok, isTrue);
  });

  test('节点不存在时拒绝', () {
    final check = validateAiPatch(
      patch: const AiPatch(node: '9', key: 'prompt', value: 'hi'),
      nodes: [node()],
      allowedParamKeys: {'9:prompt'},
    );
    expect(check.error, AiApplyError.nodeMissing);
  });

  test('非文本参数拒绝（数值）', () {
    final check = validateAiPatch(
      patch: const AiPatch(node: '6', key: 'steps', value: '20'),
      nodes: [node(id: '6', key: 'steps', type: ParamType.intType)],
      allowedParamKeys: {'6:steps'},
    );
    expect(check.error, AiApplyError.notTextParam);
  });

  test('控件不是文本框也拒绝', () {
    final check = validateAiPatch(
      patch: const AiPatch(node: '6', key: 'image', value: 'x'),
      nodes: [
        node(
          id: '6',
          key: 'image',
          type: ParamType.image,
          control: ParamControl.upload,
        ),
      ],
      allowedParamKeys: {'6:image'},
    );
    expect(check.error, AiApplyError.notTextParam);
  });

  test('不在本次输出列表里拒绝（防越权改别的节点）', () {
    final check = validateAiPatch(
      patch: const AiPatch(node: '5', key: 'negative_prompt', value: 'bad'),
      nodes: [node(), node(key: 'negative_prompt')],
      allowedParamKeys: {'5:prompt'},
    );
    expect(check.error, AiApplyError.notAllowed);
  });

  test('超长拒绝', () {
    final check = validateAiPatch(
      patch: AiPatch(node: '5', key: 'prompt', value: 'x' * (kAiMaxPatchLength + 1)),
      nodes: [node()],
      allowedParamKeys: {'5:prompt'},
    );
    expect(check.error, AiApplyError.tooLong);
  });
}
