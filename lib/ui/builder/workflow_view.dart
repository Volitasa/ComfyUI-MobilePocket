import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/workflow_node.dart';
import '../../providers/workflow_provider.dart';
import '../../utils.dart';
import 'run_view.dart'; // 下一步我们将创建运行页面

class WorkflowView extends ConsumerStatefulWidget {
  final String workflowId;

  const WorkflowView({super.key, required this.workflowId});

  @override
  ConsumerState<WorkflowView> createState() => _WorkflowViewState();
}

class _WorkflowViewState extends ConsumerState<WorkflowView> {
  bool _isReady = false;
  List<WorkflowNode> _extractableNodes = [];
  // 别名输入框控制器统一挂到 State 上，随页面销毁一并释放（避免 build 内新建导致泄漏）
  final Map<String, TextEditingController> _aliasControllers = {};

  @override
  void dispose() {
    for (final c in _aliasControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _initData();
  }

  Future<void> _initData() async {
    final notifier = ref.read(workflowProvider.notifier);
    final state = ref.read(workflowProvider);

    if (widget.workflowId.startsWith('local_')) {
      if (state.currentWorkflowData == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('本地数据已丢失，请重新选择文件')));
        Navigator.pop(context);
        return;
      }
      _parseWorkflow(state.currentWorkflowData!);
    } else {
      final success = await notifier.fetchWorkflowContent(widget.workflowId);
      if (!success) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('拉取线上工作流内容失败，请检查服务器连接')));
        Navigator.pop(context);
        return;
      }
      _parseWorkflow(ref.read(workflowProvider).currentWorkflowData!);
    }

    if (!mounted) return;
    setState(() {
      _isReady = true;
    });
  }

  void _parseWorkflow(Map<String, dynamic> jsonMap) {
    final List<WorkflowNode> nodes = [];

    // 白名单节点类型：仅在这些节点内做参数扩展，避免把连线引用等噪声暴露出来
    const whitelist = {
      'KSampler',
      'KSamplerAdvanced',
      'CLIPTextEncode',
      'LoadImage',
      'PrimitiveNode',
      'String Input',
      'Text Input',
      'CheckpointLoaderSimple',
    };

    jsonMap.forEach((nodeId, nodeData) {
      if (nodeData is! Map) return;

      final classType = nodeData['class_type'] as String?;
      final inputs = nodeData['inputs'] as Map<String, dynamic>?;
      final meta = nodeData['_meta'] as Map<String, dynamic>?;

      if (classType == null || inputs == null) return;
      if (!whitelist.contains(classType)) return;

      final title = meta?['title'] as String? ?? 'Node $nodeId';

      inputs.forEach((key, rawValue) {
        if (isLinkReference(rawValue)) return; // 连线引用不暴露

        // seed 是整数，需特殊识别为 seed 类型（带随机按钮）
        if ((key == 'seed' || key == 'noise_seed') && rawValue is! List) {
          nodes.add(WorkflowNode(
            id: nodeId,
            classType: classType,
            key: key,
            alias: _defaultAlias(key, title),
            exposed: true,
            paramType: ParamType.seed,
            value: rawValue is num ? rawValue.toInt() : rawValue,
          ));
          return;
        }

        // image 图片参数
        if (key == 'image' && rawValue is String) {
          nodes.add(WorkflowNode(
            id: nodeId,
            classType: classType,
            key: key,
            alias: _defaultAlias(key, title),
            exposed: true,
            paramType: ParamType.image,
            value: rawValue,
          ));
          return;
        }

        // 其余参数按值类型推断
        final type = inferParamType(key, rawValue);
        if (type == null) return;

        // 文本类型：优先显示为文本控件
        final effectiveType = (key == 'text' || key == 'value') && rawValue is String
            ? ParamType.text
            : type;

        final List<String> options = effectiveType == ParamType.enumType
            ? _enumOptions(rawValue)
            : const [];

        nodes.add(WorkflowNode(
          id: nodeId,
          classType: classType,
          key: key,
          alias: _defaultAlias(key, title),
          exposed: isDefaultExposed(key, classType),
          paramType: effectiveType,
          options: options,
          value: _normalizeValue(effectiveType, rawValue),
        ));
      });
    });

    // 优先使用历史保存的配置
    final savedConfig = ref.read(workflowProvider.notifier).getMappingConfig(widget.workflowId);
    if (savedConfig != null && savedConfig.isNotEmpty) {
      _extractableNodes = savedConfig;
    } else {
      _extractableNodes = nodes;
    }
  }

  // 配置面板里参数卡片的一行摘要：类型 + 当前值
  String _describeParam(WorkflowNode node) {
    final typeName = {
      ParamType.text: '文本',
      ParamType.seed: '种子',
      ParamType.image: '图片',
      ParamType.intType: '整数',
      ParamType.float: '小数',
      ParamType.boolType: '开关',
      ParamType.enumType: '选项',
    }[node.paramType] ?? '参数';

    final v = node.value;
    String valueStr = '';
    if (v != null) {
      valueStr = v.toString();
      if (valueStr.length > 20) valueStr = '${valueStr.substring(0, 20)}…';
    }
    return valueStr.isEmpty ? '类型: $typeName' : '类型: $typeName · 当前值: $valueStr';
  }

  // 给参数起一个可读的默认别名
  String _defaultAlias(String key, String title) {    const map = {
      'seed': '随机种子',
      'noise_seed': '随机种子',
      'text': '提示词',
      'value': '文本内容',
      'image': '参考图片',
      'steps': '采样步数',
      'cfg': 'CFG 强度',
      'sampler_name': '采样器',
      'scheduler': '调度器',
      'denoise': '重绘幅度',
      'width': '宽度',
      'height': '高度',
      'positive': '正向提示词',
      'negative': '负向提示词',
    };
    return map[key] ?? title;
  }

  // 枚举选项：当前只取工作流里的当前值作为唯一下拉项
  List<String> _enumOptions(dynamic value) {
    if (value is List) {
      return value.map((e) => e.toString()).toList();
    }
    if (value is String) return [value];
    if (value != null) return [value.toString()];
    return const [];
  }

  // 把值规整为可序列化、可回填的形态
  dynamic _normalizeValue(ParamType type, dynamic rawValue) {
    switch (type) {
      case ParamType.enumType:
        return rawValue is List ? (rawValue.isNotEmpty ? rawValue.first : null) : rawValue;
      default:
        return rawValue;
    }
  }

  void _handleSaveMapping() {
    ref.read(workflowProvider.notifier).saveMappingConfig(widget.workflowId, _extractableNodes);
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => RunView(workflowId: widget.workflowId)),
    );
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('配置已保存')));
  }

  @override
  Widget build(BuildContext context) {
    if (!_isReady) {
      return Scaffold(
        appBar: AppBar(title: const Text('解析中...')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final displayName = workflowDisplayName(widget.workflowId);

    return Scaffold(
      appBar: AppBar(
        title: Text('配置面板: $displayName', style: const TextStyle(fontSize: 16)),
      ),
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text(
              '请勾选需要暴露到手机 App 表单的参数，并为它们起一个易懂的名字。',
              style: TextStyle(color: Colors.black54, fontSize: 14),
            ),
          ),
          Expanded(
            child: _extractableNodes.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32.0),
                      child: Text('此工作流没有找到可动态修改的参数。', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    itemCount: _extractableNodes.length,
                    itemBuilder: (context, index) {
                      final node = _extractableNodes[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: BorderSide(color: Colors.grey.shade300),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              CheckboxListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(
                                  '[${node.classType}] ${node.alias}',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                ),
                                subtitle: Text(
                                  _describeParam(node),
                                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                                ),
                                value: node.exposed,
                                onChanged: (val) {
                                  setState(() {
                                    node.exposed = val ?? false;
                                  });
                                },
                                controlAffinity: ListTileControlAffinity.leading,
                                dense: true,
                              ),
                              if (node.exposed) ...[
                                Padding(
                                  padding: const EdgeInsets.only(left: 48.0, top: 8.0, bottom: 8.0),
                                  child: Text('参数名: ${node.key}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                ),
                                Padding(
                                  padding: const EdgeInsets.only(left: 48.0),
                                  child: TextField(
                                    controller: _aliasControllers.putIfAbsent(
                                        node.id, () => TextEditingController(text: node.alias)),
                                    onChanged: (val) => node.alias = val,
                                    decoration: const InputDecoration(
                                      isDense: true,
                                      hintText: '例如: 画面主体描述',
                                      border: OutlineInputBorder(),
                                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                    ),
                                    style: const TextStyle(fontSize: 14),
                                  ),
                                ),
                              ]
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: Colors.green,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: _handleSaveMapping,
                  child: const Text('保存表单配置', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}