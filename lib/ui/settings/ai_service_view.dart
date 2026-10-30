import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../l10n/app_localizations.dart';
import '../../models/ai_provider_config.dart';
import '../../providers/ai_settings_provider.dart';
import '../../theme.dart';
import '../widgets/page_title.dart';

/// AI 供应商列表。
///
/// 结构与交互**完全对齐服务器连接页**（`server_config_view.dart`）：
/// 卡片圆角 10 / 间距 6、点卡片主体设为当前、行尾编辑与删除、
/// 「添加」按钮开同一个对话框、测试结果内联显示。
class AiServiceView extends ConsumerStatefulWidget {
  const AiServiceView({super.key});

  @override
  ConsumerState<AiServiceView> createState() => _AiServiceViewState();
}

class _AiServiceViewState extends ConsumerState<AiServiceView> {
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final settings = ref.watch(aiSettingsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l.aiServiceTitle, style: kSubPageTitleStyle),
        centerTitle: false,
      ),
      body: settings.providers.isEmpty
          ? _buildEmpty(l)
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                ...settings.providers.map(
                  (p) => _buildProviderCard(settings, p, l),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => _showProviderDialog(),
                  icon: const Icon(Icons.add),
                  label: Text(l.aiServiceAdd),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: BorderSide(color: context.borderColor),
                    foregroundColor: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  l.aiServiceKeyNote,
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
          Text(
            l.aiServiceEmpty,
            style: TextStyle(color: context.textSecondary),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => _showProviderDialog(),
            icon: const Icon(Icons.add),
            label: Text(l.aiServiceAdd),
          ),
        ],
      ),
    );
  }

  Widget _buildProviderCard(
    AiSettings settings,
    AiProviderConfig provider,
    AppLocalizations l,
  ) {
    final isActive = settings.activeId == provider.id;
    return Card(
      // 列表卡片统一：圆角 10、间距 6（与服务器连接、首页工作流、生成记录一致）
      margin: const EdgeInsets.only(bottom: 6),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: isActive ? context.stateSuccess : context.borderColor,
          width: isActive ? 1.5 : 1,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: Icon(
          isActive ? Icons.radio_button_checked : Icons.radio_button_unchecked,
          color: isActive ? context.accent : context.textSecondary,
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                provider.name.trim().isEmpty ? provider.id : provider.name,
                style: const TextStyle(
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isActive)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: context.stateSuccessFill,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  l.aiServiceActiveTag,
                  style: TextStyle(
                    fontSize: 11,
                    color: context.onStateSuccessFill,
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
              provider.model.trim().isEmpty ? '—' : provider.model,
              style: const TextStyle(fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              provider.baseUrl,
              style: const TextStyle(fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        onTap: isActive
            ? null
            : () =>
                  ref.read(aiSettingsProvider.notifier).setActive(provider.id),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 20),
              tooltip: l.aiServiceEdit,
              onPressed: () => _showProviderDialog(existing: provider),
            ),
            IconButton(
              icon: const Icon(
                Icons.delete_outline,
                size: 20,
                color: Colors.redAccent,
              ),
              tooltip: l.delete,
              onPressed: () => _confirmDelete(provider),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showProviderDialog({AiProviderConfig? existing}) async {
    final result = await showDialog<AiProviderConfig>(
      context: context,
      builder: (ctx) => _AiProviderFormDialog(existing: existing),
    );
    if (result == null || !mounted) return;
    await ref.read(aiSettingsProvider.notifier).upsert(result);
  }

  Future<void> _confirmDelete(AiProviderConfig provider) async {
    final l = AppLocalizations.of(context);
    final name = provider.name.trim().isEmpty ? provider.id : provider.name;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.aiServiceDeleteTitle),
        content: Text(l.aiServiceDeleteConfirm(name)),
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
      await ref.read(aiSettingsProvider.notifier).remove(provider.id);
    }
  }
}

/// 新增 / 编辑对话框。控制器随对话框 State 释放（与服务器连接页同一处理）。
class _AiProviderFormDialog extends StatefulWidget {
  const _AiProviderFormDialog({this.existing});

  final AiProviderConfig? existing;

  @override
  State<_AiProviderFormDialog> createState() => _AiProviderFormDialogState();
}

class _AiProviderFormDialogState extends State<_AiProviderFormDialog> {
  late final TextEditingController _name;
  late final TextEditingController _baseUrl;
  late final TextEditingController _model;
  late final TextEditingController _key;
  bool _obscure = true;
  bool _testing = false;
  String? _testError;

  bool get _isNew => widget.existing == null;

  @override
  void initState() {
    super.initState();
    final preset = widget.existing ?? AiProviderConfig.deepseek;
    _name = TextEditingController(text: preset.name);
    _baseUrl = TextEditingController(text: preset.baseUrl);
    _model = TextEditingController(text: preset.model);
    _key = TextEditingController(text: preset.apiKey);
  }

  @override
  void dispose() {
    _name.dispose();
    _baseUrl.dispose();
    _model.dispose();
    _key.dispose();
    super.dispose();
  }

  void _applyPreset(AiProviderConfig preset) {
    setState(() {
      _name.text = preset.name;
      _baseUrl.text = preset.baseUrl;
      _model.text = preset.model;
    });
  }

  AiProviderConfig _collect() {
    final base = widget.existing ?? AiProviderConfig.deepseek;
    return base.copyWith(
      id:
          widget.existing?.id ??
          '${base.id}_${DateTime.now().millisecondsSinceEpoch}',
      name: _name.text.trim().isEmpty ? base.name : _name.text.trim(),
      baseUrl: _baseUrl.text.trim(),
      model: _model.text.trim(),
      apiKey: _key.text.trim(),
    );
  }

  Future<void> _test() async {
    final provider = _collect();
    if (provider.baseUrl.isEmpty) return;
    setState(() {
      _testing = true;
      _testError = null;
    });
    final client = http.Client();
    String? error;
    try {
      final res = await client
          .get(
            Uri.parse(provider.modelsEndpoint),
            headers: {
              if (provider.apiKey.isNotEmpty)
                'Authorization': 'Bearer ${provider.apiKey}',
            },
          )
          .timeout(const Duration(seconds: 15));
      if (res.statusCode < 200 || res.statusCode >= 300) {
        error = 'HTTP ${res.statusCode}';
      }
    } catch (e) {
      error = '$e';
    } finally {
      client.close();
      if (mounted) {
        setState(() {
          _testing = false;
          _testError = error;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(_isNew ? l.aiServiceAdd : l.aiServiceEdit),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_isNew) ...[
              Wrap(
                spacing: 6,
                children: [
                  ActionChip(
                    label: Text(l.aiServicePresetDeepSeek),
                    onPressed: () => _applyPreset(AiProviderConfig.deepseek),
                  ),
                  ActionChip(
                    label: Text(l.aiServicePresetCustom),
                    onPressed: () => _applyPreset(
                      AiProviderConfig.custom(
                        now: DateTime.now().millisecondsSinceEpoch,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: _name,
              decoration: InputDecoration(
                labelText: l.aiServiceName,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _baseUrl,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                labelText: l.aiServiceBaseUrl,
                hintText: 'https://api.deepseek.com',
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _model,
              decoration: InputDecoration(
                labelText: l.aiServiceModel,
                hintText: 'deepseek-chat',
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _key,
              obscureText: _obscure,
              decoration: InputDecoration(
                labelText: l.aiServiceApiKey,
                border: const OutlineInputBorder(),
                isDense: true,
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscure ? Icons.visibility_off : Icons.visibility,
                    size: 18,
                  ),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
            ),
            if (_testError != null) ...[
              const SizedBox(height: 10),
              Text(
                l.aiServiceTestFail(_testError!),
                style: TextStyle(fontSize: 12, color: context.stateDanger),
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
              label: Text(l.aiServiceTest),
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
            if (_baseUrl.text.trim().isEmpty) return;
            Navigator.pop(context, _collect());
          },
          child: Text(l.save),
        ),
      ],
    );
  }
}
