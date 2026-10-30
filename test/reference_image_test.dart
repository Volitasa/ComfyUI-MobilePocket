import 'package:flutter_test/flutter_test.dart';

import 'package:comfyui_mobilepocket/services/reference_image.dart';

/// 一个典型的双图编辑工作流：两张 LoadImage 都喂进编辑节点，
/// 其中一个还接了 ControlNet，外加一个和图片无关的节点。
Map<String, dynamic> _workflow() => {
  '10': {
    'class_type': 'LoadImage',
    'inputs': {'image': 'face.png'},
    '_meta': {'title': '加载图像'},
  },
  '11': {
    'class_type': 'LoadImage',
    'inputs': {'image': 'cloth.jpg'},
    '_meta': {'title': '衣服'},
  },
  '12': {
    'class_type': 'LoadImage',
    'inputs': {'image': 'face.png'},
    '_meta': {'title': '第二张脸'},
  },
  '13': {
    'class_type': 'ControlNetApply',
    'inputs': {
      'image': ['10', 0], // 连线引用，不是文件名
      'strength': 0.8,
    },
  },
  '14': {
    'class_type': 'KSampler',
    'inputs': {'seed': 42, 'positive': ['20', 0]},
  },
  '15': {
    'class_type': 'LoadImage',
    'inputs': {'image': 'example'}, // ComfyUI 默认的占位值，没有扩展名
  },
};

void main() {
  group('collectReferenceImages', () {
    test('按参数名认出所有图片输入，连线引用与无扩展名值都被跳过', () {
      final refs = collectReferenceImages(workflowJson: _workflow());
      // 10 / 11 各一条；12 与 10 是同一张图（合并）；13 是连线、15 是 example
      expect(refs.length, 2);
      expect(refs[0].ref.filename, 'face.png');
      expect(refs[1].ref.filename, 'cloth.jpg');
    });

    test('同一张图被多个节点用：合并成一条并记处数', () {
      final refs = collectReferenceImages(workflowJson: _workflow());
      final face = refs.firstWhere((r) => r.ref.filename == 'face.png');
      expect(face.mergeCount, 2);
      // 合并时保留第一条的官方名，不拼两个名字
      expect(face.label, '加载图像');
    });

    test('节点名优先取 _meta.title，缺了退 class_type', () {
      final refs = collectReferenceImages(workflowJson: _workflow());
      expect(refs[0].label, '加载图像');
      expect(refs[1].label, '衣服');
    });

    test('params 里的值覆盖工作流原值，并标 fromParams', () {
      final refs = collectReferenceImages(
        workflowJson: _workflow(),
        params: {'10:image': 'upload_20261030.png'},
      );
      expect(refs[0].ref.filename, 'upload_20261030.png');
      expect(refs[0].fromParams, isTrue);
      // 没被覆盖的那张仍来自工作流
      expect(refs[1].ref.filename, 'cloth.jpg');
      expect(refs[1].fromParams, isFalse);
    });

    test('未暴露的图片节点靠工作流原值兜住（params 里没有它）', () {
      // 这正是最常见的图生图场景：用户只暴露了提示词，没暴露 LoadImage
      final refs = collectReferenceImages(
        workflowJson: _workflow(),
        params: {'14:seed': 42},
      );
      expect(refs.map((r) => r.ref.filename), containsAll(['face.png', 'cloth.jpg']));
    });

    test('值带目录注解时按注解解析（从输出目录挑的图）', () {
      final refs = collectReferenceImages(
        workflowJson: {
          '10': {
            'class_type': 'LoadImage',
            'inputs': {'image': 'ComfyUI_00001_.png [output]'},
          },
        },
      );
      expect(refs.single.ref.filename, 'ComfyUI_00001_.png');
      expect(refs.single.ref.type, 'output');
    });

    test('没有快照时退化成只扫 params，节点名用回退函数；没有回退就用参数名', () {
      final refs = collectReferenceImages(
        workflowJson: null,
        params: {
          '10:image': 'a.png',
          '11:image_path': 'b.png',
          '14:seed': 7, // 不是图片参数，忽略
        },
        labelFallback: (id) => id == '10' ? '加载图像' : '',
      );
      expect(refs.length, 2);
      expect(refs[0].label, '加载图像');
      expect(refs[0].fromParams, isTrue);
      // 拿不到名字时不编节点名，退回参数名
      expect(refs[1].label, 'image_path');
    });

    test('既没有快照也没有参数时返回空列表，不抛错', () {
      expect(collectReferenceImages(workflowJson: null), isEmpty);
      expect(collectReferenceImages(workflowJson: {}), isEmpty);
    });

    test('外包一层 {"prompt": ...} 的工作流也能扫（与解析侧同一套归一化）', () {
      final refs = collectReferenceImages(
        workflowJson: {
          'prompt': _workflow(),
          'client_id': 'abc',
        },
      );
      expect(refs.length, 2);
    });
  });
}
