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

    jsonMap.forEach((nodeId, nodeData) {
      if (nodeData is! Map) return;

      final classType = nodeData['class_type'] as String?;
      final inputs = nodeData['inputs'] as Map<String, dynamic>?;
      final meta = nodeData['_meta'] as Map<String, dynamic>?;

      if (classType == null || inputs == null) return;

      final title = meta?['title'] as String? ?? 'Node $nodeId';

      // 1. 提取采样器的随机种子
      if (classType == 'KSampler') {
        if (inputs.containsKey('seed') && inputs['seed'] is! List) {
          nodes.add(WorkflowNode(id: nodeId, classType: classType, key: 'seed', alias: title, exposed: true));
        }
      } else if (classType == 'KSamplerAdvanced') {
        // KSamplerAdvanced 的种子键是 noise_seed，而非 seed
        if (inputs.containsKey('noise_seed') && inputs['noise_seed'] is! List) {
          nodes.add(WorkflowNode(id: nodeId, classType: classType, key: 'noise_seed', alias: title, exposed: true));
        }
      }
      // 2. 提取原生 CLIP 文本
      else if (classType == 'CLIPTextEncode') {
        if (inputs.containsKey('text') && inputs['text'] is String) {
          nodes.add(WorkflowNode(id: nodeId, classType: classType, key: 'text', alias: title, exposed: true));
        }
      }
      // 3. 提取主流自定义文本节点
      else if (classType == 'PrimitiveNode') {
        if (inputs.containsKey('text') && inputs['text'] is String) {
          nodes.add(WorkflowNode(id: nodeId, classType: classType, key: 'text', alias: title, exposed: true));
        } else if (inputs.containsKey('value') && inputs['value'] is String) {
          nodes.add(WorkflowNode(id: nodeId, classType: classType, key: 'value', alias: title, exposed: true));
        }
      }
      // 4. 提取图片上传节点
      else if (classType == 'LoadImage') {
        if (inputs.containsKey('image') && inputs['image'] is String) {
          nodes.add(WorkflowNode(id: nodeId, classType: classType, key: 'image', alias: title, exposed: true));
        }
      }
    });

    // 优先使用历史保存的配置
    final savedConfig = ref.read(workflowProvider.notifier).getMappingConfig(widget.workflowId);
    if (savedConfig != null && savedConfig.isNotEmpty) {
      _extractableNodes = savedConfig;
    } else {
      _extractableNodes = nodes;
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
                      child: Text('此工作流没有找到支持动态修改的节点（缺少提示词、图片加载或采样器）。', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
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
                                  '[${node.classType}] Node: ${node.id}',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
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
                                  child: Text('参数: ${node.key}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
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