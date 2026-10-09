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
  // 枚举下拉、开关、滑块的当前选中值
  final Map<String, dynamic> _widgetValues = {};
  bool _isExecuting = false;
  // 节点分组的展开/收起状态
  final Set<String> _expandedNodeIds = {};
  final Set<String> _collapsedNodeIds = {};

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
      // 同一节点可有多个参数，控制器/状态统一用 id:key 复合键，避免串台
      final k = nodeParamKey(node.id, node.key);
      switch (node.paramType) {
        case ParamType.seed:
          // 有初值则用初值，否则随机
          if (node.value is int) {
            _setSeedValue(k, node.value as int);
          } else {
            _generateSeed(k);
          }
          break;
        case ParamType.text:
          _controllers[k] = TextEditingController(text: node.value?.toString() ?? '');
          break;
        case ParamType.intType:
          _controllers[k] = TextEditingController(text: _numToString(node.value));
          break;
        case ParamType.float:
          _controllers[k] = TextEditingController(text: _numToString(node.value));
          break;
        case ParamType.boolType:
          _widgetValues[k] = node.value ?? false;
          break;
        case ParamType.enumType:
          // 下拉当前值：取 value，若为空则取 options 第一项
          final opts = node.options;
          final current = node.value?.toString();
          _widgetValues[k] = (current != null && opts.contains(current))
              ? current
              : (opts.isNotEmpty ? opts.first : (current ?? ''));
          break;
        case ParamType.image:
          // 图片初值为服务器上已有的文件名，仅作展示，不预载图片
          if (node.value is String && (node.value as String).isNotEmpty) {
            _widgetValues[k] = node.value;
          }
          break;
      }
    }

    // 确保工作流数据已加载：从首页直接进入运行页时，
    // currentWorkflowData 可能为空（冷启动未拉取 / 切换连接被清空），
    // 提交任务依赖它，这里主动补拉，否则「立即生成」会静默无反应
    if (!widget.workflowId.startsWith('local_')) {
      _ensureWorkflowData();
    }
  }

  Future<void> _ensureWorkflowData() async {
    final state = ref.read(workflowProvider);
    if (state.currentWorkflowData != null) return;
    await ref.read(workflowProvider.notifier).fetchWorkflowContent(widget.workflowId);
  }

  String _numToString(dynamic v) {
    if (v == null) return '';
    if (v is int) return v.toString();
    if (v is double) {
      // 去掉多余的小数尾零
      return v == v.roundToDouble() ? v.toInt().toString() : v.toString();
    }
    return v.toString();
  }

  void _setSeedValue(String nodeId, int seed) {
    setState(() {
      _formData[nodeId] = seed;
      final controller = _controllers.putIfAbsent(nodeId, () => TextEditingController());
      controller.text = seed.toString();
    });
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
    _setSeedValue(nodeId, seed);
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

  // 根据参数类型，把控件里的值解析成正确的 Dart 类型后提交
  dynamic _resolveValue(WorkflowNode node) {
    final k = nodeParamKey(node.id, node.key);
    switch (node.paramType) {
      case ParamType.seed:
        return int.tryParse(_controllers[k]?.text ?? '') ?? 0;
      case ParamType.intType:
        return int.tryParse(_controllers[k]?.text ?? '');
      case ParamType.float:
        return double.tryParse(_controllers[k]?.text ?? '');
      case ParamType.boolType:
        return _widgetValues[k] ?? false;
      case ParamType.enumType:
        return _widgetValues[k];
      case ParamType.text:
      case ParamType.image:
        return _controllers[k]?.text;
    }
  }

  Future<void> _handleExecute() async {
    final workflowData = ref.read(workflowProvider).currentWorkflowData;
    if (workflowData == null) {
      // 防御：正常已在 _ensureWorkflowData 预加载，这里兜底给明确提示而非静默
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('工作流数据未加载，请返回重试')));
      }
      return;
    }

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

        if (node.paramType == ParamType.image) {
          // 图片：只有用户重新选择了本地图片才上传；否则沿用工作流里的原值
          final picked = _formData[nodeParamKey(node.id, node.key)];
          if (picked != null) {
            final uploadedName = await taskManager.uploadImage(picked['bytes'], picked['filename']);
            if (uploadedName == null) throw Exception('图片上传失败');
            value = uploadedName;
          } else {
            // 未重新选择，保持工作流原有图片文件名不变
            continue;
          }
        } else {
          value = _resolveValue(node);
        }

        if (value == null || value == '') continue;

        if (promptNodes[node.id] != null && promptNodes[node.id]['inputs'] != null) {
          promptNodes[node.id]['inputs'][node.key] = value;
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
        ref.read(mainTabIndexProvider.notifier).state = MainTabs.history;
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
            child: Builder(builder: (context) {
              // 按节点分组展示：同一节点的多个参数合并为一张卡片，支持展开/折叠
              final groups = <String, List<WorkflowNode>>{};
              for (final n in _formConfig) {
                groups.putIfAbsent(n.id, () => []).add(n);
              }
              final groupIds = groups.keys.toList();
              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: groupIds.length,
                itemBuilder: (context, index) {
                  final nodeId = groupIds[index];
                  final params = groups[nodeId]!;
                  final expanded = _expandedNodeIds.contains(nodeId)
                      ? true
                      : _collapsedNodeIds.contains(nodeId)
                          ? false
                          : true; // 运行页默认全部展开

                  return Card(
                    margin: const EdgeInsets.only(bottom: 16),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: Colors.grey.shade200),
                    ),
                    child: Column(
                      children: [
                        InkWell(
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
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
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                                    _groupLabel(params),
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Text(
                                  '${params.length} 项参数',
                                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (expanded)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                            child: Column(
                              children: [
                                const Divider(height: 1),
                                ...params.map((node) => Padding(
                                      padding: const EdgeInsets.only(top: 16),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Text(node.alias, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
                                              ),
                                              if (node.key != 'text' && node.key != 'value')
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: Colors.grey.shade100,
                                                    borderRadius: BorderRadius.circular(4),
                                                  ),
                                                  child: Text(
                                                    node.key,
                                                    style: const TextStyle(fontSize: 10, color: Colors.grey),
                                                  ),
                                                ),
                                            ],
                                          ),
                                          const SizedBox(height: 10),
                                          _buildInputControl(node),
                                        ],
                                      ),
                                    )),
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

  // 分组卡片头部标签：优先节点标题，无有效标题回退类名
  String _groupLabel(List<WorkflowNode> params) {
    final classType = params.first.classType;
    final title = params.first.title;
    if (isMeaningfulTitle(title, classType)) return title;
    return classType;
  }

  Widget _buildInputControl(WorkflowNode node) {
    // 同一节点可有多个参数，控制器/状态统一用 id:key 复合键
    final k = nodeParamKey(node.id, node.key);
    switch (node.paramType) {
      case ParamType.text:
        return TextField(
          controller: _controllers[k],
          maxLines: 3,
          minLines: 3,
          decoration: InputDecoration(
            hintText: '请输入描述...',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            isDense: true,
            filled: true,
            fillColor: Colors.white,
          ),
        );
      case ParamType.seed:
        return Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controllers[k],
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  isDense: true,
                  filled: true,
                  fillColor: Colors.white,
                ),
              ),
            ),
            const SizedBox(width: 12),
            ElevatedButton.icon(
              onPressed: () => _generateSeed(k),
              icon: const Icon(Icons.casino, size: 18),
              label: const Text('随机'),
            )
          ],
        );
      case ParamType.intType:
        return TextField(
          controller: _controllers[k],
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            hintText: '整数',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            isDense: true,
            filled: true,
            fillColor: Colors.white,
          ),
        );
      case ParamType.float:
        return TextField(
          controller: _controllers[k],
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            hintText: '数值（可小数）',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            isDense: true,
            filled: true,
            fillColor: Colors.white,
          ),
        );
      case ParamType.boolType:
        return SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(
            (_widgetValues[k] == true) ? '开启' : '关闭',
            style: const TextStyle(fontSize: 14),
          ),
          value: _widgetValues[k] == true,
          onChanged: (val) => setState(() => _widgetValues[k] = val),
        );
      case ParamType.enumType:
        final opts = node.options;
        final current = _widgetValues[k]?.toString() ?? '';
        // 若当前值不在选项里（理论上不会），仍显示它
        final items = opts.contains(current) ? opts : [...opts, if (current.isNotEmpty) current];
        return DropdownButtonFormField<String>(
          initialValue: items.contains(current) ? current : (items.isNotEmpty ? items.first : null),
          isExpanded: true,
          decoration: InputDecoration(
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            isDense: true,
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          ),
          items: items.map((o) => DropdownMenuItem(value: o, child: Text(o, overflow: TextOverflow.ellipsis))).toList(),
          onChanged: (val) {
            if (val != null) setState(() => _widgetValues[k] = val);
          },
        );
      case ParamType.image:
        final hasImage = _formData[k] != null;
        final serverImage = _widgetValues[k] as String?;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (serverImage != null && !hasImage) ...[
              Row(
                children: [
                  const Icon(Icons.image_outlined, size: 16, color: Colors.grey),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '已用图: $serverImage',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            OutlinedButton.icon(
              onPressed: () => _pickImage(k),
              icon: const Icon(Icons.image),
              label: Text(hasImage ? '更换图片' : '选择图片'),
            ),
            if (hasImage) ...[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(
                  _formData[k]['bytes'],
                  height: 100,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
            ]
          ],
        );
    }
  }
}