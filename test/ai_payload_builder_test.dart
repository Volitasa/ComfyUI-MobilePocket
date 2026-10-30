import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:comfyui_mobilepocket/models/ai_task.dart';
import 'package:comfyui_mobilepocket/services/ai/ai_payload_builder.dart';

AiContextInput textInput(String id, String text) => AiContextInput(
  nodeId: id,
  title: '节点$id',
  classType: 'Text Multiline',
  key: 'text',
  text: text,
);

AiContextInput imageInput(String id, String file) => AiContextInput(
  nodeId: id,
  title: '加载图像',
  classType: 'LoadImage',
  key: 'image',
  image: file,
);

const target = AiOutputTarget(
  nodeId: '5',
  key: 'prompt',
  title: '文本编码',
  current: 'keep <image1>',
);

Map<String, dynamic> decodeText(AiPayload p) =>
    jsonDecode(p.userParts.first['text'] as String) as Map<String, dynamic>;

void main() {
  test('只包含被引用节点，且带 image_order', () {
    final p = buildAiPayload(
      task: 'imageToPrompt',
      target: target,
      inputs: [
        textInput('10', '基础设定'),
        imageInput('15', 'a.png'),
        imageInput('16', 'b.png'),
      ],
      models: const [AiModelInfo(kind: 'unet', name: 'x.safetensors')],
      instruction: '写一段提示词',
    );
    final json = decodeText(p);

    expect(json['task'], 'imageToPrompt');
    expect((json['target'] as Map)['node'], '5');
    expect(json['inputs'], hasLength(3));
    expect(json['image_order'], hasLength(2));
    expect((json['image_order'] as List).first['node'], '15');
    expect(json['instruction'], '写一段提示词');
    expect(p.imageNodeIds, ['15', '16']);
  });

  test('系统提示包含只输出 JSON 与占位符约束', () {
    final p = buildAiPayload(
      task: 'rewrite',
      target: target,
      inputs: [textInput('10', 'x')],
      models: const [],
      instruction: 'y',
    );
    expect(p.systemPrompt, contains('只输出 JSON'));
    expect(p.systemPrompt, contains('占位符'));
  });

  test('超长时先砍模型信息', () {
    final models = [
      for (var i = 0; i < 20; i++)
        AiModelInfo(kind: 'lora', name: 'very_long_model_name_$i.safetensors'),
    ];
    final p = buildAiPayload(
      task: 'rewrite',
      target: target,
      inputs: [textInput('10', 'x')],
      models: models,
      instruction: 'y',
      maxChars: 600,
    );
    final json = decodeText(p);
    final keptModels = (json['models'] as List?) ?? const [];
    expect(keptModels.length, lessThan(models.length));
    expect((json['inputs'] as List), isNotEmpty);
  });

  test('图片块按顺序追加在文本之后', () {
    final p = buildAiPayload(
      task: 'imageToPrompt',
      target: target,
      inputs: [imageInput('15', 'a.png')],
      models: const [],
      instruction: 'y',
    );
    appendImagePart(p, 'data:image/png;base64,AAA');
    expect(p.userParts.first['type'], 'text');
    expect(p.userParts.last['type'], 'image_url');
    expect(
      ((p.userParts.last['image_url'] as Map)['url'] as String),
      startsWith('data:image/png;base64,'),
    );
  });
}
