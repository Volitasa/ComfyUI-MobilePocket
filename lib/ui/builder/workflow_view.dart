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
  // 节点分组的展开/收起状态（用户手动切换）
  final Set<String> _expandedNodeIds = {};
  final Set<String> _collapsedNodeIds = {};

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

  void _parseWorkflow(Map<String, dynamic> jsonMap, {bool useSavedConfig = true}) {
    final List<WorkflowNode> nodes = [];

    // 白名单节点类型：在这些节点内做全参数类型识别
    const whitelist = {
      'KSampler',
      'KSamplerAdvanced',
      'CLIPTextEncode',
      'LoadImage',
      'PrimitiveNode',
      // 主流第三方文本节点（保留兼容，避免已有工作流反向失去支持）
      'Text Multiline',
      'Text box',
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

      final title = meta?['title'] as String? ?? 'Node $nodeId';
      final inWhitelist = whitelist.contains(classType);

      // 兜底规则：任何节点的 text/value 参数若为字符串，都识别为文本节点。
      // 第三方文本节点类名五花八门，靠类名白名单会漏，靠参数名兜底可全兼容。
      final isTextNodeFallback = !inWhitelist &&
          ((inputs['text'] is String) || (inputs['value'] is String));

      if (!inWhitelist && !isTextNodeFallback) return;

      inputs.forEach((key, rawValue) {
        if (isLinkReference(rawValue)) return; // 连线引用不暴露

        // 非白名单节点只暴露 text/value 兜底参数
        if (!inWhitelist && key != 'text' && key != 'value') return;

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
        var type = inferParamType(key, rawValue);
        if (type == null) return;

        // 已知枚举参数名（sampler_name/scheduler/ckpt_name 等）：
        // JSON 里是字符串，但语义是下拉选项，选项暂取当前值
        if (type == ParamType.text && knownEnumParams.contains(key)) {
          type = ParamType.enumType;
        }

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

    // 默认优先使用历史保存的配置；重新解析时跳过历史配置，用最新解析结果
    if (useSavedConfig) {
      final savedConfig = ref.read(workflowProvider.notifier).getMappingConfig(widget.workflowId);
      if (savedConfig != null && savedConfig.isNotEmpty) {
        _extractableNodes = savedConfig;
        return;
      }
    }
    _extractableNodes = nodes;
  }

  // 重新解析：放弃已保存的映射，用工作流当前结构重新提取参数。
  // 用于服务器端工作流更新后，让 App 重新识别新参数。
  Future<void> _reparse() async {
    final state = ref.read(workflowProvider);
    final data = state.currentWorkflowData;
    if (data == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('无可用工作流数据，无法重新解析')));
      return;
    }

    setState(() {
      _extractableNodes = [];
      _isReady = false;
    });

    // 本地导入的工作流数据已在 currentWorkflowData 中，直接重新解析；
    // 线上工作流则先重新拉取最新内容再解析
    if (widget.workflowId.startsWith('local_')) {
      _parseWorkflow(data, useSavedConfig: false);
    } else {
      final ok = await ref.read(workflowProvider.notifier).fetchWorkflowContent(widget.workflowId);
      if (!ok) {
        if (!mounted) return;
        setState(() => _isReady = true);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('重新拉取工作流失败，请检查服务器连接')));
        return;
      }
      _parseWorkflow(ref.read(workflowProvider).currentWorkflowData!, useSavedConfig: false);
    }

    if (!mounted) return;
    // 清掉旧的别名控制器，避免与新解析出的节点错位
    for (final c in _aliasControllers.values) {
      c.dispose();
    }
    _aliasControllers.clear();
    setState(() => _isReady = true);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已重新解析，请确认参数后保存')));
  }

  // 配置面板里单个参数行：勾选 + 别名编辑 + 类型/当前值摘要
  Widget _buildParamRow(WorkflowNode node) {
    final controllerKey = nodeParamKey(node.id, node.key);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            title: Text(
              node.alias,
              style: const TextStyle(fontSize: 14),
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
          if (node.exposed)
            Padding(
              padding: const EdgeInsets.only(left: 40.0),
              child: TextField(
                controller: _aliasControllers.putIfAbsent(
                    controllerKey, () => TextEditingController(text: node.alias)),
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
        ],
      ),
    );
  }

  // 配置面板里参数卡片的一行摘要：类型 + 当前值
  String _describeParam(WorkflowNode node) {    final typeName = {
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
  String _defaultAlias(String key, String title) {
    const map = {
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
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '重新解析参数',
            onPressed: _reparse,
          ),
        ],
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
                : Builder(builder: (context) {
                    // 按节点分组展示：同一节点的多个参数合并为一张卡片
                    final groups = <String, List<WorkflowNode>>{};
                    for (final n in _extractableNodes) {
                      groups.putIfAbsent(n.id, () => []).add(n);
                    }
                    final groupIds = groups.keys.toList();
                    return ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      itemCount: groupIds.length,
                      itemBuilder: (context, index) {
                        final nodeId = groupIds[index];
                        final params = groups[nodeId]!;
                        final classType = params.first.classType;
                        final exposedCount = params.where((p) => p.exposed).length;

                        // 默认展开含已勾选参数的节点，其余收起；用户可手动切换
                        final expanded = _expandedNodeIds.contains(nodeId)
                            ? true
                            : _collapsedNodeIds.contains(nodeId)
                                ? false
                                : exposedCount > 0;

                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                            side: BorderSide(color: Colors.grey.shade300),
                          ),
                          child: Column(
                            children: [
                              // 节点分组头部：类名 + 参数统计 + 展开/收起
                              InkWell(
                                borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                                onTap: () => setState(() {
                                  if (expanded) {
                                    _collapsedNodeIds.add(nodeId);
                                    _expandedNodeIds.remove(nodeId);
                                  } else {
                                    _expandedNodeIds.add(nodeId);
                                    _collapsedNodeIds.remove(nodeId);
                                  }
                                }),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  child: Row(
                                    children: [
                                      AnimatedRotation(
                                        turns: expanded ? 0 : -0.25,
                                        duration: const Duration(milliseconds: 150),
                                        child: const Icon(Icons.expand_more, size: 20, color: Colors.grey),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          '[$classType] $nodeId',
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      Text(
                                        exposedCount > 0 ? '$exposedCount/${params.length} 项已选' : '${params.length} 项参数',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: exposedCount > 0 ? Colors.green.shade700 : Colors.grey,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              if (expanded)
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                                  child: Column(
                                    children: [
                                      const Divider(height: 1),
                                      ...params.map((node) => _buildParamRow(node)),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    );
                  }),
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