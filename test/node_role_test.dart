import 'package:flutter_test/flutter_test.dart';

import 'package:comfyui_mobilepocket/services/node_role.dart';
import 'package:comfyui_mobilepocket/services/workflow_node_parser.dart';

/// 一条常见的 文生图链路：加载器 → 两个文本编码 → 空画布 → 两段采样，外加一个 LoRA。
const Map<String, dynamic> _workflow = {
  '1': {
    'class_type': 'CheckpointLoaderSimple',
    'inputs': {'ckpt_name': 'checkpoints/v1-5.safetensors'},
  },
  '2': {
    'class_type': 'CLIPTextEncode',
    'inputs': {
      'text': 'a cat',
      'clip': ['1', 1],
    },
  },
  '3': {
    'class_type': 'CLIPTextEncode',
    'inputs': {
      'text': 'blurry',
      'clip': ['1', 1],
    },
  },
  '4': {
    'class_type': 'EmptyLatentImage',
    'inputs': {'width': 512, 'height': 512, 'batch_size': 1},
  },
  '5': {
    'class_type': 'KSampler',
    'inputs': {
      'seed': 1,
      'steps': 20,
      'cfg': 8,
      'model': ['1', 0],
      'positive': ['2', 0],
      'negative': ['3', 0],
      'latent_image': ['4', 0],
    },
  },
  '6': {
    'class_type': 'KSampler',
    'inputs': {
      'seed': 2,
      'steps': 10,
      'cfg': 8,
      'model': ['1', 0],
      'positive': ['2', 0],
      'negative': ['3', 0],
      'latent_image': ['5', 0],
    },
  },
  '7': {
    'class_type': 'LoraLoader',
    'inputs': {
      'lora_name': 'styles/film_grain.safetensors',
      'strength_model': 1.0,
      'model': ['1', 0],
      'clip': ['1', 1],
    },
  },
};

void main() {
  group('节点位置', () {
    test('同名文本编码靠它接到的官方槽位说清去哪', () {
      final roles = inferNodeRoles(_workflow);

      // 光看类名这两个节点一模一样，区别只在它接到了采样器的哪个口
      expect(roles['2']?.links.first, (label: 'KSampler', slot: 'positive'));
      expect(roles['3']?.links.first, (label: 'KSampler', slot: 'negative'));
    });

    test('下游节点名用工作流自带的标题，我们自己不另起名字', () {
      final roles = inferNodeRoles({
        '2': {
          'class_type': 'CLIPTextEncode',
          'inputs': {
            'text': 'a cat',
            'clip': ['1', 1],
          },
        },
        '5': {
          'class_type': 'KSampler',
          '_meta': {'title': 'K采样器'},
          'inputs': {'positive': ['2', 0]},
        },
      });

      // 「K采样器」是 ComfyUI 前端给的节点名，不是我们翻译的
      expect(roles['2']?.links.first, (label: 'K采样器', slot: 'positive'));
    });

    test('加载类也只看连线 —— 卡片上那句话只有一种含义', () {
      final roles = inferNodeRoles(_workflow);

      // 模型名在参数行里写着当前值，这里不再重复；只回答「接去哪」
      expect(roles['1']?.links, contains((label: 'KSampler', slot: 'model')));
      // 装着 LoRA 但没有任何下游 → 不给位置说明（宁可不说）
      expect(roles['7'], isNull);
    });

    test('链式加载也按连线分得清（LoRA 接给谁）', () {
      final roles = inferNodeRoles({
        '1': {
          'class_type': 'CheckpointLoaderSimple',
          'inputs': {'ckpt_name': 'v1.safetensors'},
        },
        '7': {
          'class_type': 'LoraLoader',
          'inputs': {
            'lora_name': 'film.safetensors',
            'model': ['1', 0],
          },
        },
        '5': {
          'class_type': 'KSampler',
          'inputs': {
            'model': ['7', 0],
          },
        },
      });

      expect(roles['1']?.links, [(label: 'LoraLoader', slot: 'model')]);
      expect(roles['7']?.links, [(label: 'KSampler', slot: 'model')]);
    });

    test('下游接了好几个同名节点同一个槽，算一处', () {
      final roles = inferNodeRoles(_workflow);

      // '1' 同时喂给两个文本编码的 clip：不合并就会写成「等 2 处」，
      // 而两处长得一模一样（接给 LoraLoader.clip 是另一处，不算重复）
      final clipLinks = roles['1']!.links.where(
        (l) => l == (label: 'CLIPTextEncode', slot: 'clip'),
      );
      expect(clipLinks.length, 1);

      // '2' 同时喂给两个采样器的 positive，同理只算一处
      expect(roles['2']!.links.length, 1);
    });

    test('接了好几处时，条件槽位排在最前面', () {
      final roles = inferNodeRoles({
        '2': {
          'class_type': 'CLIPTextEncode',
          'inputs': {'text': 'a cat'},
        },
        '8': {
          'class_type': 'ControlNetApply',
          'inputs': {
            'conditioning': ['2', 0],
          },
        },
        '5': {
          'class_type': 'KSampler',
          'inputs': {'positive': ['2', 0]},
        },
      });

      // 两处都保留，但先报 positive（任务里最容易混淆的就是它）
      expect(roles['2']!.links.length, 2);
      expect(roles['2']!.links.first, (label: 'KSampler', slot: 'positive'));
      expect(
        roles['2']!.links.last,
        (label: 'ControlNetApply', slot: 'conditioning'),
      );
    });

    test('采样器不再贴「起始 / 精修」这种自己发明的标签', () {
      final roles = inferNodeRoles(_workflow);

      // 只按连线说话：'5' 的输出接到 '6' 的 latent_image，'6' 没有下游就别编
      expect(roles['5']?.links, [(label: 'KSampler', slot: 'latent_image')]);
      expect(roles['6'], isNull);
    });

    test('没有下游的节点不出现在结果里，绝不硬猜', () {
      final roles = inferNodeRoles({
        '4': {
          'class_type': 'EmptyLatentImage',
          'inputs': {'width': 512},
        },
        '8': {
          'class_type': 'VAEDecode',
          'inputs': {
            'samples': ['5', 0],
            'vae': ['1', 2],
          },
        },
      });

      expect(roles['4'], isNull);
      expect(roles['8'], isNull);
    });
  });

  group('用途分类', () {
    test('规则表里的类型各归其位', () {
      expect(
        WorkflowNodeParser.categoryFor('CLIPTextEncode'),
        ParamCategory.prompt,
      );
      expect(
        WorkflowNodeParser.categoryFor('KSampler'),
        ParamCategory.sampling,
      );
      expect(
        WorkflowNodeParser.categoryFor('EmptyLatentImage'),
        ParamCategory.size,
      );
      expect(
        WorkflowNodeParser.categoryFor('CheckpointLoaderSimple'),
        ParamCategory.model,
      );
      expect(WorkflowNodeParser.categoryFor('LoraLoader'), ParamCategory.model);
      expect(
        WorkflowNodeParser.categoryFor('ControlNetApplyAdvanced'),
        ParamCategory.control,
      );
    });

    test('没收录的类型落在其余，不会消失', () {
      expect(
        WorkflowNodeParser.categoryFor('SomeCommunityNode'),
        ParamCategory.other,
      );
    });
  });
}
