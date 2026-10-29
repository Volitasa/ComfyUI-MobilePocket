import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:comfyui_mobilepocket/l10n/app_localizations.dart';

import '../../providers/connection_provider.dart';
import '../../providers/haptics_provider.dart';
import '../../providers/locale_provider.dart';
import '../../providers/theme_mode_provider.dart';
import '../../providers/snapshot_provider.dart';
import '../../providers/local_workflow_provider.dart';
import '../../providers/github_token_provider.dart';
import '../widgets/section_title.dart';
import 'server_config_view.dart';
import 'about_view.dart';
import 'snapshot_list_view.dart';
import 'workflow_storage_view.dart';
import 'github_token_view.dart';

import '../../theme.dart';

/// 语言选择的返回值：用枚举而不是 Locale?，
/// 否则「取消」与「跟随系统」都是 null，无法区分。
enum LanguageChoice { follow, zh, en }

/// 外观选择的返回值，同上：枚举才能区分「取消」和「跟随系统」。
enum AppearanceChoice { follow, light, dark }

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
    final themeChoice = ref.watch(themeModeProvider);
    final haptics = ref.watch(hapticsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          l.settingsTitle,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
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
          _EntryTile(
            icon: Icons.brightness_6_outlined,
            title: l.settingsAppearance,
            subtitle: _appearanceLabel(l, themeChoice),
            onTap: () => _pickAppearance(context, ref),
          ),
          // 与语言 / 外观同一套交互：点开弹窗选，不在这页再引入一种「开关」控件
          _EntryTile(
            icon: Icons.vibration,
            title: l.settingsHaptics,
            subtitle: haptics.isEmpty
                ? l.settingsHapticsOff
                : l.settingsHapticsCount(haptics.length),
            onTap: () => _pickHaptics(context, ref),
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
            subtitle: tokenConfigured
                ? l.settingsTokenSet
                : l.settingsTokenUnset,
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

  /// 设置项上显示的当前外观；未选择即跟随系统
  String _appearanceLabel(AppLocalizations l, ThemeMode? mode) =>
      switch (mode) {
        ThemeMode.light => l.settingsAppearanceLight,
        ThemeMode.dark => l.settingsAppearanceDark,
        _ => l.settingsLanguageFollow,
      };

  Future<void> _pickAppearance(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context);
    final choice = await showDialog<AppearanceChoice>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(l.settingsAppearanceTitle),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, AppearanceChoice.follow),
            child: Text(l.settingsLanguageFollow),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, AppearanceChoice.light),
            child: Text(l.settingsAppearanceLight),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, AppearanceChoice.dark),
            child: Text(l.settingsAppearanceDark),
          ),
        ],
      ),
    );
    if (choice == null) return;

    final notifier = ref.read(themeModeProvider.notifier);
    switch (choice) {
      case AppearanceChoice.follow:
        await notifier.setFollowSystem();
        break;
      case AppearanceChoice.light:
        await notifier.setThemeMode(ThemeMode.light);
        break;
      case AppearanceChoice.dark:
        await notifier.setThemeMode(ThemeMode.dark);
        break;
    }
  }

  /// 震动分类：可多选，改完立即生效（弹窗不关，方便逐项试）。
  ///
  /// 与语言 / 外观同一套交互：这条也是「点开弹窗选」，不在这页引入开关控件。
  Future<void> _pickHaptics(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context);
    await showDialog<void>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(l.settingsHaptics),
        children: [
          Consumer(
            builder: (dialogContext, ref, _) {
              final enabled = ref.watch(hapticsProvider);
              final notifier = ref.read(hapticsProvider.notifier);
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final category in HapticCategory.values)
                    ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 24,
                      ),
                      title: Text(
                        _hapticLabel(l, category),
                        style: const TextStyle(fontSize: 14),
                      ),
                      // 关闭时也占住 20 的位置，勾选状态一变整行不会左右跳
                      trailing: Icon(
                        enabled.contains(category) ? Icons.check : null,
                        size: 20,
                        color: dialogContext.accent,
                      ),
                      onTap: () => notifier.toggle(category),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => notifier.setAll(true),
                          child: Text(l.hapticsAllOn),
                        ),
                        TextButton(
                          onPressed: () => notifier.setAll(false),
                          child: Text(l.hapticsAllOff),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  /// 分类名：只用于展示，不落盘（落盘的是枚举名）。
  String _hapticLabel(AppLocalizations l, HapticCategory category) =>
      switch (category) {
        HapticCategory.nav => l.hapticsNav,
        HapticCategory.check => l.hapticsCheck,
        HapticCategory.reorder => l.hapticsReorder,
        HapticCategory.fold => l.hapticsFold,
        HapticCategory.submit => l.hapticsSubmit,
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

/// 设置页没有卡片左右边距，分组标题贴 16；样式与首页、工作流存储页共用一个控件。
class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return SectionTitle(
      text,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
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
      // 原来是写死的 Theme.of(context).colorScheme.onSurface，深色底上只有 1.16:1，等于隐形
      leading: Icon(icon, color: Theme.of(context).colorScheme.onSurface),
      title: Text(title),
      subtitle: Text(
        subtitle,
        style: TextStyle(fontSize: 12, color: context.textSecondary),
      ),
      trailing: Icon(Icons.chevron_right, color: context.textSecondary),
      onTap: onTap,
    );
  }
}
