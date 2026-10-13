import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:comfyui_mobilepocket/l10n/app_localizations.dart';

import '../../providers/github_token_provider.dart';
import '../../theme.dart';

/// GitHub 访问令牌配置页。
///
/// 仓库为私有时，匿名请求 releases 接口会被 GitHub 一律回 404，
/// 需要配置一个对该仓库有 Contents 读取权限的令牌才能检查更新。
class GithubTokenView extends ConsumerStatefulWidget {
  const GithubTokenView({super.key});

  @override
  ConsumerState<GithubTokenView> createState() => _GithubTokenViewState();
}

class _GithubTokenViewState extends ConsumerState<GithubTokenView> {
  // 控制器在 State 内创建与释放，避免在 build 中新建导致泄漏
  final TextEditingController _controller = TextEditingController();
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    _controller.text = ref.read(githubTokenProvider);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _save() async {
    // 在 await 前取好文案，避免异步 gap 后使用 context
    final l = AppLocalizations.of(context);
    await ref.read(githubTokenProvider.notifier).save(_controller.text);
    _snack(_controller.text.trim().isEmpty ? l.tokenCleared : l.tokenSaved);
  }

  Future<void> _clear() async {
    _controller.clear();
    final l = AppLocalizations.of(context);
    await ref.read(githubTokenProvider.notifier).clear();
    _snack(l.tokenCleared);
  }

  @override
  Widget build(BuildContext context) {
    final token = ref.watch(githubTokenProvider);
    final configured = token.trim().isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          AppLocalizations.of(context).tokenTitle,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.grey.shade200),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Icon(
                      configured
                          ? Icons.check_circle_outline
                          : Icons.info_outline,
                      size: 20,
                      color: configured ? AppColors.success : AppColors.neutral,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        configured
                            ? AppLocalizations.of(context).tokenConfigured
                            : AppLocalizations.of(context).wfStatusUnconfigured,
                        style: TextStyle(
                          fontSize: 13,
                          color: configured
                              ? AppColors.success
                              : AppColors.neutral,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              obscureText: _obscure,
              maxLines: 1,
              decoration: InputDecoration(
                labelText: 'Personal Access Token',
                hintText: 'github_pat_… 或 ghp_…',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscure ? Icons.visibility_off : Icons.visibility,
                  ),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save_outlined),
              label: Text(AppLocalizations.of(context).save),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(
                  vertical: 14,
                  horizontal: 16,
                ),
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: configured ? _clear : null,
              icon: const Icon(Icons.delete_outline),
              label: Text(AppLocalizations.of(context).tokenClearButton),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  vertical: 14,
                  horizontal: 16,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              AppLocalizations.of(context).tokenLocalOnlyNote,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
