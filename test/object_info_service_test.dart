import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:comfyui_mobilepocket/services/object_info_service.dart';

/// 构造一个单节点说明书响应。
/// 结构按真实接口：{"<类名>": {"input": {"required": {...}}}}
String _body(Map<String, dynamic> input, {String classType = 'KSampler'}) =>
    jsonEncode({
      classType: {'input': input},
    });

String _required(dynamic spec, {String key = 'ckpt_name'}) => _body({
  'required': {key: spec},
});

void main() {
  group('解析：COMBO 的三种形态', () {
    test('形态 A：选项直接是列表 → 取到真实选项', () {
      final spec = ObjectInfoService.parseNodeSpec(
        _required([
          ['a.safetensors', 'b.safetensors'],
          {'tooltip': 'x'},
        ]),
        'KSampler',
      );
      expect(spec['ckpt_name']!.isCombo, isTrue);
      expect(spec['ckpt_name']!.options, ['a.safetensors', 'b.safetensors']);
    });

    test('形态 A 但列表为空：确实问到了，只是服务器上一个都没有', () {
      // 报文里是 "ckpt_name": [[], {}] —— 选项列表本身是空的
      final spec = ObjectInfoService.parseNodeSpec(
        _required([<String>[]]),
        'KSampler',
      );
      expect(spec['ckpt_name']!.isCombo, isTrue);
      expect(spec['ckpt_name']!.options, isEmpty);
    });

    test('形态 B：["COMBO", {"options": [...]}] → 取到真实选项', () {
      final spec = ObjectInfoService.parseNodeSpec(
        _required([
          'COMBO',
          {
            'options': ['x', 'y'],
          },
        ]),
        'KSampler',
      );
      expect(spec['ckpt_name']!.isCombo, isTrue);
      expect(spec['ckpt_name']!.options, ['x', 'y']);
    });

    test('形态 B 但没给 options：当作没数据，绝不当成「服务器上一个都没有」', () {
      final spec = ObjectInfoService.parseNodeSpec(
        _required([
          'COMBO',
          {'tooltip': 'x'},
        ]),
        'KSampler',
      );
      expect(spec['ckpt_name']!.isCombo, isFalse);
      expect(spec['ckpt_name']!.options, isEmpty);
    });

    test('形态 C（动态下拉）：静态请求取不到选项，当作没数据', () {
      final spec = ObjectInfoService.parseNodeSpec(
        _required([
          'COMFY_DYNAMICCOMBO_V3',
          {
            'options': [
              {'key': 'a'},
            ],
          },
        ]),
        'KSampler',
      );
      expect(spec['ckpt_name']!.isCombo, isFalse);
      expect(spec['ckpt_name']!.options, isEmpty);
    });
  });

  group('解析：非下拉与其它形态', () {
    test('INT / FLOAT 等不是下拉 → 没有选项', () {
      final spec = ObjectInfoService.parseNodeSpec(
        _required([
          'INT',
          {'default': 20, 'min': 1, 'max': 10000},
        ]),
        'KSampler',
      );
      expect(spec['ckpt_name']!.isCombo, isFalse);
    });

    test('2^64 的边界写成字符串或数字都能解析，不会崩', () {
      // 实测有的版本把它当字符串发、有的当数字发，两种都得扛住。
      // ⚠️ 这个数字连 Dart 源码里都写不下（超 int64），只能用原始报文测。
      for (final raw in const [
        '{"KSampler":{"input":{"required":{"seed":'
            '["INT",{"max":"18446744073709551615"}]}}}}',
        '{"KSampler":{"input":{"required":{"seed":'
            '["INT",{"max":18446744073709551615}]}}}}',
      ]) {
        final spec = ObjectInfoService.parseNodeSpec(raw, 'KSampler');
        expect(spec['seed'], isNotNull);
        expect(spec['seed']!.isCombo, isFalse);
      }
    });

    test('只有 [TYPE] 一项、没有元数据 → 不抛，当作没数据', () {
      final spec = ObjectInfoService.parseNodeSpec(
        _required(['INT']),
        'KSampler',
      );
      expect(spec['ckpt_name']!.isCombo, isFalse);
    });
  });

  group('解析：分区取舍', () {
    test('hidden 分区一律不读（否则会把 PROMPT 当普通参数提交）', () {
      final spec = ObjectInfoService.parseNodeSpec(
        _body({
          'required': {
            'ckpt_name': [
              'COMBO',
              {
                'options': ['a'],
              },
            ],
          },
          'hidden': {
            'prompt': ['PROMPT', {}],
          },
        }),
        'KSampler',
      );
      expect(spec.containsKey('ckpt_name'), isTrue);
      expect(spec.containsKey('prompt'), isFalse);
    });

    test('optional 分区会读（参数可能不在 required 里）', () {
      final spec = ObjectInfoService.parseNodeSpec(
        _body({
          'optional': {
            'denoise': [
              'FLOAT',
              {'default': 1.0},
            ],
          },
        }),
        'KSampler',
      );
      expect(spec.containsKey('denoise'), isTrue);
    });

    test('required 与 optional 同名时以 required 为准', () {
      final spec = ObjectInfoService.parseNodeSpec(
        _body({
          'required': {
            'x': [
              'COMBO',
              {
                'options': ['from_required'],
              },
            ],
          },
          'optional': {
            'x': [
              'COMBO',
              {
                'options': ['from_optional'],
              },
            ],
          },
        }),
        'KSampler',
      );
      expect(spec['x']!.options, ['from_required']);
    });
  });

  group('解析：异常一律不抛', () {
    test('不是合法 JSON', () {
      expect(
        ObjectInfoService.parseNodeSpec('not json at all', 'KSampler'),
        isEmpty,
      );
    });

    test('空响应体', () {
      expect(ObjectInfoService.parseNodeSpec('', 'KSampler'), isEmpty);
    });

    test('顶层是数组而不是对象', () {
      expect(ObjectInfoService.parseNodeSpec('[]', 'KSampler'), isEmpty);
    });

    test('缺 input 字段', () {
      expect(
        ObjectInfoService.parseNodeSpec(
          jsonEncode({
            'KSampler': {
              'output': ['LATENT'],
            },
          }),
          'KSampler',
        ),
        isEmpty,
      );
    });

    test('类名对不上时容错取第一个值', () {
      final spec = ObjectInfoService.parseNodeSpec(
        _body({
          'required': {
            'ckpt_name': [
              'COMBO',
              {
                'options': ['a'],
              },
            ],
          },
        }, classType: 'OtherName'),
        'KSampler',
      );
      expect(spec['ckpt_name']!.options, ['a']);
    });

    test('单个参数定义是空数组时跳过，不影响其它参数', () {
      final spec = ObjectInfoService.parseNodeSpec(
        _body({
          'required': {
            'bad': [],
            'good': [
              'COMBO',
              {
                'options': ['a'],
              },
            ],
          },
        }),
        'KSampler',
      );
      expect(spec.containsKey('bad'), isFalse);
      expect(spec['good']!.options, ['a']);
    });
  });

  group('NodeInputSpec.contains', () {
    test('空值与不在列表里都算缺失', () {
      final spec = NodeInputSpec(isCombo: true, options: ['a']);
      expect(spec.contains('a'), isTrue);
      expect(spec.contains('b'), isFalse);
      expect(spec.contains(null), isFalse);
      expect(spec.contains(''), isFalse);
    });
  });

  group('允许取真实选项的参数名单', () {
    test('模型类与采样类在名单内', () {
      for (final key in const [
        'ckpt_name',
        'unet_name',
        'clip_name',
        'vae_name',
        'lora_name',
        'control_net_name',
        'upscale_model',
        'sampler_name',
        'scheduler',
      ]) {
        expect(kDynamicOptionKeys.contains(key), isTrue, reason: key);
      }
    });

    test('⚠️ 图片上传参数绝不能在名单内（否则用户传不了新图）', () {
      for (final key in const ['image', 'image_path']) {
        expect(kDynamicOptionKeys.contains(key), isFalse, reason: key);
      }
    });
  });

  group('下拉该怎么显示', () {
    test('没拿到服务器数据 → 用工作流当前值，跟以前一样，不做任何判定', () {
      final view = resolveEnumOptions(
        hasServerData: false,
        serverOptions: const ['a', 'b'],
        currentValue: 'workflow_value',
        fallbackOptions: const ['workflow_value'],
      );
      expect(view.options, ['workflow_value']);
      expect(view.selected, 'workflow_value');
      expect(view.fromServer, isFalse);
      expect(view.missingOnServer, isFalse);
    });

    test('拿到数据且当前值在里面 → 选中它', () {
      final view = resolveEnumOptions(
        hasServerData: true,
        serverOptions: const ['a', 'b'],
        currentValue: 'b',
        fallbackOptions: const ['b'],
      );
      expect(view.options, ['a', 'b']);
      expect(view.selected, 'b');
      expect(view.missingOnServer, isFalse);
    });

    test('拿到数据但当前值不在里面 → 不塞进选项，也不选中', () {
      final view = resolveEnumOptions(
        hasServerData: true,
        serverOptions: const ['a', 'b'],
        currentValue: 'gone.safetensors',
        fallbackOptions: const ['gone.safetensors'],
      );
      expect(view.options, ['a', 'b']);
      expect(view.options.contains('gone.safetensors'), isFalse);
      expect(view.selected, isNull);
      expect(view.missingOnServer, isTrue);
    });

    test('拿到数据但服务器上一个都没有 → 选项为空且标记缺失', () {
      final view = resolveEnumOptions(
        hasServerData: true,
        serverOptions: const [],
        currentValue: 'x.safetensors',
        fallbackOptions: const ['x.safetensors'],
      );
      expect(view.options, isEmpty);
      expect(view.selected, isNull);
      expect(view.missingOnServer, isTrue);
    });

    test('没拿到数据且没备选时，用当前值兜底而不是留空', () {
      final view = resolveEnumOptions(
        hasServerData: false,
        serverOptions: const [],
        currentValue: 'x',
        fallbackOptions: const [],
      );
      expect(view.options, ['x']);
      expect(view.selected, 'x');
    });

    test('没拿到数据且当前值也不在备选里 → 退回第一项，不算缺失', () {
      final view = resolveEnumOptions(
        hasServerData: false,
        serverOptions: const [],
        currentValue: 'x',
        fallbackOptions: const ['a', 'b'],
      );
      expect(view.selected, 'a');
      expect(view.missingOnServer, isFalse);
    });
  });

  group('解析：数值参数的 min/max/step', () {
    test('INT 元数据 → 取到上下限与步进', () {
      final spec = ObjectInfoService.parseNodeSpec(
        _required([
          'INT',
          {'default': 20, 'min': 1, 'max': 100, 'step': 1},
        ], key: 'steps'),
        'KSampler',
      );
      final s = spec['steps']!;
      expect(s.min, 1);
      expect(s.max, 100);
      expect(s.step, 1);
      expect(s.hasBounds, isTrue);
      expect(s.hasSliderRange, isTrue);
    });

    test('max 是超 int64 的字符串（种子类）→ 能校验但不画滑块', () {
      final spec = ObjectInfoService.parseNodeSpec(
        _required([
          'INT',
          {'min': 0, 'max': '18446744073709551615'},
        ], key: 'seed'),
        'KSampler',
      );
      final s = spec['seed']!;
      expect(s.max, 18446744073709551615.0);
      expect(s.hasBounds, isTrue);
      // 天文数字画成滑块没有意义
      expect(s.hasSliderRange, isFalse);
    });

    test('没有元数据 → 没有任何边界，不算范围', () {
      final spec = ObjectInfoService.parseNodeSpec(
        _required(['FLOAT'], key: 'cfg'),
        'KSampler',
      );
      final s = spec['cfg']!;
      expect(s.min, isNull);
      expect(s.hasBounds, isFalse);
      expect(checkNumberAgainstSpec(spec: s, text: '99999'), isNull);
    });

    test('max <= min 的畸形定义 → 不算范围', () {
      const bad = NodeInputSpec(isCombo: false, min: 10, max: 10);
      expect(bad.hasBounds, isFalse);
    });

    test('只填了 min → 不算范围（不猜上界）', () {
      const half = NodeInputSpec(isCombo: false, min: 1);
      expect(half.hasBounds, isFalse);
    });
  });

  group('数值校验 checkNumberAgainstSpec', () {
    const spec = NodeInputSpec(isCombo: false, min: 1, max: 100);

    test('范围内 → 没问题', () {
      expect(checkNumberAgainstSpec(spec: spec, text: '50'), isNull);
    });

    test('超出上界 / 下界 → outOfRange', () {
      expect(
        checkNumberAgainstSpec(spec: spec, text: '101'),
        NumberIssue.outOfRange,
      );
      expect(
        checkNumberAgainstSpec(spec: spec, text: '0'),
        NumberIssue.outOfRange,
      );
    });

    test('不是数字 → notANumber', () {
      expect(
        checkNumberAgainstSpec(spec: spec, text: 'abc'),
        NumberIssue.notANumber,
      );
    });

    test('空值不在这里报，交给提交侧', () {
      expect(checkNumberAgainstSpec(spec: spec, text: ''), isNull);
      expect(checkNumberAgainstSpec(spec: spec, text: '  '), isNull);
    });

    test('小数与负数按数值比较，不做字符串比较', () {
      const f = NodeInputSpec(isCombo: false, min: 0, max: 1);
      expect(checkNumberAgainstSpec(spec: f, text: '0.5'), isNull);
      expect(
        checkNumberAgainstSpec(spec: f, text: '0.9'),
        isNull, // 字符串比较会误判 "0.9" > "1"
      );
      expect(
        checkNumberAgainstSpec(spec: f, text: '2'),
        NumberIssue.outOfRange,
      );
    });

    test('拿不到说明书 → 一律不报错', () {
      expect(checkNumberAgainstSpec(spec: null, text: 'whatever'), isNull);
    });
  });
}
