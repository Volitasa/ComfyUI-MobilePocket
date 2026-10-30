import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:comfyui_mobilepocket/l10n/app_localizations.dart';

import '../models/task_history.dart';
import '../providers/connection_provider.dart';
import '../providers/snapshot_provider.dart';
import '../ui/builder/run_view.dart';

/// 「再次运行」：凭记录留下的快照还原表单，并预填当时的参数。
///
/// 生成记录页与画廊页共用（画廊那张图要先反查到记录才有这个入口）。
/// 两个页面各写一份的话，出错文案、跨服务器确认、预填逻辑迟早会分叉。
///
/// [notice] 非空时在推页面前弹一次提示。画廊用它说明
/// 「再次运行会用当时的工作流重新生成，不保证与这张完全一致」——
/// 不让用户以为点一下就能得到同一张。
Future<void> runTaskAgain(
  BuildContext context,
  WidgetRef ref,
  TaskHistory task, {
  String? notice,
}) async {
  final l = AppLocalizations.of(context);
  final snapshotId = task.snapshotId;

  if (snapshotId == null) {
    _toast(context, l.historyNoSnapshot);
    return;
  }

  final snapshot = ref.read(snapshotProvider.notifier).byId(snapshotId);
  if (snapshot == null) {
    _toast(context, l.historySnapshotDeleted);
    return;
  }

  // 服务器一致性：环境不同，模型/节点可能缺失，先让用户知情
  final config = ref.read(connectionProvider);
  final currentId = config.activeServerId;
  if (task.serverId != currentId) {
    String nameOf(String? id) {
      if (id == null) return l.historyUnknownServer;
      for (final s in config.servers) {
        if (s.id == id) return s.name;
      }
      return l.historyUnknownServer;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.historyServerMismatchTitle),
        content: Text(
          l.historyServerMismatchBody(nameOf(task.serverId), nameOf(currentId)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.historyRunAnyway),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
  }

  if (!context.mounted) return;
  if (notice != null && notice.isNotEmpty) {
    _toast(context, notice);
  }
  await Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => RunView(
        workflowId: task.workflowId,
        snapshotId: snapshotId,
        initialParams: task.params,
      ),
    ),
  );
}

void _toast(BuildContext context, String text) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}
