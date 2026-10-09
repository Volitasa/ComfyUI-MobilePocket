import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import '../../providers/connection_provider.dart';
import '../../providers/workflow_provider.dart';
import '../../utils.dart';
import '../builder/workflow_view.dart';
import '../builder/run_view.dart';
import '../widgets/connection_status_badge.dart';
import '../main_screen.dart';

class HomeView extends ConsumerStatefulWidget {
  const HomeView({super.key});

  @override
  ConsumerState<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends ConsumerState<HomeView> {
  @override
  void initState() {
    super.initState();
    // 页面加载时：先静默探测已保存地址自动连接，成功后拉取远端列表
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(connectionProvider.notifier).autoConnect().then((_) {
        if (!mounted) return;
        if (ref.read(connectionProvider).isConnected) {
          ref.read(workflowProvider.notifier).fetchRemoteList();
        }
      });
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

        // 以内容哈希作为本地工作流 ID，避免多个本地文件共用 'local' 导致配置串台
        final localId = 'local_${stableHash(jsonString).toRadixString(36)}';
        if (!mounted) return;
        await Navigator.push(context, MaterialPageRoute(builder: (_) => WorkflowView(workflowId: localId)));
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('本地导入成功，即将跳转...')));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('JSON 文件解析失败')));
    }
  }

  void _onCardTap(String filename) {
    // 已配置过的工作流直接进入运行页；未配置的先进配置面板
    final hasConfig = ref.read(workflowProvider.notifier).hasMappingConfig(filename);
    final Widget page = hasConfig
        ? RunView(workflowId: filename)
        : WorkflowView(workflowId: filename);
    Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    final configState = ref.watch(connectionProvider);
    final workflowState = ref.watch(workflowProvider);

    // 监听连接状态：在设置页完成连接（isConnected 由 false→true）时，
    // 自动拉取一次工作流列表，免去手动点刷新
    ref.listen(connectionProvider, (prev, next) {
      if (next.isConnected && !(prev?.isConnected ?? false)) {
        ref.read(workflowProvider.notifier).fetchRemoteList();
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('工作流', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          if (configState.isConnected)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: '刷新工作流列表',
              onPressed: () => ref.read(workflowProvider.notifier).fetchRemoteList(),
            ),
          ConnectionStatusBadge(
            onTap: () => ref.read(mainTabIndexProvider.notifier).state = MainTabs.setup,
          ),
          const SizedBox(width: 8),
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
            Icon(Icons.cloud_off, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            const Text('尚未连接到服务器', style: TextStyle(color: Colors.black54, fontSize: 16)),
            const SizedBox(height: 4),
            const Text('请先配置并启用一个服务器连接', style: TextStyle(color: Colors.grey, fontSize: 12)),
            const SizedBox(height: 20),
            FilledButton.icon(
              icon: const Icon(Icons.settings),
              onPressed: () {
                // 直接通过 Provider 将底部导航栏硬切到“服务器配置”页 (索引为 2)
                ref.read(mainTabIndexProvider.notifier).state = MainTabs.setup;
              },
              label: const Text('前往配置'),
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
          Padding(
            padding: const EdgeInsets.all(40.0),
            child: Column(
              children: [
                Icon(Icons.inbox_outlined, size: 48, color: Colors.grey.shade400),
                const SizedBox(height: 12),
                const Text(
                  '未找到工作流',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.black54, fontSize: 16),
                ),
                const SizedBox(height: 4),
                const Text(
                  '服务器上没有找到 _api.json 后缀的工作流',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
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