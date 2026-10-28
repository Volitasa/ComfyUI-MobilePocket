import 'package:flutter_test/flutter_test.dart';
import 'package:comfyui_mobilepocket/models/workflow_node.dart';
import 'package:comfyui_mobilepocket/services/param_order.dart';

WorkflowNode _n(String id, String key, {bool exposed = true}) => WorkflowNode(
  id: id,
  classType: 'Node',
  key: key,
  alias: key,
  exposed: exposed,
);

/// 列表里节点 id 的先后（去重、按首次出现）—— 也就是段顺序 / 运行页卡片顺序。
List<String> _nodeOrder(List<WorkflowNode> nodes) {
  final out = <String>[];
  for (final n in nodes) {
    if (!out.contains(n.id)) out.add(n.id);
  }
  return out;
}

String _key(WorkflowNode n) => '${n.id}:${n.key}';

void main() {
  group('参数分段', () {
    test('按节点分组，顺序取首次出现', () {
      final sections = buildParamSections([
        _n('3', 'width'),
        _n('7', 'text'),
        _n('3', 'height'),
        _n('3', 'batch'),
      ]);
      expect(sections.map((s) => s.nodeId).toList(), ['3', '7']);
      expect(sections.first.params.map(_key).toList(), [
        '3:width',
        '3:height',
        '3:batch',
      ]);
    });

    test('同一节点的参数不连续时也会被聚到一起', () {
      final sections = buildParamSections([
        _n('a', 'x'),
        _n('b', 'y'),
        _n('a', 'z'),
      ]);
      expect(sections.length, 2);
      expect(sections.first.params.map(_key).toList(), ['a:x', 'a:z']);
    });

    test('摊平回一条列表', () {
      final sections = buildParamSections([
        _n('a', 'x'),
        _n('b', 'y'),
        _n('a', 'z'),
      ]);
      expect(
        flattenSections(sections).map(_key).toList(),
        ['a:x', 'a:z', 'b:y'],
      );
    });
  });

  group('段顺序写回（槽位回写）', () {
    test('未暴露的参数原地不动', () {
      final all = [
        _n('a', 'x'),
        _n('b', 'y', exposed: false),
        _n('c', 'z'),
        _n('d', 'w', exposed: false),
      ];
      // 把 c 那一段挪到最前
      final ordered = [_n('c', 'z'), _n('a', 'x')];
      final out = withExposedOrder(all, ordered);

      expect(out.map(_key).toList(), ['c:z', 'b:y', 'a:x', 'd:w']);
      // 未暴露的两项仍在 1、3 号位，且仍是未暴露
      expect(out[1].exposed, false);
      expect(out[3].exposed, false);
    });

    test('只回写已选项占据的槽位，不新增也不删除', () {
      final all = [_n('a', '1'), _n('b', '2'), _n('c', '3')];
      final ordered = [_n('c', '3'), _n('b', '2'), _n('a', '1')];
      final out = withExposedOrder(all, ordered);
      expect(out.length, 3);
      expect(out.map(_key).toList(), ['c:3', 'b:2', 'a:1']);
    });
  });

  group('合并旧配置时保住段顺序', () {
    test('旧配置是 B、A，新解析是 A、B —— 结果仍是 B、A', () {
      final saved = [_n('B', 'b1'), _n('A', 'a1'), _n('A', 'a2')];
      final parsed = [_n('A', 'a1'), _n('A', 'a2'), _n('B', 'b1')];
      expect(_nodeOrder(orderLikeSavedConfig(parsed, saved)), ['B', 'A']);
    });

    test('旧配置为空时保持解析顺序', () {
      final parsed = [_n('A', 'a1'), _n('B', 'b1')];
      expect(_nodeOrder(orderLikeSavedConfig(parsed, <WorkflowNode>[])), [
        'A',
        'B',
      ]);
    });

    test('服务器新增的节点排到末尾', () {
      final saved = [_n('A', 'a1'), _n('B', 'b1')];
      final parsed = [_n('C', 'c1'), _n('A', 'a1'), _n('B', 'b1')];
      expect(_nodeOrder(orderLikeSavedConfig(parsed, saved)), ['A', 'B', 'C']);
    });

    test('节点内新增的参数插到自己节点块的末尾，而不是整表末尾', () {
      final saved = [_n('A', 'a1'), _n('B', 'b1')];
      final parsed = [_n('A', 'a1'), _n('A', 'a2'), _n('B', 'b1')];
      expect(
        orderLikeSavedConfig(parsed, saved).map(_key).toList(),
        ['A:a1', 'A:a2', 'B:b1'],
      );
    });

    test('未暴露的参数也跟着走（下次勾回来顺序不乱）', () {
      final saved = [
        _n('B', 'b1'),
        _n('A', 'a1'),
        _n('A', 'a2', exposed: false),
      ];
      final parsed = [_n('A', 'a1'), _n('A', 'a2'), _n('B', 'b1')];
      final out = orderLikeSavedConfig(parsed, saved);
      expect(_nodeOrder(out), ['B', 'A']);
      expect(out.map(_key).toList(), ['B:b1', 'A:a1', 'A:a2']);
    });
  });

  group('拖动整段（端到端链路）', () {
    test('把第 3 段拖到第 1 位，落盘顺序与运行页卡片顺序一致', () {
      final all = [
        _n('size', 'width'),
        _n('size', 'height'),
        _n('clip', 'text'),
        _n('refA', 'image'),
        _n('refB', 'image'),
      ];
      expect(_nodeOrder(all), ['size', 'clip', 'refA', 'refB']);

      // 模拟 onReorder(oldIndex: 2, newIndex: 0)
      final sections = List<ParamSection>.of(buildParamSections(all));
      final moved = sections.removeAt(2);
      sections.insert(0, moved);
      final next = withExposedOrder(all, flattenSections(sections));

      expect(_nodeOrder(next), ['refA', 'size', 'clip', 'refB']);
      // 未暴露项不动的保证在这里：整表都暴露，所以只验参数归属没散
      expect(
        buildParamSections(next).first.params.map(_key).toList(),
        ['refA:image'],
      );
    });

    test('连续两次移动后顺序累积正确', () {
      var all = [
        _n('a', '1'),
        _n('b', '1'),
        _n('c', '1'),
      ];
      List<ParamSection> move(int from, int to) {
        final s = List<ParamSection>.of(buildParamSections(all));
        final m = s.removeAt(from);
        s.insert(to, m);
        all = withExposedOrder(all, flattenSections(s));
        return buildParamSections(all);
      }

      move(2, 0); // c 到最前
      expect(_nodeOrder(all), ['c', 'a', 'b']);
      move(2, 1); // b 挪到中间
      expect(_nodeOrder(all), ['c', 'b', 'a']);
    });
  });
}
