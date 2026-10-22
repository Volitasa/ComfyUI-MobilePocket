import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:comfyui_mobilepocket/models/workflow_node.dart';
import 'package:comfyui_mobilepocket/services/object_info_service.dart';

/// 只返回预设结果的假客户端，用来测 `fetchNodeSpec` 的三态。
class _FakeClient extends http.BaseClient {
  _FakeClient({this.status = 200, this.body = '{}', this.error});

  final int status;
  final String body;
  final Object? error;

  /// 记录被请求的路径，用于断言「空参数时不发请求」。
  final List<String> requested = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requested.add(request.url.path);
    if (error != null) throw error!;
    return http.StreamedResponse(
      Stream<List<int>>.value(utf8.encode(body)),
      status,
      request: request,
    );
  }
}

/// 单节点说明书响应：{"<类名>": {"input": {...}}}
String _body(
  Map<String, dynamic> input, {
  String classType = 'KSampler',
}) =>
    jsonEncode({
      classType: {'input': input},
    });

String _required(
  dynamic spec, {
  String key = 'ckpt_name',
  String classType = 'KSampler',
}) =>
    _body({
      'required': {key: spec},
    }, classType: classType);

void main() {
  group('选项原始类型（方案 §3.6）', () {
    test('混整数的选项保持原始类型：8 不是 "8"', () {
      final spec = ObjectInfoService.parseNodeSpec(
        _required(
          [
            'COMBO',
            {
              'options': ['auto', 8, 10],
            },
          ],
          key: 'bit_depth',
          classType: 'CreateVideo',
        ),
        'CreateVideo',
      );
      final s = spec['bit_depth']!;
      expect(s.isCombo, isTrue);
      // options 只用于显示，仍是字符串
      expect(s.options, ['auto', '8', '10']);
      // rawOptions 保留服务器给的类型
      expect(s.rawOptions, ['auto', 8, 10]);
      expect(s.rawOptions[1], isA<int>());
      expect(s.rawOptions[2], isA<int>());
    });

    test('rawOf：由显示值取回原始值，类型不变', () {
      final s = NodeInputSpec(
        isCombo: true,
        options: const ['auto', '8', '10'],
        rawOptions: const ['auto', 8, 10],
      );
      expect(s.rawOf('8'), 8);
      expect(s.rawOf('8'), isA<int>());
      expect(s.rawOf('auto'), 'auto');
    });

    test('形态 A（选项直接是列表）也保留原始类型', () {
      final spec = ObjectInfoService.parseNodeSpec(
        _required([
          ['auto', 8, 10],
        ], key: 'bit_depth', classType: 'CreateVideo'),
        'CreateVideo',
      );
      expect(spec['bit_depth']!.rawOptions, ['auto', 8, 10]);
      expect(spec['bit_depth']!.rawOptions[1], isA<int>());
    });

    test('⚠️ 过滤空串后 options 与 rawOptions 仍一一对应', () {
      final spec = ObjectInfoService.parseNodeSpec(
        _required(
          [
            'COMBO',
            {
              'options': ['', 'a', 8, ''],
            },
          ],
          key: 'x',
        ),
        'KSampler',
      );
      final s = spec['x']!;
      expect(s.options, ['a', '8']);
      expect(s.rawOptions, ['a', 8]);
      expect(s.options.length, s.rawOptions.length);
      for (var i = 0; i < s.options.length; i++) {
        expect(s.rawOptions[i].toString(), s.options[i], reason: '下标 $i 错位');
      }
    });

    test('rawOptions 缺失时 rawOf 退回显示串（旧数据不炸）', () {
      final s = NodeInputSpec(isCombo: true, options: ['a']);
      expect(s.rawOf('a'), 'a');
      expect(s.rawOf(null), isNull);
    });
  });

  group('declaredType / advanced', () {
    test('解析声明类型：COMBO / INT / FLOAT / STRING / BOOLEAN', () {
      final spec = ObjectInfoService.parseNodeSpec(
        _body({
          'required': {
            'ckpt_name': [
              'COMBO',
              {
                'options': ['a'],
              },
            ],
            'steps': [
              'INT',
              {'default': 20},
            ],
            'cfg': [
              'FLOAT',
              {'default': 7},
            ],
            'text': [
              'STRING',
              {'multiline': true},
            ],
            'flag': [
              'BOOLEAN',
              {'default': false},
            ],
          },
        }),
        'KSampler',
      );
      expect(spec['ckpt_name']!.declaredType, 'COMBO');
      expect(spec['steps']!.declaredType, 'INT');
      expect(spec['cfg']!.declaredType, 'FLOAT');
      expect(spec['text']!.declaredType, 'STRING');
      expect(spec['flag']!.declaredType, 'BOOLEAN');
    });

    test('动态下拉也记下声明类型（但 isCombo 仍是 false）', () {
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
      expect(spec['ckpt_name']!.declaredType, 'COMFY_DYNAMICCOMBO_V3');
      expect(spec['ckpt_name']!.isCombo, isFalse);
    });

    test('optional 段里的 advanced 会被解析（只影响展示，不参与默认勾选）', () {
      final spec = ObjectInfoService.parseNodeSpec(
        _body({
          'optional': {
            'device': [
              'COMBO',
              {
                'options': ['default', 'cpu'],
                'advanced': true,
              },
            ],
          },
        }),
        'CLIPLoader',
      );
      expect(spec['device']!.advanced, isTrue);
      expect(spec['device']!.isCombo, isTrue);
    });

    test('没标 advanced 的参数为 false', () {
      final spec = ObjectInfoService.parseNodeSpec(
        _required([
          'COMBO',
          {
            'options': ['a'],
          },
        ]),
        'KSampler',
      );
      expect(spec['ckpt_name']!.advanced, isFalse);
    });
  });

  group('fetchNodeSpec 三态（方案 §3.7）', () {
    late http.Client original;

    setUp(() {
      original = ObjectInfoService.instance.client;
    });

    tearDown(() {
      ObjectInfoService.instance.client = original;
    });

    test('服务器 200 回 {} → empty：确实不认识这个节点', () async {
      ObjectInfoService.instance.client = _FakeClient(body: '{}');
      final r = await ObjectInfoService.instance.fetchNodeSpec(
        'http://127.0.0.1:8190',
        'DefinitelyNotARealNode',
      );
      expect(r.status, ObjectInfoFetchStatus.empty);
      expect(r.isMissingOnServer, isTrue);
      expect(r.isFailure, isFalse);
      expect(r.hasSpec, isFalse);
    });

    test('网络异常 → failure：不是「服务器不认识」，只是我们不知道', () async {
      ObjectInfoService.instance.client = _FakeClient(
        error: const SocketException('down'),
      );
      final r = await ObjectInfoService.instance.fetchNodeSpec(
        'http://127.0.0.1:8190',
        'KSampler',
      );
      expect(r.status, ObjectInfoFetchStatus.failure);
      expect(r.isFailure, isTrue);
      expect(r.isMissingOnServer, isFalse);
    });

    test('非 200 → failure', () async {
      ObjectInfoService.instance.client = _FakeClient(status: 404);
      final r = await ObjectInfoService.instance.fetchNodeSpec(
        'http://127.0.0.1:8190',
        'KSampler',
      );
      expect(r.isFailure, isTrue);
      expect(r.isMissingOnServer, isFalse);
    });

    test('拿到定义 → ok', () async {
      ObjectInfoService.instance.client = _FakeClient(
        body: _required([
          'COMBO',
          {
            'options': ['a', 'b'],
          },
        ]),
      );
      final r = await ObjectInfoService.instance.fetchNodeSpec(
        'http://127.0.0.1:8190',
        'KSampler',
      );
      expect(r.status, ObjectInfoFetchStatus.ok);
      expect(r.hasSpec, isTrue);
      expect(r.spec['ckpt_name']!.options, ['a', 'b']);
    });

    test('baseUrl 或 classType 为空 → failure 且不发请求', () async {
      final client = _FakeClient();
      ObjectInfoService.instance.client = client;
      final a = await ObjectInfoService.instance.fetchNodeSpec('', 'KSampler');
      final b = await ObjectInfoService.instance.fetchNodeSpec('http://x', '');
      expect(a.isFailure, isTrue);
      expect(b.isFailure, isTrue);
      expect(client.requested, isEmpty);
    });

    test('⚠️ 关键回归：failure 与 empty 必须可区分（否则 §3.7 两条规则二选一失效）',
        () async {
          ObjectInfoService.instance.client = _FakeClient(
            error: const SocketException('down'),
          );
          final failure = await ObjectInfoService.instance.fetchNodeSpec(
            'http://127.0.0.1:8190',
            'KSampler',
          );

          ObjectInfoService.instance.client = _FakeClient(body: '{}');
          final empty = await ObjectInfoService.instance.fetchNodeSpec(
            'http://127.0.0.1:8190',
            'KSampler',
          );

          expect(failure.isFailure, isTrue);
          expect(empty.isFailure, isFalse);
          expect(failure.isMissingOnServer, isFalse);
          expect(empty.isMissingOnServer, isTrue);
          // 两者 spec 都是空的，但绝不能只靠 spec 是否为空来判定
          expect(failure.spec.isEmpty, empty.spec.isEmpty);
        });
  });

  group('WorkflowNode.control / bounds 序列化', () {
    test('旧配置（无 control / bounds）能读，字段为 null', () {
      final node = WorkflowNode.fromJson({
        'id': '1',
        'classType': 'KSampler',
        'key': 'seed',
        'alias': '种子',
        'exposed': true,
        'title': '采样器',
        'paramType': 'seed',
        'options': <String>[],
        'value': 123,
      });
      expect(node.control, isNull);
      expect(node.bounds, isNull);
    });

    test('⚠️ 旧配置 toJson 不含新字段（磁盘格式零变化）', () {
      final node = WorkflowNode.fromJson({
        'id': '1',
        'classType': 'KSampler',
        'key': 'seed',
        'alias': '种子',
        'exposed': true,
        'paramType': 'seed',
      });
      final json = node.toJson();
      expect(json.containsKey('control'), isFalse);
      expect(json.containsKey('bounds'), isFalse);
      expect(json.keys, [
        'id',
        'classType',
        'key',
        'alias',
        'exposed',
        'title',
        'paramType',
        'options',
        'value',
      ]);
    });

    test('control / bounds 往返一致', () {
      final node = WorkflowNode(
        id: '3',
        classType: 'KSampler',
        key: 'steps',
        alias: '步数',
        paramType: ParamType.intType,
        value: 20,
        control: ParamControl.slider,
        bounds: ParamBounds(min: 1, max: 150, step: 1),
      );
      final restored = WorkflowNode.fromJson(
        jsonDecode(jsonEncode(node.toJson())) as Map<String, dynamic>,
      );
      expect(restored.control, ParamControl.slider);
      expect(restored.paramType, ParamType.intType,
          reason: 'paramType 必须原样保留，control 不覆盖它');
      expect(restored.bounds!.min, 1);
      expect(restored.bounds!.max, 150);
      expect(restored.bounds!.step, 1);
      expect(restored.bounds!.hasBounds, isTrue);
    });

    test('bounds 只有部分字段时往返不丢', () {
      final node = WorkflowNode(
        id: '4',
        classType: 'X',
        key: 'cfg',
        alias: 'c',
        control: ParamControl.number,
        bounds: ParamBounds(max: 30),
      );
      final restored = WorkflowNode.fromJson(
        jsonDecode(jsonEncode(node.toJson())) as Map<String, dynamic>,
      );
      expect(restored.bounds!.min, isNull);
      expect(restored.bounds!.max, 30);
      expect(restored.bounds!.step, isNull);
      expect(restored.bounds!.hasBounds, isFalse);
    });

    test('⚠️ 未知的 control 名字 → null 走推断，不抛异常', () {
      final node = WorkflowNode.fromJson({
        'id': '5',
        'classType': 'X',
        'key': 'k',
        'alias': 'a',
        'control': 'some_future_control',
        'bounds': 'not a map',
      });
      expect(node.control, isNull);
      expect(node.bounds, isNull);
    });
  });

  group('WorkflowNode.copyWith（方案 §8.1 陷阱 1）', () {
    test('⚠️ 未指定的字段全部保留，control / bounds 不会被清空', () {
      final saved = WorkflowNode(
        id: '7',
        classType: 'CLIPLoader',
        key: 'device',
        alias: '设备',
        exposed: true,
        title: 'CLIP 加载',
        paramType: ParamType.text,
        value: 'cpu',
        control: ParamControl.select,
        bounds: ParamBounds(min: 0, max: 2, step: 1),
      );

      // 模拟配置页合并：新解析出的节点带着新的 paramType / value
      final parsed = WorkflowNode(
        id: '7',
        classType: 'CLIPLoader',
        key: 'device',
        alias: 'device',
        title: 'CLIP 加载',
        paramType: ParamType.text,
        value: 'default',
      );

      final merged = parsed.copyWith(
        alias: saved.alias,
        exposed: saved.exposed,
        control: saved.control,
        bounds: saved.bounds,
      );

      expect(merged.alias, '设备');
      expect(merged.exposed, isTrue);
      expect(merged.control, ParamControl.select);
      expect(merged.bounds!.max, 2);
      // 参数集合 / 类型 / 当前值取新解析
      expect(merged.value, 'default');
    });

    test('copyWith 可显式覆盖为 null 之外的其它值', () {
      final node = WorkflowNode(
        id: '8',
        classType: 'X',
        key: 'k',
        alias: 'a',
        control: ParamControl.text,
      );
      expect(node.copyWith(control: ParamControl.select).control,
          ParamControl.select);
      // 不给 control 时保留原值（不是被清成 null）
      expect(node.copyWith(alias: 'b').control, ParamControl.text);
    });
  });
}
