import '../models/task_history.dart';
import '../models/task_status.dart';
import '../models/workflow_snapshot.dart';
import '../utils.dart';

/// 一条搜索命中结果。
class HistoryHit {
  const HistoryHit({required this.task, this.summary});

  final TaskHistory task;

  /// 命中摘要，形如「正面提示词: …一只猫咪…」。
  ///
  /// 关键词为空、或只靠工作流名命中时为 null —— 名字本身就显示在卡片上，
  /// 再重复一遍是噪音。
  final String? summary;
}

/// 生成记录页的状态筛选。
///
/// 「进行中」把排队与生成合并 —— 对找任务的人来说，两者都还没出结果，
/// 拆成两个标签只会让筛选条变长。
enum HistoryStatusFilter { all, pending, completed, failed, interrupted }

/// 生成记录的关键词搜索。
///
/// 纯函数，不依赖 BuildContext，便于单测。
/// 数据来源全部在本地，50 条的量级直接遍历即可，不需要索引。
class HistorySearch {
  const HistorySearch._();

  /// 该筛选是否放行这个状态。
  static bool passesFilter(HistoryStatusFilter filter, TaskStatus status) =>
      switch (filter) {
        HistoryStatusFilter.all => true,
        HistoryStatusFilter.pending => status.isPending,
        HistoryStatusFilter.completed => status == TaskStatus.completed,
        HistoryStatusFilter.failed => status == TaskStatus.failed,
        HistoryStatusFilter.interrupted => status == TaskStatus.interrupted,
      };

  /// 摘要里关键词两侧各保留的字符数。
  static const int _excerptRadius = 12;

  /// 从 [tasks] 里按顺序挑出命中 [keyword] 的记录。
  ///
  /// - [keyword] 为空（或只有空白）时原样返回全部，summary 一律为 null。
  /// - [displayName] 取展示名：**必须传展示层算出来的那个**。
  ///   旧记录的 title 可能是空串，界面上显示的是按当前语言补出来的默认名，
  ///   比原始 title 会导致切语言后那批记录搜不到。
  /// - [snapshotOf] 用于反查参数别名。快照被删时传 null 或返回 null 都行，
  ///   会降级成只匹配值、不显示别名，**不影响搜索本身**。
  static List<HistoryHit> search(
    List<TaskHistory> tasks,
    String keyword, {
    required String Function(TaskHistory) displayName,
    WorkflowSnapshot? Function(String)? snapshotOf,
  }) {
    final words = _tokenize(keyword);
    if (words.isEmpty) {
      return [for (final t in tasks) HistoryHit(task: t)];
    }

    final hits = <HistoryHit>[];
    for (final task in tasks) {
      // 工作流名命中即可收工：名字就在卡片上，不需要摘要
      if (_matchesAll(displayName(task), words)) {
        hits.add(HistoryHit(task: task));
        continue;
      }

      // 旧记录没存过表单值（10-11 之前），只能按名称搜
      final params = task.params;
      if (params == null) continue;

      final snapshot = task.snapshotId == null
          ? null
          : snapshotOf?.call(task.snapshotId!);

      for (final entry in params.entries) {
        final value = entry.value;
        // 数值不参与：搜「7」命中 cfg=7 / steps=7 没有信息量，纯噪音
        if (value is! String) continue;

        final alias = _aliasOf(snapshot, entry.key);
        // 别名一起搜：搜索「提示词」能命中别名就叫"正面提示词"的参数
        final haystack = alias == null ? value : '$alias $value';
        if (!_matchesAll(haystack, words)) continue;

        hits.add(
          HistoryHit(task: task, summary: _buildSummary(alias, value, words)),
        );
        break; // 一条记录只取第一个命中，卡片上放不下更多
      }
    }
    return hits;
  }

  /// 按空白分词，全部转小写。多个词之间是「与」的关系。
  static List<String> _tokenize(String keyword) {
    final s = keyword.trim().toLowerCase();
    if (s.isEmpty) return const [];
    return s.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  }

  /// 所有词都要命中才算命中。
  ///
  /// 刻意要求落在**同一个字段**里：搜「猫 窗台」应该找出同一段提示词里
  /// 两者都有的记录，而不是正面有猫、负面有窗台的那条。
  static bool _matchesAll(String haystack, List<String> words) {
    final lower = haystack.toLowerCase();
    for (final w in words) {
      if (!lower.contains(w)) return false;
    }
    return true;
  }

  /// 反查参数别名：params 的键是 nodeId:key，快照的 mappingConfig 里有同名节点。
  static String? _aliasOf(WorkflowSnapshot? snapshot, String paramKey) {
    if (snapshot == null) return null;
    for (final node in snapshot.mappingConfig) {
      if (nodeParamKey(node.id, node.key) != paramKey) continue;
      final alias = node.alias.trim();
      return alias.isEmpty ? null : alias;
    }
    return null;
  }

  static String? _buildSummary(
    String? alias,
    String value,
    List<String> words,
  ) {
    // 命中可能来自别名本身（值里没有关键词），这时退化成取值开头
    String? excerpt;
    for (final w in words) {
      excerpt = _excerpt(value, w);
      if (excerpt != null) break;
    }
    excerpt ??= _head(value);
    if (excerpt == null) return null;

    return (alias == null || alias.isEmpty) ? excerpt : '$alias: $excerpt';
  }

  /// 截取关键词两侧的一段，前后按需补省略号。
  static String? _excerpt(String text, String word) {
    final i = text.toLowerCase().indexOf(word.toLowerCase());
    if (i < 0) return null;
    final start = (i - _excerptRadius).clamp(0, text.length);
    final end = (i + word.length + _excerptRadius).clamp(0, text.length);
    var s = text.substring(start, end);
    if (start > 0) s = '…$s';
    if (end < text.length) s = '$s…';
    return s;
  }

  /// 取开头一段（关键词不在值里时用）。
  static String? _head(String text) {
    final t = text.trim();
    if (t.isEmpty) return null;
    const int max = 24;
    return t.length <= max ? t : '${t.substring(0, max)}…';
  }
}
