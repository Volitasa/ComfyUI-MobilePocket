import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';

import '../../providers/update_provider.dart';
import '../../services/update_service.dart';
import '../../theme.dart';

/// 关于页：展示版本号，并提供手动检查更新入口。
class AboutView extends ConsumerStatefulWidget {
  const AboutView({super.key});

  @override
  ConsumerState<AboutView> createState() => _AboutViewState();
}

class _AboutViewState extends ConsumerState<AboutView> {
  @override
  void initState() {
    super.initState();
    // 异步读取，不会在 build 阶段改动状态
    ref.read(updateProvider.notifier).loadCurrentVersion();
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _downloadAndInstall() async {
    try {
      final path = await ref.read(updateProvider.notifier).downloadUpdate();
      final result = await OpenFilex.open(
        path,
        type: 'application/vnd.android.package-archive',
      );
      if (result.type != ResultType.done) {
        _snack('无法唤起安装界面：${result.message}');
      }
    } on UpdateException catch (e) {
      _snack(e.message);
    } catch (_) {
      // 具体原因已写入状态，这里不重复提示
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(updateProvider);
    final busy = state.status == UpdateStatus.checking ||
        state.status == UpdateStatus.downloading;

    return Scaffold(
      appBar: AppBar(
        title: const Text('关于', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildVersionCard(state),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: busy
                  ? null
                  : () => ref.read(updateProvider.notifier).checkForUpdate(),
              icon: const Icon(Icons.system_update_alt),
              label: const Text('检查更新'),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.green,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
            const SizedBox(height: 16),
            _buildStatus(state),
            const SizedBox(height: 24),
            const Text(
              '更新来源：GitHub Releases',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 4),
            SelectableText(
              UpdateService.repoHomeUrl,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVersionCard(UpdateState state) {
    final version = state.currentVersion.isEmpty ? '—' : state.currentVersion;
    final build = state.currentBuild.isEmpty ? '—' : state.currentBuild;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.apps, color: Colors.black54),
            ),
            const SizedBox(width: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'ComfyUI MobilePocket',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  '版本 $version（构建 $build）',
                  style: const TextStyle(fontSize: 13, color: Colors.grey),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatus(UpdateState state) {
    switch (state.status) {
      case UpdateStatus.checking:
        return const _InfoRow(
          icon: Icons.hourglass_top,
          color: Colors.grey,
          text: '正在检查更新…',
        );

      case UpdateStatus.upToDate:
        return _InfoRow(
          icon: Icons.check_circle_outline,
          color: AppColors.success,
          text: '当前已是最新版本 ${state.currentVersion}',
        );

      case UpdateStatus.error:
        return _InfoRow(
          icon: Icons.error_outline,
          color: AppColors.danger,
          text: state.message ?? '检查更新失败',
          action: TextButton(
            onPressed: () => ref.read(updateProvider.notifier).checkForUpdate(),
            child: const Text('重试'),
          ),
        );

      case UpdateStatus.available:
      case UpdateStatus.downloading:
        final release = state.release;
        if (release == null) return const SizedBox.shrink();
        if (!Platform.isAndroid) {
          return _InfoRow(
            icon: Icons.info_outline,
            color: Colors.grey,
            text: '发现新版本 ${release.version}，当前平台不支持应用内安装，请到 Release 页面手动下载',
          );
        }
        return _buildReleaseCard(state, release);

      case UpdateStatus.idle:
        return const SizedBox.shrink();
    }
  }

  Widget _buildReleaseCard(UpdateState state, release) {
    final downloading = state.status == UpdateStatus.downloading;

    return Card(
      elevation: 0,
      color: Colors.green.shade50,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.green.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.new_releases_outlined, color: Colors.green.shade700),
                const SizedBox(width: 8),
                Text(
                  '发现新版本 ${release.version}',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.green.shade800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${release.assetName} · ${release.sizeText}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            if (release.notes.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text('更新说明', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 180),
                child: SingleChildScrollView(
                  child: Text(
                    release.notes,
                    style: const TextStyle(fontSize: 13, height: 1.5),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 14),
            if (downloading)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LinearProgressIndicator(
                    value: state.progress > 0 ? state.progress : null,
                    backgroundColor: Colors.green.shade100,
                    color: Colors.green,
                    minHeight: 5,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    state.progress > 0
                        ? '下载中 ${(state.progress * 100).toStringAsFixed(0)}%'
                        : '正在下载…',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              )
            else
              FilledButton.icon(
                onPressed: _downloadAndInstall,
                icon: const Icon(Icons.download),
                label: const Text('下载并安装'),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.green,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  final Widget? action;

  const _InfoRow({
    required this.icon,
    required this.color,
    required this.text,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(text, style: TextStyle(fontSize: 13, color: color)),
            ),
            ?action,
          ],
        ),
      ),
    );
  }
}
