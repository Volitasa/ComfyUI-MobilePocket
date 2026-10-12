import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/parsed_workflow.dart';
import '../utils.dart';
import 'connection_provider.dart';

/// 解析缓存持久化键（SharedPreferences）
const String parsedWorkflowsPrefsKey = 'comfy_parsed_workflows';

/// UI 工作流的解析缓存。
///
/// 这里的条目**可再生**（随时能从服务器再解析一次），因此不提供删除，
/// 只提供清除缓存；服务器连接被移除时连带清理，避免留下孤儿。
class ParsedWorkflowNotifier extends Notifier<List<ParsedWorkflow>> {
  late SharedPreferences _prefs;

  @override
  List<ParsedWorkflow> build() {
    _prefs = ref.watch(sharedPreferencesProvider);
    return _load();
  }

  List<ParsedWorkflow> _load() {
    final raw = _prefs.getString(parsedWorkflowsPrefsKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map((e) => ParsedWorkflow.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  void _persist(List<ParsedWorkflow> list) {
    _prefs.setString(
      parsedWorkflowsPrefsKey,
      jsonEncode(list.map((e) => e.toJson()).toList()),
    );
    state = list;
  }

  /// 由服务器与文件名推导缓存 id：同一来源永远命中同一条
  static String buildId(String serverId, String filename) =>
      'parsed_${stableHash('$serverId::$filename').toRadixString(36)}';

  ParsedWorkflow? byId(String id) {
    for (final w in state) {
      if (w.id == id) return w;
    }
    return null;
  }

  ParsedWorkflow? byServerFile(String? serverId, String filename) {
    if (serverId == null) return null;
    return byId(buildId(serverId, filename));
  }

  /// 写入（或覆盖）一条解析结果，返回缓存 id
  String upsert({
    required String serverId,
    required String filename,
    required String name,
    required String sourceHash,
    required Map<String, dynamic> workflowJson,
  }) {
    final id = buildId(serverId, filename);
    final entry = ParsedWorkflow(
      id: id,
      serverId: serverId,
      filename: filename,
      name: name,
      sourceHash: sourceHash,
      parsedAt: DateTime.now().millisecondsSinceEpoch,
      workflowJson: Map<String, dynamic>.from(workflowJson),
    );
    final updated = byId(id) == null
        ? [entry, ...state]
        : state.map((w) => w.id == id ? entry : w).toList();
    _persist(updated);
    return id;
  }

  /// 清除解析缓存：条目回到未解析状态，可随时重新解析
  void remove(String id) {
    final updated = state.where((w) => w.id != id).toList();
    if (updated.length == state.length) return;
    _persist(updated);
  }

  void removeByServerFile(String serverId, String filename) =>
      remove(buildId(serverId, filename));

  /// 服务器连接被移除时清理它名下的全部缓存，避免孤儿堆积
  void removeByServer(String serverId) {
    final updated = state.where((w) => w.serverId != serverId).toList();
    if (updated.length == state.length) return;
    _persist(updated);
  }

  int get totalBytes => state.fold(0, (sum, w) => sum + w.sizeBytes);
}

final parsedWorkflowProvider =
    NotifierProvider<ParsedWorkflowNotifier, List<ParsedWorkflow>>(() {
  return ParsedWorkflowNotifier();
});
