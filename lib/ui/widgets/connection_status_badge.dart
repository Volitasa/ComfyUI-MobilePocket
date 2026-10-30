import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:comfyui_mobilepocket/l10n/app_localizations.dart';

import '../../theme.dart';
import '../../providers/connection_provider.dart';
import '../../providers/ws_event_provider.dart';
import '../settings/server_config_view.dart' show serverDisplayName;

/// 连接状态指示：显示当前连接的服务器名 + 连接状态点。
/// 首页与生成记录页顶部复用，保证两处一致性。
///
/// 断线时圆点会缓慢呼吸、并写明「重连中」——只写状态，不解释 WebSocket 这类机制。
/// ⚠️ 呼吸是**无限动画**，只在「真的在重连」这一个状态下开：
/// 连上、没配服务器、重连次数用完都必须停，否则后台页面白烧帧、徽标也在说假话。
class ConnectionStatusBadge extends ConsumerStatefulWidget {
  final VoidCallback? onTap;
  const ConnectionStatusBadge({super.key, this.onTap});

  @override
  ConsumerState<ConnectionStatusBadge> createState() =>
      _ConnectionStatusBadgeState();
}

class _ConnectionStatusBadgeState extends ConsumerState<ConnectionStatusBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
    // ⚠️ 必须给 1：默认是 0，而 0 对应的 opacity 是 0.35，
    // 于是「没在重连」的常态圆点会被压成三四成透明（实测像素 182,210,183，
    // 正好是 #2E7D32 叠加 35% 后的值）。这一行就是「绿点变浅变暗」的根因。
    value: 1,
  );
  bool _pulsing = false;

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  /// 启停呼吸。只在状态翻转时才动控制器，避免每帧 repeat 一次。
  void _syncPulse(bool shouldPulse) {
    if (shouldPulse == _pulsing) return;
    _pulsing = shouldPulse;
    // 系统开了「移除动画」就保持常亮：呼吸是装饰，不是信息本身
    if (shouldPulse && !MediaQuery.disableAnimationsOf(context)) {
      _pulse.repeat(reverse: true);
    } else {
      _pulse.stop();
      _pulse.value = 1;
    }
  }

  @override
  Widget build(BuildContext context) {
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
    // 「重连中」必须来自真的在重连，不能由「没连上」推断（见 WsState.isReconnecting）
    final reconnecting = !connected && wsState.isReconnecting;
    final color = connected ? context.stateSuccess : context.stateDanger;
    final label = reconnecting ? l.badgeReconnecting : name;

    _syncPulse(reconnecting);

    return InkWell(
      onTap: widget.onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            FadeTransition(
              // begin 小、end 大：控制器停在 1 时是常亮，往返跑时才会暗下去
              opacity: _pulse.drive(
                Tween<double>(
                  begin: 0.35,
                  end: 1,
                ).chain(CurveTween(curve: Curves.easeInOut)),
              ),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOut,
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
            ),
            const SizedBox(width: 6),
            // 文案在「服务器名 ↔ 重连中」之间淡入淡出，不要瞬间换字
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: Text(
                label,
                key: ValueKey<String>(label),
                style: TextStyle(
                  fontSize: 12,
                  color: reconnecting
                      ? context.stateDanger
                      : Theme.of(context).colorScheme.onSurface,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
