import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/local_workflow.dart';
import '../models/parsed_workflow.dart';
import '../models/workflow_entry.dart';
import '../utils.dart';
import 'connection_provider.dart';
import 'parsed_workflow_provider.dart';
import 'workflow_provider.dart';

/// 本地工作流持久化键（SharedPreferences）
const String localWorkflowsPrefsKey = 'comfy_local_workflows';

/// 本地工作流库：用户导入或另存的工作流资产。
///
/// 与快照、解析缓存都不同——这里的条目**不可再生**，
/// 所以是唯一提供重命名与删除的一类工作流。
class LocalWorkflowNotifier extends Notifier<List<LocalWorkflow>> {
  late SharedPreferences _prefs;

  @override
  List<LocalWorkflow> build() {
    _prefs = ref.watch(sharedPreferencesProvider);
    return _load();
  }

  List<LocalWorkflow> _load() {
    final raw = _prefs.getString(localWorkflowsPrefsKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map((e) => LocalWorkflow.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      // 数据损坏时退回空列表，避免整个页面打不开
      return [];
    }
  }

  void _persist(List<LocalWorkflow> list) {
    _prefs.setString(
      localWorkflowsPrefsKey,
      jsonEncode(list.map((e) => e.toJson()).toList()),
    );
    state = list;
  }

  LocalWorkflow? byId(String id) {
    for (final w in state) {
      if (w.id == id) return w;
    }
    return null;
  }

  /// 总占用字节数
  int get totalBytes => state.fold(0, (sum, w) => sum + w.sizeBytes);

  /// 生成一个不与现有条目冲突的展示名（重名时追加序号）。
  /// [excludeId] 用于排除自己——覆盖保存同一条时不该给自己加序号。
  String uniqueName(String base, {String? excludeId}) {
    final existing = state
        .where((w) => w.id != excludeId)
        .map((w) => w.name)
        .toSet();
    if (!existing.contains(base)) return base;
    var i = 2;
    while (existing.contains('$base ($i)')) {
      i++;
    }
    return '$base ($i)';
  }

  /// 保存一条本地工作流，返回最终使用的 id。
  ///
  /// [id] 可指定：导入流程沿用 `local_<内容哈希>`，
  /// 这样已存在的 `mapping_local_<hash>` 配置能直接复用。
  /// 同名 id 已存在时覆盖。
  String save({
    required String name,
    required Map<String, dynamic> workflowJson,
    required LocalWorkflowSource sourceKind,
    String? originName,
    String? id,
  }) {
    final finalId =
        id ?? 'lw_${stableHash(jsonEncode(workflowJson)).toRadixString(36)}';
    final entry = LocalWorkflow(
      id: finalId,
      name: uniqueName(name, excludeId: finalId),
      createdAt: DateTime.now().millisecondsSinceEpoch,
      sourceKind: sourceKind,
      originName: originName,
      workflowJson: Map<String, dynamic>.from(normalizeWorkflowJson(workflowJson)),
    );

    final exists = byId(finalId) != null;
    final updated = exists
        ? state.map((w) => w.id == finalId ? entry : w).toList()
        : [entry, ...state];
    _persist(updated);
    return finalId;
  }

  void rename(String id, String newName) {
    final name = newName.trim();
    if (name.isEmpty) return;
    final idx = state.indexWhere((w) => w.id == id);
    if (idx == -1) return;
    final updated = List<LocalWorkflow>.from(state);
    updated[idx] = LocalWorkflow(
      id: state[idx].id,
      name: name,
      createdAt: state[idx].createdAt,
      sourceKind: state[idx].sourceKind,
      originName: state[idx].originName,
      workflowJson: state[idx].workflowJson,
    );
    _persist(updated);
  }

  /// 删除本地工作流，连带清除它的节点暴露配置。
  void remove(String id) {
    final updated = state.where((w) => w.id != id).toList();
    if (updated.length == state.length) return;
    _persist(updated);
    // 配置与工作流同生共死，否则会留下永远用不到的孤儿键
    ref.read(workflowProvider.notifier).removeMappingConfig(id);
  }
}

final localWorkflowProvider =
    NotifierProvider<LocalWorkflowNotifier, List<LocalWorkflow>>(() {
  return LocalWorkflowNotifier();
});

/// 本地资产与解析缓存的合集，供展示名解析使用。
/// WidgetRef 不继承 Ref，所以没法做成收 ref 的函数。
List<WorkflowEntry> knownWorkflows(
  List<LocalWorkflow> local,
  List<ParsedWorkflow> parsed,
) =>
    [...local, ...parsed];

/// 参与展示名解析的全部已知条目（本地资产 + 解析缓存）。
/// 比手搓 knownWorkflows 更省事，也不用每个调用点都读两个 provider。
final knownWorkflowEntriesProvider = Provider<List<WorkflowEntry>>((ref) {
  return knownWorkflows(
    ref.watch(localWorkflowProvider),
    ref.watch(parsedWorkflowProvider),
  );
});

/// 取本地持久化的工作流数据：本地资产或解析缓存命中即返回，两者都不请求服务器。
///
/// 返回 null 表示这条 id 归属服务器，需要另行拉取。
/// 收 WidgetRef —— 只有页面层需要它，Notifier 走各自的 provider。
Map<String, dynamic>? persistedWorkflowJson(WidgetRef ref, String workflowId) {
  if (workflowId.startsWith('local_')) {
    return ref.read(localWorkflowProvider.notifier).byId(workflowId)?.workflowJson;
  }
  if (workflowId.startsWith('parsed_')) {
    return ref.read(parsedWorkflowProvider.notifier).byId(workflowId)?.workflowJson;
  }
  return null;
}
