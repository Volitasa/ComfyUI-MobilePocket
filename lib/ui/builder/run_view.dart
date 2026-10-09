import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import '../../models/workflow_node.dart';
import '../../providers/workflow_provider.dart';
import '../../providers/task_manager.dart';
import '../../providers/ws_event_provider.dart';
import '../../utils.dart';
import '../main_screen.dart';
import 'workflow_view.dart';

class RunView extends ConsumerStatefulWidget {
  final String workflowId;
  const RunView({super.key, required this.workflowId});

  @override
  ConsumerState<RunView> createState() => _RunViewState();
}

class _RunViewState extends ConsumerState<RunView> {
  List<WorkflowNode> _formConfig = [];
  final Map<String, dynamic> _formData = {};
  final Map<String, TextEditingController> _controllers = {};
  bool _isExecuting = false;

  @override
  void initState() {
    super.initState();
    _initForm();
  }

  void _initForm() {
    final savedConfig = ref.read(workflowProvider.notifier).getMappingConfig(widget.workflowId);
    if (savedConfig == null || savedConfig.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('未找到有效的表单配置')));
        Navigator.pop(context);
      });
      return;
    }

    _formConfig = savedConfig.where((node) => node.exposed).toList();
    for (var node in _formConfig) {
      if (node.key == 'seed' || node.key == 'noise_seed') {
        _generateSeed(node.id);
      } else if (node.key == 'text' || node.key == 'value') {
        _controllers[node.id] = TextEditingController();
      }
    }
  }

  @override
  void dispose() {
    for (var controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _generateSeed(String nodeId) {
    // 定长生成：高 10 位 + 低 5 位，固定 15 位，避免 substring(0,15) 越界崩溃
    final high = Random().nextInt(1000000000) + 1000000000; // 10 位（1e9 ~ 2e9）
    final low = Random().nextInt(100000); // 0 ~ 99999
    final seed = high * 100000 + low;
    setState(() {
      _formData[nodeId] = seed;
      final controller = _controllers.putIfAbsent(nodeId, () => TextEditingController());
      controller.text = seed.toString();
    });
  }

  Future<void> _pickImage(String nodeId) async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (result != null && result.files.single.bytes != null) {
      setState(() {
        _formData[nodeId] = {
          'bytes': result.files.single.bytes!,
          'filename': result.files.single.name,
        };
      });
    }
  }

  Future<void> _handleExecute() async {
    final workflowData = ref.read(workflowProvider).currentWorkflowData;
    if (workflowData == null) return;

    setState(() => _isExecuting = true);
    ref.read(wsProvider.notifier).connect();

    try {
      // 深拷贝一份原始工作流，防止污染内存
      Map<String, dynamic> originalJson = jsonDecode(jsonEncode(workflowData));
      // 与解析侧保持一致：统一归一化后再解包节点结构
      Map<String, dynamic> promptNodes = normalizeWorkflowJson(originalJson);

      final taskManager = ref.read(taskManagerProvider.notifier);

      for (var node in _formConfig) {
        dynamic value;

        if (node.key == 'image' && _formData[node.id] != null) {
          final imgData = _formData[node.id];
          final uploadedName = await taskManager.uploadImage(imgData['bytes'], imgData['filename']);
          if (uploadedName == null) throw Exception('图片上传失败');
          value = uploadedName;
        } else if (node.key == 'seed' || node.key == 'noise_seed') {
          value = int.tryParse(_controllers[node.id]?.text ?? '0');
        } else {
          value = _controllers[node.id]?.text;
        }

        if (value != null && value != '') {
          if (promptNodes[node.id] != null && promptNodes[node.id]['inputs'] != null) {
            promptNodes[node.id]['inputs'][node.key] = value;
          }
        }
      }

      final result = await taskManager.executeWorkflow(promptNodes);

      if (result == null) {
        throw Exception('提交失败：无法连接服务器或请求超时');
      }
      if (result.containsKey('prompt_id')) {
        taskManager.createNewTask(result['prompt_id'], widget.workflowId);

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('任务下发成功！')));
        Navigator.pop(context);
        ref.read(mainTabIndexProvider.notifier).state = 1;
      } else {
        // 服务端返回非 200：透出具体错误（node_errors 等），而非笼统提示
        final code = result['_http_error'];
        final body = result['_body'];
        String detail = '';
        if (body is Map && body['node_errors'] != null) {
          final errors = body['node_errors'];
          detail = errors is Map && errors.isNotEmpty
              ? '，错误节点: ${errors.keys.join(', ')}'
              : '';
        }
        throw Exception('提交失败 (HTTP $code)$detail，请检查 ComfyUI 日志');
      }
    } catch (e) {
      final msg = e.toString().replaceFirst('Exception: ', '');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      if (mounted) setState(() => _isExecuting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayName = workflowDisplayName(widget.workflowId);

    return Scaffold(
      appBar: AppBar(
        title: Text('运行: $displayName', style: const TextStyle(fontSize: 16)),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: '节点配置',
            // 跳转到节点配置面板（用 pushReplacement 替换当前页，
            // 与配置页「保存并进入运行页」的 pushReplacement 对称，避免栈内重复）
            onPressed: () => Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => WorkflowView(workflowId: widget.workflowId)),
            ),
          )
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _formConfig.length,
              itemBuilder: (context, index) {
                final node = _formConfig[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 16),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: Colors.grey.shade200),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(node.alias, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        const SizedBox(height: 12),
                        _buildInputControl(node),
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
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: _isExecuting ? Colors.grey : Colors.green,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _isExecuting ? null : _handleExecute,
                  icon: _isExecuting 
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.rocket_launch),
                  label: Text(_isExecuting ? '下发任务中...' : '立即生成', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputControl(WorkflowNode node) {
    if (node.key == 'text' || node.key == 'value') {
      return TextField(
        controller: _controllers[node.id],
        maxLines: 3,
        decoration: const InputDecoration(
          hintText: '请输入描述...',
          border: OutlineInputBorder(),
          isDense: true,
        ),
      );
    } else if (node.key == 'seed' || node.key == 'noise_seed') {
      return Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controllers[node.id],
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton.icon(
            onPressed: () => _generateSeed(node.id),
            icon: const Icon(Icons.casino, size: 18),
            label: const Text('随机'),
          )
        ],
      );
    } else if (node.key == 'image') {
      final hasImage = _formData[node.id] != null;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          OutlinedButton.icon(
            onPressed: () => _pickImage(node.id),
            icon: const Icon(Icons.image),
            label: Text(hasImage ? '更换图片' : '选择图片'),
          ),
          if (hasImage) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(
                _formData[node.id]['bytes'],
                height: 100,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
          ]
        ],
      );
    }
    return const SizedBox.shrink();
  }
}