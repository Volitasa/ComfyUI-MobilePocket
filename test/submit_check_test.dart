import 'package:flutter_test/flutter_test.dart';

import 'package:comfyui_mobilepocket/models/workflow_node.dart';
import 'package:comfyui_mobilepocket/services/object_info_service.dart';
import 'package:comfyui_mobilepocket/services/submit_check.dart';

/// 提交前检查（方案 §3.7）的纯函数测试。
///
/// 四条规则必须分开验，因为它们对**同一种空响应**的处理是相反的：
/// - 取数成功但服务器返回 `{}` → 缺节点 → **拦**
/// - 取数失败（断网 / 超时 / 非 200）→ 不知道 → **不拦**
/// - 说明书里没这个键 → 版本差异 → **不拦**
/// - 下拉当前值不在选项里（只认模型 / 采样器类键）→ **拦**

WorkflowNode _node({
  String classType = 'CheckpointLoaderSimple',
  String key = 'ckpt_name',
  String alias = '大模型',
  ParamType paramType = ParamType.enumType,
  ParamControl? control = ParamControl.select,
  dynamic value = 'old.safetensors',
}) => WorkflowNode(
  id: '4',
  classType: classType,
  key: key,
  alias: alias,
  exposed: true,
  title: '',
  paramType: paramType,
  value: value,
  control: control,
);

/// 造一次调用的公共壳，只暴露需要的三个可变参数。
SubmitBlock? _check(
  List<WorkflowNode> config, {
  required ObjectInfoFetchStatus? status,
  NodeSpec? spec,
}) => checkBeforeSubmit(
  config: config,
  statusOf: (_) => status,
  specOf: (_, key) => spec?[key],
  controlOf: (n) => n.control ?? ParamControl.text,
  currentOf: (n) => n.value?.toString(),
);

const NodeSpec _comboSpec = {
  'ckpt_name': NodeInputSpec(
    isCombo: true,
    declaredType: 'COMBO',
    options: ['a.safetensors', 'b.safetensors'],
    rawOptions: ['a.safetensors', 'b.safetensors'],
  ),
};

void main() {
  group('缺节点：取数成功但服务器返回 {} → 拦', () {
    test('status == empty 且 spec 为空 → 拦下并带走类名', () {
      final block = _check(
        [_node()],
        status: ObjectInfoFetchStatus.empty,
        spec: const {},
      );
      expect(block, isNotNull);
      expect(block!.classType, 'CheckpointLoaderSimple');
      expect(block.alias, isNull);
    });
  });

  group('取数失败 / 没问过 → 不拦（不知道就别拦）', () {
    test('status == failure → 放行', () {
      expect(
        _check(
          [_node()],
          status: ObjectInfoFetchStatus.failure,
          spec: const {},
        ),
        isNull,
      );
    });

    test('status == null（从没问过）→ 放行', () {
      expect(_check([_node()], status: null), isNull);
    });
  });

  group('缺参数：说明书里没这个键 → 不拦', () {
    test('说明书取到了、但没有 ckpt_name → 放行，照旧提交原值', () {
      final block = _check(
        [_node()],
        status: ObjectInfoFetchStatus.ok,
        spec: const {
          'other_key': NodeInputSpec(
            isCombo: true,
            declaredType: 'COMBO',
            options: ['x'],
            rawOptions: ['x'],
          ),
        },
      );
      expect(block, isNull);
    });
  });

  group('缺选项：下拉当前值不在服务器选项里 → 拦', () {
    test('当前值服务器没有 → 拦下并带走参数别名', () {
      final block = _check(
        [_node(value: 'old.safetensors')],
        status: ObjectInfoFetchStatus.ok,
        spec: _comboSpec,
      );
      expect(block, isNotNull);
      expect(block!.alias, '大模型');
      expect(block.classType, isNull);
    });

    test('当前值在选项里 → 放行', () {
      expect(
        _check(
          [_node(value: 'a.safetensors')],
          status: ObjectInfoFetchStatus.ok,
          spec: _comboSpec,
        ),
        isNull,
      );
    });

    test('只认模型 / 采样器类键：device 不在选项里也放行', () {
      // `device` 在 kExtraComboKeys 里、会被取成下拉，但服务器版本一变
      // 选项就变，全拦会大面积误伤（方案 §3.7 的第二条 🔴 注）
      final block = _check(
        [
          _node(
            classType: 'CLIPLoader',
            key: 'device',
            alias: '设备',
            paramType: ParamType.text,
            value: 'cuda',
          ),
        ],
        status: ObjectInfoFetchStatus.ok,
        spec: const {
          'device': NodeInputSpec(
            isCombo: true,
            declaredType: 'COMBO',
            options: ['default', 'cpu'],
            rawOptions: ['default', 'cpu'],
          ),
        },
      );
      expect(block, isNull);
    });

    test('不是下拉的控件不查选项（文本框里的值服务器有没有都照发）', () {
      final block = _check(
        [_node(key: 'ckpt_name', value: 'random', control: ParamControl.text)],
        status: ObjectInfoFetchStatus.ok,
        spec: _comboSpec,
      );
      expect(block, isNull);
    });

    test('说明书里没有任何选项（服务器上一个模型都没装）→ 放行', () {
      // 判断不了「服务器没有」还是「我们没问到」，不拦
      final block = _check(
        [_node(value: 'old.safetensors')],
        status: ObjectInfoFetchStatus.ok,
        spec: const {
          'ckpt_name': NodeInputSpec(isCombo: false, declaredType: 'COMBO'),
        },
      );
      expect(block, isNull);
    });
  });

  group('多条参数时的优先级', () {
    test('缺节点优先于缺选项（节点都没有，谈不上选项）', () {
      final block = checkBeforeSubmit(
        config: [
          _node(value: 'old.safetensors'),
          _node(classType: 'GhostNode', key: 'sampler_name', alias: '采样器'),
        ],
        statusOf: (classType) => classType == 'GhostNode'
            ? ObjectInfoFetchStatus.empty
            : ObjectInfoFetchStatus.ok,
        specOf: (_, key) => key == 'ckpt_name' ? _comboSpec['ckpt_name'] : null,
        controlOf: (n) => n.control ?? ParamControl.text,
        currentOf: (n) => n.value?.toString(),
      );
      // 第一个参数缺选项，顺序上先命中它
      expect(block, isNotNull);
      expect(block!.alias, '大模型');

      final onlyNode = _check(
        [_node(classType: 'GhostNode', key: 'sampler_name', alias: '采样器')],
        status: ObjectInfoFetchStatus.empty,
        spec: const {},
      );
      expect(onlyNode!.classType, 'GhostNode');
    });
  });
}
