import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import '../../providers/connection_provider.dart';
import '../../providers/workflow_provider.dart';
import '../builder/workflow_view.dart'; 

class HomeView extends ConsumerStatefulWidget {
  const HomeView({super.key});

  @override
  ConsumerState<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends ConsumerState<HomeView> {
  @override
  void initState() {
    super.initState();
    // 页面加载时，如果已连接则自动拉取
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (ref.read(connectionProvider).isConnected) {
        ref.read(workflowProvider.notifier).fetchRemoteList();
      }
    });
  }

  Future<void> _importLocalJson() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: true, // 确保能直接读取到字节数据
      );

      if (result != null && result.files.single.bytes != null) {
        final jsonString = utf8.decode(result.files.single.bytes!);
        final Map<String, dynamic> data = jsonDecode(jsonString);
        
        ref.read(workflowProvider.notifier).setLocalWorkflowData(data);
        
        // 带着 'local' 标识跳转到配置装配页
        Navigator.push(context, MaterialPageRoute(builder: (_) => const WorkflowView(workflowId: 'local')));
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('本地导入成功，即将跳转...')));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('JSON 文件解析失败')));
    }
  }

  void _onCardTap(String filename) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => WorkflowView(workflowId: filename)));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('点击了: $filename')));
  }

  @override
  Widget build(BuildContext context) {
    final configState = ref.watch(connectionProvider);
    final workflowState = ref.watch(workflowProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('我的功能卡片', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          if (configState.isConnected)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () => ref.read(workflowProvider.notifier).fetchRemoteList(),
            ),
        ],
      ),
      body: _buildBody(configState, workflowState),
    );
  }

  Widget _buildBody(ConfigState configState, WorkflowState workflowState) {
    if (!configState.isConnected) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('尚未连接到服务器', style: TextStyle(color: Colors.black54)),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () {
                // 暂时用弹窗提示，之后整合 BottomNavigationBar 可直接切 Tab
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请切换到底部[设置]进行连接')));
              },
              child: const Text('前往设置'),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (workflowState.isLoading)
          const Padding(
            padding: EdgeInsets.all(40.0),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (workflowState.workflowList.isEmpty)
          const Padding(
            padding: EdgeInsets.all(40.0),
            child: Text('未在服务器找到带有 _api.json 后缀的工作流。', textAlign: TextAlign.center, style: TextStyle(color: Colors.black54)),
          )
        else
          ...workflowState.workflowList.map((file) => _buildWorkflowCard(file)),

        const SizedBox(height: 40),
        const Row(
          children: [
            Expanded(child: Divider()),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 10),
              child: Text('或者', style: TextStyle(color: Colors.grey, fontSize: 12)),
            ),
            Expanded(child: Divider()),
          ],
        ),
        const SizedBox(height: 20),
        OutlinedButton.icon(
          onPressed: _importLocalJson,
          icon: const Icon(Icons.upload_file),
          label: const Text('导入本地 _api.json'),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            side: const BorderSide(color: Colors.grey),
            foregroundColor: Colors.black87,
          ),
        ),
      ],
    );
  }

  Widget _buildWorkflowCard(String filename) {
    final title = filename.replaceAll('_api.json', '');
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: InkWell(
        onTap: () => _onCardTap(filename),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
              ),
              const SizedBox(height: 4),
              const Text(
                'API 模板',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ),
      ),
    );
  }
}