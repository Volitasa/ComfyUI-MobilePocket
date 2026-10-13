import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:comfyui_mobilepocket/l10n/app_localizations.dart';
import 'package:open_filex/open_filex.dart';

import '../../models/release_info.dart';
import '../../providers/update_provider.dart';
import '../../providers/github_token_provider.dart';
import '../../services/update_service.dart';
import '../../theme.dart';
import '../../utils/release_notes.dart';
import 'github_token_view.dart';

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
    // 在首个 await 前取好文案，避免异步 gap 后使用 context
    final l = AppLocalizations.of(context);
    try {
      final path = await ref.read(updateProvider.notifier).downloadUpdate();
      final result = await OpenFilex.open(
        path,
        type: 'application/vnd.android.package-archive',
      );
      if (result.type != ResultType.done) {
        _snack(l.installLaunchFailed(result.message));
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
    final busy =
        state.status == UpdateStatus.checking ||
        state.status == UpdateStatus.downloading;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          AppLocalizations.of(context).settingsAbout,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
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
              label: Text(AppLocalizations.of(context).updateCheckButton),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                // 水平 padding 不能省：styleFrom 会覆盖默认值，
                // 只给 vertical 会让图标与文字紧贴边缘甚至被裁切
                padding: const EdgeInsets.symmetric(
                  vertical: 14,
                  horizontal: 16,
                ),
              ),
            ),
            const SizedBox(height: 16),
            _buildStatus(state),
            const SizedBox(height: 24),
            Text(
              AppLocalizations.of(context).updateSourceNote,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
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
                  AppLocalizations.of(context)
                      .aboutVersionBuild(version, build),
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
        return _InfoRow(
          icon: Icons.hourglass_top,
          color: Colors.grey,
          text: AppLocalizations.of(context).updateChecking,
        );

      case UpdateStatus.upToDate:
        return _InfoRow(
          icon: Icons.check_circle_outline,
          color: AppColors.success,
          text: AppLocalizations.of(context)
              .updateUpToDate(state.currentVersion),
        );

      case UpdateStatus.error:
        // 未配置令牌时，最可能的原因就是私有仓库导致匿名访问被拒，
        // 直接给出通往配置页的入口，而不是让人对着报错猜
        final needsToken = ref.watch(githubTokenProvider).trim().isEmpty;
        return _InfoRow(
          icon: Icons.error_outline,
          color: AppColors.danger,
          text: state.message ?? AppLocalizations.of(context).updateCheckFailed,
          action: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton(
                onPressed: () =>
                    ref.read(updateProvider.notifier).checkForUpdate(),
                child: Text(AppLocalizations.of(context).retry),
              ),
              if (needsToken)
                TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const GithubTokenView()),
                  ),
                  child: Text(AppLocalizations.of(context).configureToken),
                ),
            ],
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
            text: AppLocalizations.of(context)
                .updateAvailableOtherPlatform(release.version),
          );
        }
        return _buildReleaseCard(state, release);

      case UpdateStatus.idle:
        return const SizedBox.shrink();
    }
  }

  Widget _buildReleaseCard(UpdateState state, ReleaseInfo release) {
    final downloading = state.status == UpdateStatus.downloading;
    final notes = parseReleaseNotes(release.notes);

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
                  AppLocalizations.of(context)
                      .updateAvailableTitle(release.version),
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
              '${release.assetName} · ${release.sizeText(AppLocalizations.of(context))}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            // GitHub 自动生成的说明含 Markdown 与裸链接，需清洗后再展示
            if (notes.text.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                AppLocalizations.of(context).releaseNotesTitle,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 180),
                child: SingleChildScrollView(
                  child: Text(
                    notes.text,
                    style: const TextStyle(fontSize: 13, height: 1.6),
                  ),
                ),
              ),
            ] else if (notes.changelogUrl.isNotEmpty) ...[
              // 没有手写说明时，至少把「完整变更」链接给出来，而不是留空白
              const SizedBox(height: 12),
              Text(
                AppLocalizations.of(context).changelogTitle,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              SelectableText(
                notes.changelogUrl,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
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
                        ? AppLocalizations.of(context).updateDownloadingPercent(
                            (state.progress * 100).toStringAsFixed(0),
                          )
                        : AppLocalizations.of(context).updateDownloading,
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              )
            else
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _downloadAndInstall,
                  icon: const Icon(Icons.download),
                  label: Text(
                    AppLocalizations.of(context).updateDownloadInstall,
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: 16,
                    ),
                  ),
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
