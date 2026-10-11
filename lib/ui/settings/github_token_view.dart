import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/github_token_provider.dart';

/// GitHub 访问令牌配置页。
///
/// 本应用的仓库是私有的，而 GitHub 对无权限的匿名请求一律返回 404
/// （不会返回 403，以免泄露仓库是否存在）。因此必须配置一个只读令牌，
/// 检查更新与下载安装包才能正常工作。
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
    await ref.read(githubTokenProvider.notifier).save(_controller.text);
    _snack(_controller.text.trim().isEmpty ? '令牌已清除' : '令牌已保存');
  }

  Future<void> _clear() async {
    _controller.clear();
    await ref.read(githubTokenProvider.notifier).clear();
    _snack('令牌已清除');
  }

  @override
  Widget build(BuildContext context) {
    final token = ref.watch(githubTokenProvider);
    final configured = token.trim().isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('GitHub 访问令牌', style: TextStyle(fontWeight: FontWeight.bold)),
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
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          configured ? Icons.check_circle_outline : Icons.info_outline,
                          size: 20,
                          color: configured ? Colors.green : Colors.orange,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          configured ? '已配置' : '未配置',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: configured ? Colors.green.shade800 : Colors.orange.shade800,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      '更新功能读取的是 GitHub Releases。若仓库为私有，'
                      '匿名请求会一律返回 404，表现为「没有发布带安装包的版本」。'
                      '配置一个只读令牌即可正常检查更新与下载。',
                      style: TextStyle(fontSize: 13, height: 1.5),
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
                  icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save_outlined),
              label: const Text('保存'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: configured ? _clear : null,
              icon: const Icon(Icons.delete_outline),
              label: const Text('清除令牌'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              '如何创建令牌',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              '1. GitHub → Settings → Developer settings\n'
              '2. Personal access tokens → Fine-grained tokens → Generate new token\n'
              '3. Repository access 只勾选本仓库\n'
              '4. Permissions → Repository permissions → Contents 设为 Read-only\n'
              '5. 生成后复制，粘贴到上面保存\n\n'
              '提示：细粒度令牌有有效期，过期后检查更新会提示令牌无效，'
              '届时重新生成并更新即可。令牌仅保存在本机，不会上传。',
              style: TextStyle(fontSize: 13, height: 1.6),
            ),
          ],
        ),
      ),
    );
  }
}
