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
  group('节点角色', () {
    test('两个同名的文本编码按接到的槽位区分正负向', () {
      final roles = inferNodeRoles(_workflow);

      // 光看类名这两个节点一模一样，区别只在它接到了采样器的哪个口
      expect(roles['2']?.kind, NodeRoleKind.positive);
      expect(roles['3']?.kind, NodeRoleKind.negative);
    });

    test('两个同名的采样器按 latent 来源区分起始 / 精修', () {
      final roles = inferNodeRoles(_workflow);

      // '5' 的 latent 来自空画布，'6' 接着 '5' 的输出继续采
      expect(roles['5']?.kind, NodeRoleKind.baseSampler);
      expect(roles['6']?.kind, NodeRoleKind.refinerSampler);
    });

    test('加载类直接说装了什么，路径与扩展名都去掉', () {
      final roles = inferNodeRoles(_workflow);

      expect(roles['1']?.kind, NodeRoleKind.asset);
      expect(roles['1']?.assetName, 'v1-5');
      expect(roles['7']?.assetName, 'film_grain');
    });

    test('连线引用不当资源名 —— 否则会显示成一串节点号', () {
      // LoraLoader 的 model 是连线 ['1', 0]，不能拿来当名字
      final roles = inferNodeRoles({
        '9': {
          'class_type': 'LoraLoader',
          'inputs': {
            'model': ['1', 0],
            'clip': ['1', 1],
            'strength_model': 0.8,
          },
        },
      });

      expect(roles['9'], isNull);
    });

    test('认不出来就干脆不给，绝不硬猜', () {
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

    test('没有连线的孤立条件节点也认不出来', () {
      final roles = inferNodeRoles({
        '2': {
          'class_type': 'CLIPTextEncode',
          'inputs': {'text': 'a cat'},
        },
      });

      expect(roles['2'], isNull);
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
