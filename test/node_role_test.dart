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
      expect(roles['2']?.isLink, isTrue);
      expect(roles['2']?.targetLabel, 'KSampler');
      expect(roles['2']?.slot, 'positive');
      expect(roles['3']?.targetLabel, 'KSampler');
      expect(roles['3']?.slot, 'negative');
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
      expect(roles['2']?.targetLabel, 'K采样器');
      expect(roles['2']?.slot, 'positive');
    });

    test('采样器不再贴「起始 / 精修」这种自己发明的标签', () {
      final roles = inferNodeRoles(_workflow);

      // 只按连线说话：'5' 的输出接到 '6' 的 latent_image，'6' 没有下游就别编
      expect(roles['5']?.targetLabel, 'KSampler');
      expect(roles['5']?.slot, 'latent_image');
      expect(roles['6'], isNull);
    });

    test('加载类直接说装了什么，路径与扩展名都去掉', () {
      final roles = inferNodeRoles(_workflow);

      expect(roles['1']?.assetName, 'v1-5');
      expect(roles['7']?.assetName, 'film_grain');
      // 资源名比「它接去哪」更值得占这一行
      expect(roles['1']?.isLink, isFalse);
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

    test('多个下游又说不清是哪一路 → 干脆不说', () {
      // 同一张空画布喂两个采样器：说「连到 KSampler · latent_image」会让人
      // 以为只连了一个
      final roles = inferNodeRoles({
        '1': {
          'class_type': 'EmptyLatentImage',
          'inputs': {'width': 512},
        },
        '2': {
          'class_type': 'KSampler',
          'inputs': {
            'latent_image': ['1', 0],
          },
        },
        '3': {
          'class_type': 'KSampler',
          'inputs': {
            'latent_image': ['1', 0],
          },
        },
      });

      expect(roles['1'], isNull);
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
