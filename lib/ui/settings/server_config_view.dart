import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:comfyui_mobilepocket/l10n/app_localizations.dart';

import '../../providers/connection_provider.dart';
import '../../providers/parsed_workflow_provider.dart';

import '../../theme.dart';

/// 连接探测结果 → 展示文案。结果本身只描述“发生了什么”，
/// 这里才按当前语言拼出句子（颜色也由 ok 决定，不再靠文案里的字眼判断）。
String testResultText(AppLocalizations l, ConnectionTestResult r) =>
    switch (r.kind) {
      ConnectionTestKind.activatedPrimary => l.serverActivatedPrimary(r.name),
      ConnectionTestKind.activatedBackup => l.serverActivatedBackup(r.name),
      ConnectionTestKind.activateFailed => l.serverActivateFailed(r.name),
      ConnectionTestKind.testPrimaryOk => l.serverTestPrimaryOk,
      ConnectionTestKind.testBackupOk => l.serverTestBackupOk,
      ConnectionTestKind.testAllFailed => l.serverTestAllFailed,
      ConnectionTestKind.emptyPrimary => l.serverTestEmptyPrimary,
    };

/// 连接名：旧数据可能没有名称，这里按当前语言补默认名
String serverDisplayName(AppLocalizations l, String name) =>
    name.trim().isEmpty ? l.serverDefaultName : name;

class ServerConfigView extends ConsumerStatefulWidget {
  const ServerConfigView({super.key});

  @override
  ConsumerState<ServerConfigView> createState() => _ServerConfigViewState();
}

class _ServerConfigViewState extends ConsumerState<ServerConfigView> {
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final config = ref.watch(connectionProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          l.serverTitle,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: false,
      ),
      body: config.servers.isEmpty
          ? _buildEmpty(l)
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // 连接结果提示
                if (config.testResult != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: config.testResult!.ok
                          ? context.stateSuccessFill
                          : context.stateDangerFill,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      testResultText(l, config.testResult!),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: config.testResult!.ok
                            ? context.onStateSuccessFill
                            : context.onStateDangerFill,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                ...config.servers.map((s) => _buildServerCard(config, s, l)),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: config.isTesting
                      ? null
                      : () => _showServerDialog(),
                  icon: const Icon(Icons.add),
                  label: Text(l.serverAdd),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: BorderSide(color: context.borderColor),
                    foregroundColor: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  l.serverHint,
                  style: TextStyle(fontSize: 12, color: context.textSecondary),
                ),
              ],
            ),
    );
  }

  Widget _buildEmpty(AppLocalizations l) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(l.serverEmpty, style: TextStyle(color: context.textSecondary)),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => _showServerDialog(),
            icon: const Icon(Icons.add),
            label: Text(l.serverAdd),
          ),
        ],
      ),
    );
  }

  Widget _buildServerCard(
    ConfigState config,
    ServerConfig server,
    AppLocalizations l,
  ) {
    final isActive = config.activeServerId == server.id;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isActive ? context.stateSuccess : context.borderColor,
          width: isActive ? 1.5 : 1,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        // 单选指示：同时只能启用一个连接（点击卡片主体或圆点启用）
        leading: config.isTesting && isActive
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(
                isActive
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: isActive ? context.accent : context.textSecondary,
              ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                serverDisplayName(l, server.name),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isActive)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: config.isConnected
                      ? context.stateSuccessFill
                      : context.stateWarningFill,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  config.isConnected ? l.serverConnected : l.serverActivated,
                  style: TextStyle(
                    fontSize: 10,
                    color: config.isConnected
                        ? context.onStateSuccessFill
                        : context.onStateWarningFill,
                  ),
                ),
              ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 2),
            Text(
              l.serverPrimaryPrefix(server.primaryUrl),
              style: const TextStyle(fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
            if (server.backupUrl.trim().isNotEmpty)
              Text(
                l.serverBackupPrefix(server.backupUrl),
                style: const TextStyle(fontSize: 12),
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
        // 点击卡片主体 = 启用该连接
        onTap: config.isTesting
            ? null
            : () {
                if (!isActive) {
                  ref
                      .read(connectionProvider.notifier)
                      .activateServer(server.id);
                }
              },
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 20),
              tooltip: l.serverEditTooltip,
              onPressed: () => _showServerDialog(existing: server),
            ),
            IconButton(
              icon: const Icon(
                Icons.delete_outline,
                size: 20,
                color: Colors.redAccent,
              ),
              tooltip: l.delete,
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
      await notifier.updateServer(
        existing.id,
        result.name,
        result.primary,
        result.backup,
      );
    }
  }

  Future<void> _confirmDelete(ServerConfig server) async {
    final l = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.serverDeleteTitle),
        content: Text(l.serverDeleteConfirm(serverDisplayName(l, server.name))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.delete),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await ref.read(connectionProvider.notifier).removeServer(server.id);
      // 该连接名下的解析缓存再也无从刷新或校验，一并清掉避免变成永久孤儿
      ref.read(parsedWorkflowProvider.notifier).removeByServer(server.id);
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
  // 探测结果只存“发生了什么”，文案与颜色都交给 build 处理
  ConnectionTestResult? _testResult;
  bool _testing = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.existing?.name ?? '');
    _primaryCtrl = TextEditingController(
      text: widget.existing?.primaryUrl ?? '',
    );
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
      setState(
        () => _testResult = const ConnectionTestResult(
          ok: false,
          kind: ConnectionTestKind.emptyPrimary,
        ),
      );
      return;
    }
    setState(() {
      _testing = true;
      _testResult = null;
    });
    final result = await ref
        .read(connectionProvider.notifier)
        .testUrls(_primaryCtrl.text, _backupCtrl.text);
    if (!mounted) return;
    setState(() {
      _testing = false;
      _testResult = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(widget.existing == null ? l.serverAdd : l.serverEdit),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameCtrl,
              decoration: InputDecoration(
                labelText: l.serverFormName,
                hintText: l.serverFormNameHint,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _primaryCtrl,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                labelText: l.serverFormPrimary,
                hintText: l.serverFormPrimaryHint,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _backupCtrl,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                labelText: l.serverFormBackup,
                hintText: l.serverFormBackupHint,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            if (_testResult != null) ...[
              const SizedBox(height: 10),
              Text(
                testResultText(l, _testResult!),
                style: TextStyle(
                  fontSize: 12,
                  color: _testResult!.ok
                      ? context.stateSuccess
                      : context.stateDanger,
                ),
              ),
            ],
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _testing ? null : _test,
              icon: _testing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.wifi_find, size: 18),
              label: Text(l.serverTest),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: context.accent),
          onPressed: () {
            if (_primaryCtrl.text.trim().isEmpty) return;
            Navigator.pop(
              context,
              _ServerFormResult(
                _nameCtrl.text,
                _primaryCtrl.text,
                _backupCtrl.text,
              ),
            );
          },
          child: Text(l.save),
        ),
      ],
    );
  }
}
