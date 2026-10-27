import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:comfyui_mobilepocket/l10n/app_localizations.dart';

import '../../theme.dart';
import '../../providers/connection_provider.dart';
import '../../providers/ws_event_provider.dart';
import '../settings/server_config_view.dart' show serverDisplayName;

/// 连接状态指示：显示当前连接的服务器名 + 连接状态点。
/// 首页与生成记录页顶部复用，保证两处一致性。
class ConnectionStatusBadge extends ConsumerWidget {
  final VoidCallback? onTap;
  const ConnectionStatusBadge({super.key, this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(connectionProvider);
    final wsState = ref.watch(wsProvider);

    final activeServer = config.servers
        .where((s) => s.id == config.activeServerId)
        .toList();
    final l = AppLocalizations.of(context);
    final name = activeServer.isNotEmpty
        // 名字为空（用户没填）时按当前语言补默认名
        ? serverDisplayName(l, activeServer.first.name)
        : l.notConnected;
    final connected = config.isConnected && wsState.isConnected;
    final color = connected ? context.stateSuccess : context.stateDanger;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(
              name,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurface,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
