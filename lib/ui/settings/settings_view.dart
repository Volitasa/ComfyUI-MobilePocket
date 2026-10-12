import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import '../../providers/connection_provider.dart';
import '../../providers/locale_provider.dart';
import '../../providers/snapshot_provider.dart';
import '../../providers/local_workflow_provider.dart';
import '../../providers/github_token_provider.dart';
import 'server_config_view.dart';
import 'about_view.dart';
import 'snapshot_list_view.dart';
import 'workflow_storage_view.dart';
import 'github_token_view.dart';

/// 语言选择的返回值：用枚举而不是 Locale?，
/// 否则「取消」与「跟随系统」都是 null，无法区分。
enum LanguageChoice { follow, zh, en }

/// 设置中心：服务器配置下沉为子项，后续设置项都挂在这里。
class SettingsView extends ConsumerWidget {
  const SettingsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final config = ref.watch(connectionProvider);
    final serverCount = config.servers.length;
    final snapshotCount = ref.watch(snapshotProvider).length;
    final localCount = ref.watch(localWorkflowProvider).length;
    final tokenConfigured = ref.watch(githubTokenProvider).trim().isNotEmpty;
    final preferred = ref.watch(localeProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l.settingsTitle, style: const TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: false,
      ),
      body: ListView(
        children: [
          _SectionTitle(l.settingsSectionGeneral),
          _EntryTile(
            icon: Icons.language_outlined,
            title: l.settingsLanguage,
            subtitle: _languageLabel(l, preferred?.languageCode),
            onTap: () => _pickLanguage(context, ref),
          ),
          const Divider(height: 24),
          _SectionTitle(l.settingsSectionConnection),
          _EntryTile(
            icon: Icons.dns_outlined,
            title: l.settingsServerEntry,
            subtitle: serverCount == 0
                ? l.settingsServerNone
                : l.settingsServerCount(serverCount),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ServerConfigView()),
            ),
          ),
          const Divider(height: 24),
          _SectionTitle(l.settingsSectionData),
          _EntryTile(
            icon: Icons.folder_copy_outlined,
            title: l.settingsStorage,
            subtitle: localCount == 0
                ? l.settingsStorageNone
                : l.settingsStorageCount(localCount),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const WorkflowStorageView()),
            ),
          ),
          _EntryTile(
            icon: Icons.photo_library_outlined,
            title: l.settingsSnapshot,
            subtitle: snapshotCount == 0
                ? l.settingsSnapshotNone
                : l.settingsSnapshotCount(snapshotCount),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SnapshotListView()),
            ),
          ),
          const Divider(height: 24),
          _SectionTitle(l.settingsSectionUpdate),
          _EntryTile(
            icon: Icons.key_outlined,
            title: l.settingsToken,
            subtitle: tokenConfigured ? l.settingsTokenSet : l.settingsTokenUnset,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const GithubTokenView()),
            ),
          ),
          const Divider(height: 24),
          _SectionTitle(l.settingsSectionAbout),
          _EntryTile(
            icon: Icons.info_outline,
            title: l.settingsAbout,
            subtitle: l.settingsAboutSubtitle,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AboutView()),
            ),
          ),
        ],
      ),
    );
  }

  /// 设置项上显示的当前语言；未选择即跟随系统
  String _languageLabel(AppLocalizations l, String? code) => switch (code) {
        'zh' => l.settingsLanguageZh,
        'en' => l.settingsLanguageEn,
        _ => l.settingsLanguageFollow,
      };

  Future<void> _pickLanguage(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context);
    final choice = await showDialog<LanguageChoice>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(l.settingsLanguageTitle),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, LanguageChoice.follow),
            child: Text(l.settingsLanguageFollow),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, LanguageChoice.zh),
            child: Text(l.settingsLanguageZh),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, LanguageChoice.en),
            child: Text(l.settingsLanguageEn),
          ),
        ],
      ),
    );
    if (choice == null) return;

    final notifier = ref.read(localeProvider.notifier);
    switch (choice) {
      case LanguageChoice.follow:
        await notifier.setFollowSystem();
        break;
      case LanguageChoice.zh:
        await notifier.setLocale(const Locale('zh'));
        break;
      case LanguageChoice.en:
        await notifier.setLocale(const Locale('en'));
        break;
    }
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          color: Colors.grey,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _EntryTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _EntryTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: Colors.black87),
      title: Text(title),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      trailing: const Icon(Icons.chevron_right, color: Colors.grey),
      onTap: onTap,
    );
  }
}
