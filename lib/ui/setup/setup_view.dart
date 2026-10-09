import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/connection_provider.dart';

class SetupView extends ConsumerStatefulWidget {
  const SetupView({super.key});

  @override
  ConsumerState<SetupView> createState() => _SetupViewState();
}

class _SetupViewState extends ConsumerState<SetupView> {
  late TextEditingController _urlController;

  @override
  void initState() {
    super.initState();
    // 初始化时回填本地保存的 URL
    final initialUrl = ref.read(connectionProvider).comfyUrl;
    _urlController = TextEditingController(text: initialUrl);
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 监听连接状态变化
    final configState = ref.watch(connectionProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('服务器配置', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '请输入您的 ComfyUI 服务地址（包含端口）。',
              style: TextStyle(color: Colors.black54, fontSize: 14),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _urlController,
              enabled: !configState.isTesting,
              decoration: InputDecoration(
                labelText: '服务地址',
                hintText: '例如: http://192.168.1.100:8190',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                filled: true,
                fillColor: Colors.white,
              ),
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 20),
            FilledButton(
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16.0),
                backgroundColor: Colors.green,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: configState.isTesting
                  ? null
                  : () {
                      final url = _urlController.text.trim();
                      if (url.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('请输入地址')),
                        );
                        return;
                      }
                      ref.read(connectionProvider.notifier).testConnection(url);
                    },
              child: Text(
                configState.isTesting ? '连接中...' : '测试并保存连接',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            if (configState.testResultMessage != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: configState.isConnected ? Colors.green.shade50 : Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  configState.testResultMessage!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: configState.isConnected ? Colors.green.shade800 : Colors.red.shade800,
                  ),
                ),
              ),
            ]
          ],
        ),
      ),
    );
  }
}