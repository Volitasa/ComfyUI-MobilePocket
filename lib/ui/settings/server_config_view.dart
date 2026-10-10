import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/connection_provider.dart';

class ServerConfigView extends ConsumerStatefulWidget {
  const ServerConfigView({super.key});

  @override
  ConsumerState<ServerConfigView> createState() => _ServerConfigViewState();
}

class _ServerConfigViewState extends ConsumerState<ServerConfigView> {
  @override
  Widget build(BuildContext context) {
    final config = ref.watch(connectionProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('服务器配置', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: false,
      ),
      body: config.servers.isEmpty
          ? _buildEmpty()
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // 连接结果提示
                if (config.testResultMessage != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: config.isConnected ? Colors.green.shade50 : Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      config.testResultMessage!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: config.isConnected ? Colors.green.shade800 : Colors.red.shade800,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                ...config.servers.map((s) => _buildServerCard(config, s)),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: config.isTesting ? null : () => _showServerDialog(),
                  icon: const Icon(Icons.add),
                  label: const Text('新增连接'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: const BorderSide(color: Colors.grey),
                    foregroundColor: Colors.black87,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  '提示：点击卡片启用对应连接（同时只能启用一个）。每个连接可配置主/备两个地址，连接时先尝试主地址，不通则自动尝试备用地址。',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('还没有保存的服务器连接', style: TextStyle(color: Colors.black54)),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => _showServerDialog(),
            icon: const Icon(Icons.add),
            label: const Text('新增连接'),
          ),
        ],
      ),
    );
  }

  Widget _buildServerCard(ConfigState config, ServerConfig server) {
    final isActive = config.activeServerId == server.id;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isActive ? Colors.green.shade400 : Colors.grey.shade300,
          width: isActive ? 1.5 : 1,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        // 单选指示：同时只能启用一个连接（点击卡片主体或圆点启用）
        leading: config.isTesting && isActive
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
            : Icon(
                isActive ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                color: isActive ? Colors.green : Colors.grey,
              ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                server.name,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isActive)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: config.isConnected ? Colors.green.shade50 : Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  config.isConnected ? '已连接' : '已启用',
                  style: TextStyle(
                    fontSize: 10,
                    color: config.isConnected ? Colors.green.shade700 : Colors.orange.shade800,
                  ),
                ),
              ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 2),
            Text('主: ${server.primaryUrl}', style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis),
            if (server.backupUrl.trim().isNotEmpty)
              Text('备: ${server.backupUrl}', style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis),
          ],
        ),
        // 点击卡片主体 = 启用该连接
        onTap: config.isTesting
            ? null
            : () {
                if (!isActive) {
                  ref.read(connectionProvider.notifier).activateServer(server.id);
                }
              },
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 20),
              tooltip: '编辑',
              onPressed: () => _showServerDialog(existing: server),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 20, color: Colors.redAccent),
              tooltip: '删除',
              onPressed: () => _confirmDelete(server),
            ),
          ],
        ),
      ),
    );
  }

  // 新增/编辑连接对话框入口。
  // 对话框内容抽为独立 StatefulWidget（_ServerFormDialog），
  // 由它自己管理 TextEditingController 的生命周期——避免在对话框
  // 退场动画结束前 dispose 掉仍被 TextField 引用的 controller。
  Future<void> _showServerDialog({ServerConfig? existing}) async {
    final result = await showDialog<_ServerFormResult>(
      context: context,
      builder: (ctx) => _ServerFormDialog(existing: existing),
    );

    if (result == null || !mounted) return;
    final notifier = ref.read(connectionProvider.notifier);
    if (existing == null) {
      await notifier.addServer(result.name, result.primary, result.backup);
    } else {
      await notifier.updateServer(existing.id, result.name, result.primary, result.backup);
    }
  }

  Future<void> _confirmDelete(ServerConfig server) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除连接'),
        content: Text('确定删除「${server.name}」吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await ref.read(connectionProvider.notifier).removeServer(server.id);
    }
  }
}

/// 新增/编辑连接对话框的返回值
class _ServerFormResult {
  final String name;
  final String primary;
  final String backup;
  _ServerFormResult(this.name, this.primary, this.backup);
}

/// 新增/编辑连接表单：独立 State，自管理输入控制器生命周期
class _ServerFormDialog extends ConsumerStatefulWidget {
  final ServerConfig? existing;
  const _ServerFormDialog({this.existing});

  @override
  ConsumerState<_ServerFormDialog> createState() => _ServerFormDialogState();
}

class _ServerFormDialogState extends ConsumerState<_ServerFormDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _primaryCtrl;
  late final TextEditingController _backupCtrl;
  String _testMsg = '';
  bool _testing = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.existing?.name ?? '');
    _primaryCtrl = TextEditingController(text: widget.existing?.primaryUrl ?? '');
    _backupCtrl = TextEditingController(text: widget.existing?.backupUrl ?? '');
  }

  @override
  void dispose() {
    // 与对话框 State 同生命周期释放，此时退场动画已结束、TextField 已卸载
    _nameCtrl.dispose();
    _primaryCtrl.dispose();
    _backupCtrl.dispose();
    super.dispose();
  }

  Future<void> _test() async {
    if (_primaryCtrl.text.trim().isEmpty) {
      setState(() => _testMsg = '请先填写主地址');
      return;
    }
    setState(() {
      _testing = true;
      _testMsg = '';
    });
    final msg = await ref
        .read(connectionProvider.notifier)
        .testUrls(_primaryCtrl.text, _backupCtrl.text);
    if (!mounted) return;
    setState(() {
      _testing = false;
      _testMsg = msg;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? '新增连接' : '编辑连接'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: '名称',
                hintText: '例如: 家里内网 / 公司外网',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _primaryCtrl,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: '主地址（优先尝试）',
                hintText: '例如: http://192.168.1.100:8188',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _backupCtrl,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: '备用地址（可选）',
                hintText: '主地址不通时使用，如外网地址',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            if (_testMsg.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                _testMsg,
                style: TextStyle(
                  fontSize: 12,
                  color: _testMsg.contains('不可用') ? Colors.red.shade700 : Colors.green.shade700,
                ),
              ),
            ],
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _testing ? null : _test,
              icon: _testing
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.wifi_find, size: 18),
              label: const Text('测试连接'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.green),
          onPressed: () {
            if (_primaryCtrl.text.trim().isEmpty) return;
            Navigator.pop(
              context,
              _ServerFormResult(_nameCtrl.text, _primaryCtrl.text, _backupCtrl.text),
            );
          },
          child: const Text('保存'),
        ),
      ],
    );
  }
}
