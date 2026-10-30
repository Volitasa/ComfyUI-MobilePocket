import 'dart:convert';

import '../../models/ai_task.dart';

/// 组装好的请求内容：system 文本 + user 的 content 数组。
///
/// 图片块由调用方追加（它才拿得到字节），顺序必须与这里的 `image_order` 一致。
class AiPayload {
  const AiPayload({
    required this.systemPrompt,
    required this.userParts,
    required this.imageNodeIds,
  });

  final String systemPrompt;
  final List<Map<String, dynamic>> userParts;

  /// 与图片块一一对应的节点 id 列表（按追加顺序）。
  final List<String> imageNodeIds;
}

/// 固定系统提示。改这里必须同步改 `ai_payload_builder_test`。
///
/// 三条约束缺一不可：只输出 JSON、只改 target、保留占位符。
const String kAiSystemPrompt =
    '你是 ComfyUI 工作流的提示词编辑器。用户会给你若干被引用的节点数据、一个目标参数、以及一句要求。\n'
    '\n'
    '只输出 JSON，不要解释、不要 Markdown 代码块：\n'
    '{"patches":[{"node":"<节点id>","key":"<参数名>","value":"<新文本>"}],"notes":"<可选，不超过 30 字>"}\n'
    '\n'
    '规则：\n'
    '1. 只改写 target 指出的那一个参数，不要动其它节点，不要编造其它字段；\n'
    '2. 保留原文中的占位符（如 <image1>、<Picture 1>）与其原有语言；\n'
    '3. 不要编造模型名、LoRA 名、采样参数；\n'
    '4. 改写类任务尽量保留原有 tag 的语义与先后顺序。';

/// 文本上限：超出先砍模型信息，再砍最旧的文本输入。
const int kAiMaxChars = 6000;

/// 单次最多几张图。UI 也要按这个数限制选择。
const int kAiMaxImages = 4;

AiPayload buildAiPayload({
  required String task,
  required AiOutputTarget target,
  required List<AiContextInput> inputs,
  required List<AiModelInfo> models,
  required String instruction,
  int maxChars = kAiMaxChars,
}) {
  final imageInputs = inputs.where((i) => i.isImage).toList();
  final textInputs = inputs.where((i) => !i.isImage).toList();

  var workingModels = [...models];
  var workingText = [...textInputs];

  Map<String, dynamic> compose() => {
    'task': task,
    'target': target.toJson(),
    'inputs': [
      ...workingText.map((i) => i.toJson()),
      ...imageInputs.map((i) => i.toJson()),
    ],
    if (workingModels.isNotEmpty)
      'models': workingModels.map((m) => m.toJson()).toList(),
    if (imageInputs.isNotEmpty)
      'image_order': [
        for (var i = 0; i < imageInputs.length; i++)
          {'index': i + 1, 'node': imageInputs[i].nodeId, 'key': imageInputs[i].key},
      ],
    'instruction': instruction,
  };

  // 先砍模型，再砍最旧的文本输入（列表尾部视为较早选择）。
  while (jsonEncode(compose()).length > maxChars) {
    if (workingModels.isNotEmpty) {
      workingModels = workingModels.sublist(0, workingModels.length - 1);
      continue;
    }
    if (workingText.length > 1) {
      workingText = workingText.sublist(0, workingText.length - 1);
      continue;
    }
    break;
  }

  final payload = compose();
  return AiPayload(
    systemPrompt: kAiSystemPrompt,
    userParts: [
      {'type': 'text', 'text': jsonEncode(payload)},
    ],
    imageNodeIds: imageInputs.map((i) => i.nodeId).toList(),
  );
}

/// 把一张图追加进 user content。调用方负责顺序与体积。
void appendImagePart(
  AiPayload payload,
  String dataUrl,
) {
  payload.userParts.add({
    'type': 'image_url',
    'image_url': {'url': dataUrl},
  });
}
