import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:comfyui_mobilepocket/services/workflow_api_converter.dart';

void main() {
  group('就绪探测', () {
    test('脚本同时看 app 实例与启动遮罩', () {
      final script = WorkflowApiConverter.readinessProbeScript();

      // 只有实例不够：模块求值阶段就挂上去了，那时节点定义还没注册完
      expect(script, contains('window.comfyAPI'));
      expect(script, contains('splash-loader'));
    });

    test('识别前端返回的三种状态', () {
      expect(WorkflowApiConverter.parseReadiness('ready'),
          FrontendReadiness.ready);
      expect(WorkflowApiConverter.parseReadiness('loading'),
          FrontendReadiness.loading);
      expect(WorkflowApiConverter.parseReadiness('no-app'),
          FrontendReadiness.missing);
    });

    test('不同平台回传的字符串可能带多余引号，也能识别', () {
      expect(WorkflowApiConverter.parseReadiness('"ready"'),
          FrontendReadiness.ready);
      expect(WorkflowApiConverter.parseReadiness(' ready '),
          FrontendReadiness.ready);
    });

    test('无法识别的值不猜', () {
      expect(WorkflowApiConverter.parseReadiness(''),
          FrontendReadiness.unknown);
      expect(WorkflowApiConverter.parseReadiness(null),
          FrontendReadiness.unknown);
    });
  });

  group('转换脚本', () {
    final uiJson = jsonEncode({
      'version': 0.4,
      'nodes': [
        {'id': 3, 'type': 'KSampler'}
      ],
      'links': [],
    });

    test('走前端自己的 loadGraphData + graphToPrompt', () {
      final script = WorkflowApiConverter.conversionScript(uiJson);

      expect(script, contains('loadGraphData'));
      expect(script, contains('graphToPrompt'));
      expect(script, contains(WorkflowApiConverter.bridgeName));
    });

    test('restore 传 false，避免去重绘画布', () {
      // loadGraphData(g, false, true)：第二个参数非 false 会重设画布并 clean()
      expect(WorkflowApiConverter.conversionScript(uiJson),
          contains('loadGraphData(g,false,true)'));
    });

    test('结果取 workflow 字段回传', () {
      // graphToPrompt 返回 {workflow, output}，我们要的是前者
      expect(WorkflowApiConverter.conversionScript(uiJson),
          contains('workflow:r.workflow'));
    });

    test('单引号会被转义，否则整个脚本语法错误', () {
      final tricky = jsonEncode({'text': "it's fine"});
      final script = WorkflowApiConverter.conversionScript(tricky);

      expect(script, contains("it\\'s fine"));
    });

    test('U+2028 / U+2029 必须转义（JSON 里合法，JS 字面量里是换行）', () {
      final tricky = jsonEncode({
        'text':
            'a${String.fromCharCode(0x2028)}b${String.fromCharCode(0x2029)}c',
      });
      final script = WorkflowApiConverter.conversionScript(tricky);

      // 这两个字符留在脚本里会直接破坏 JS 语法，必须转成转义序列
      expect(script, contains('\\u2028'));
      expect(script, contains('\\u2029'));
    });

    test('异常收敛成可读的失败原因，不让脏数据冒泡', () {
      final script = WorkflowApiConverter.conversionScript(uiJson);

      // try/catch 包住同步段，Promise 也得挂 catch
      expect(script, contains('try{'));
      expect(script, contains('.catch('));
    });
  });

  group('回传结果解析', () {
    test('成功时取出工作流结构', () {
      final result = WorkflowApiConverter.parsePayload(
        jsonEncode({
          'ok': true,
          'workflow': {
            '3': {'class_type': 'KSampler', 'inputs': {}},
          },
        }),
      );

      expect(result.ok, isTrue);
      expect(result.workflow!['3']['class_type'], 'KSampler');
    });

    test('前端报错时透出原因', () {
      final result = WorkflowApiConverter.parsePayload(
        jsonEncode({'ok': false, 'error': 'Unknown node type'}),
      );

      expect(result.ok, isFalse);
      expect(result.error, 'Unknown node type');
    });

    test('成功但没有 workflow 时不算成功', () {
      final result =
          WorkflowApiConverter.parsePayload(jsonEncode({'ok': true}));

      expect(result.ok, isFalse);
      expect(result.error, '前端未返回工作流结构');
    });

    test('拿不到句柄时提示清楚，而不是笼统的「解析失败」', () {
      final result = WorkflowApiConverter.parsePayload(
        jsonEncode({'ok': false, 'error': 'no-app'}),
      );

      expect(result.ok, isFalse);
      expect(result.error, 'no-app');
    });

    test('脏数据不会抛异常', () {
      expect(WorkflowApiConverter.parsePayload('not json').ok, isFalse);
      expect(WorkflowApiConverter.parsePayload('[]').ok, isFalse);
      expect(WorkflowApiConverter.parsePayload('').ok, isFalse);
    });
  });

  group('源文件指纹', () {
    test('内容不变则哈希不变', () {
      const text = '{"nodes":[]}';

      expect(WorkflowApiConverter.sourceHashOf(text),
          WorkflowApiConverter.sourceHashOf(text));
    });

    test('内容变了哈希跟着变', () {
      expect(WorkflowApiConverter.sourceHashOf('{"nodes":[]}'),
          isNot(WorkflowApiConverter.sourceHashOf('{"nodes":[1]}')));
    });
  });
}
