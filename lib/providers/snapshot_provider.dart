import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/workflow_node.dart';
import '../models/workflow_snapshot.dart';
import '../utils.dart';
import 'connection_provider.dart';

/// 快照持久化键（SharedPreferences）
const String snapshotsPrefsKey = 'comfy_workflow_snapshots';

class SnapshotNotifier extends Notifier<List<WorkflowSnapshot>> {
  late SharedPreferences _prefs;

  @override
  List<WorkflowSnapshot> build() {
    _prefs = ref.watch(sharedPreferencesProvider);
    return _load();
  }

  List<WorkflowSnapshot> _load() {
    final raw = _prefs.getString(snapshotsPrefsKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map((e) => WorkflowSnapshot.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      // 数据损坏时退回空列表，避免整个设置页打不开
      return [];
    }
  }

  void _persist(List<WorkflowSnapshot> list) {
    _prefs.setString(
      snapshotsPrefsKey,
      jsonEncode(list.map((e) => e.toJson()).toList()),
    );
    state = list;
  }

  WorkflowSnapshot? byId(String id) {
    for (final s in state) {
      if (s.id == id) return s;
    }
    return null;
  }

  /// 该快照 id 当前是否真的存在。
  /// 记录里持有 snapshotId 不代表快照还在——可能已被用户手动删除。
  bool exists(String? id) => id != null && byId(id) != null;

  /// 由工作流内容推导快照 id。
  /// 只取 workflowJson，不含节点配置 —— 改暴露配置不能让 id 变，
  /// 否则已存在的生成记录会引用到一个失效的快照。
  static String buildId(Map<String, dynamic> workflowJson) =>
      'snap_${stableHash(jsonEncode(workflowJson)).toRadixString(36)}';

  /// 固化一份快照。
  ///
  /// 同内容（workflowJson 相同）已存在时**复用**已有快照、沿用原创建时间，
  /// 只同步最新的节点配置；否则新建一份。返回快照 id。
  String upsert({
    required Map<String, dynamic> workflowJson,
    required List<WorkflowNode> mappingConfig,
    required String sourceName,
    String? serverId,
  }) {
    final id = buildId(workflowJson);
    final existing = byId(id);
    final now = DateTime.now().millisecondsSinceEpoch;

    if (existing != null) {
      // 复用：保留原 createdAt，只更新配置与来源服务器。
      // 展示名由模型按当前语言推导，这里不再构造（避免固化旧语言文案）。
      final updated = WorkflowSnapshot(
        id: id,
        sourceName: existing.sourceName,
        createdAt: existing.createdAt,
        serverId: serverId ?? existing.serverId,
        workflowJson: existing.workflowJson,
        mappingConfig: mappingConfig,
      );
      _persist(state.map((s) => s.id == id ? updated : s).toList());
      return id;
    }

    final snapshot = WorkflowSnapshot(
      id: id,
      sourceName: sourceName,
      createdAt: now,
      serverId: serverId,
      workflowJson: Map<String, dynamic>.from(workflowJson),
      mappingConfig: mappingConfig,
    );
    _persist([snapshot, ...state]);
    return id;
  }

  /// 更新快照的节点暴露配置（不改动 id 与创建时间）
  void updateMappingConfig(String id, List<WorkflowNode> config) {
    final existing = byId(id);
    if (existing == null) return;
    final updated = WorkflowSnapshot(
      id: existing.id,
      sourceName: existing.sourceName,
      createdAt: existing.createdAt,
      serverId: existing.serverId,
      workflowJson: existing.workflowJson,
      mappingConfig: config,
    );
    _persist(state.map((s) => s.id == id ? updated : s).toList());
  }

  void remove(String id) {
    _persist(state.where((s) => s.id != id).toList());
  }
}

final snapshotProvider =
    NotifierProvider<SnapshotNotifier, List<WorkflowSnapshot>>(() {
      return SnapshotNotifier();
    });
