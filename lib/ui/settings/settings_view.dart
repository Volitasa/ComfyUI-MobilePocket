import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/connection_provider.dart';
import '../../providers/snapshot_provider.dart';
import '../../providers/local_workflow_provider.dart';
import '../../providers/github_token_provider.dart';
import 'server_config_view.dart';
import 'about_view.dart';
import 'snapshot_list_view.dart';
import 'workflow_storage_view.dart';
import 'github_token_view.dart';

/// 设置中心：服务器配置下沉为子项，后续设置项都挂在这里。
class SettingsView extends ConsumerWidget {
  const SettingsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(connectionProvider);
    final serverCount = config.servers.length;
    final snapshotCount = ref.watch(snapshotProvider).length;
    final localCount = ref.watch(localWorkflowProvider).length;
    final tokenConfigured = ref.watch(githubTokenProvider).trim().isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('设置', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: false,
      ),
      body: ListView(
        children: [
          _SectionTitle('连接'),
          _EntryTile(
            icon: Icons.dns_outlined,
            title: '服务器连接',
            subtitle: serverCount == 0
                ? '尚未配置任何服务器'
                : '已配置 $serverCount 个服务器',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ServerConfigView()),
            ),
          ),
          const Divider(height: 24),
          _SectionTitle('数据'),
          _EntryTile(
            icon: Icons.folder_copy_outlined,
            title: '工作流存储',
            subtitle: localCount == 0
                ? '导入或另存工作流后显示'
                : '已保存 $localCount 个工作流',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const WorkflowStorageView()),
            ),
          ),
          _EntryTile(
            icon: Icons.photo_library_outlined,
            title: '工作流快照',
            subtitle: snapshotCount == 0
                ? '运行工作流后自动生成'
                : '已固化 $snapshotCount 份快照',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SnapshotListView()),
            ),
          ),
          const Divider(height: 24),
          _SectionTitle('更新'),
          _EntryTile(
            icon: Icons.key_outlined,
            title: 'GitHub 访问令牌',
            subtitle: tokenConfigured
                ? '已配置，可检查私有仓库的更新'
                : '未配置。仓库为私有时必须配置才能检查更新',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const GithubTokenView()),
            ),
          ),
          const Divider(height: 24),
          _SectionTitle('关于'),
          _EntryTile(
            icon: Icons.info_outline,
            title: '关于',
            subtitle: '版本信息与检查更新',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AboutView()),
            ),
          ),
        ],
      ),
    );
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
