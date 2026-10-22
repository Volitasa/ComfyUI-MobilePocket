import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/object_info_service.dart';

/// 一个节点的一次取数结果：**说明书 + 它是怎么来的**。
///
/// ⚠️ `spec` 单独存不下来三态 —— `failure`（断网 / 超时）与 `empty`
/// （服务器 200 返回 `{}`，即不认识这个节点）拿到的都是一张空 Map。
/// 方案 §3.7 对这两种情况的处理**相反**（前者不拦、后者拦），
/// 所以状态必须跟着说明书一起存，否则两态在 provider 层又被抹平。
class NodeSpecEntry {
  const NodeSpecEntry({required this.spec, required this.status});

  final NodeSpec spec;
  final ObjectInfoFetchStatus status;

  /// 没取到（断网 / 超时 / 非 200）—— 我们**不知道**服务器认不认识这个节点。
  bool get isFailure => status == ObjectInfoFetchStatus.failure;

  /// 服务器明确说不认识这个节点（200 + `{}`）。
  bool get isMissingOnServer => status == ObjectInfoFetchStatus.empty;
}

/// 节点说明书缓存：服务器 → 类名 → 参数名 → 定义。
///
/// ⚠️ **只放内存，不落盘。** 实测一个 `LoadImage.image` 就是 139 项文件名，
/// 写进配置会让本地数据肉眼可见地膨胀；而且模型会增删，存着就是存了一堆
/// 过期的东西。
///
/// 按服务器 id 分桶：切换/删除连接后自动用到另一个桶，不会串台显示
/// 上一台服务器上的模型。
class ObjectInfoState {
  const ObjectInfoState({this.byServer = const {}});

  final Map<String, Map<String, NodeSpecEntry>> byServer;

  /// 该服务器的这个节点是否已经问过（问过但空的也算问过）。
  ///
  /// 「问过」与「问到了」是两回事：问过但没问到，意味着服务器不认识这个节点，
  /// 这时候绝不能反过来判定「服务器上没有这个模型」。
  bool hasNode(String serverId, String classType) =>
      byServer[serverId]?[classType] != null;

  /// 这个节点的取数是**怎么**来的；null 表示还没问过。
  ///
  /// 提交前检查靠它区分「缺节点（拦）」与「取数失败（不拦）」（方案 §3.7）。
  ObjectInfoFetchStatus? statusFor(String serverId, String classType) =>
      byServer[serverId]?[classType]?.status;

  /// 取参数定义；没问过或没这个参数时返回 null。
  NodeInputSpec? specFor(String serverId, String classType, String key) =>
      byServer[serverId]?[classType]?.spec[key];

  ObjectInfoState _withNode(
    String serverId,
    String classType,
    NodeSpecEntry entry,
  ) {
    final server = Map<String, NodeSpecEntry>.from(
      byServer[serverId] ?? const {},
    );
    server[classType] = entry;
    return ObjectInfoState(
      byServer: Map<String, Map<String, NodeSpecEntry>>.from(byServer)
        ..[serverId] = server,
    );
  }

  ObjectInfoState _withoutServer(String serverId) => ObjectInfoState(
    byServer: Map<String, Map<String, NodeSpecEntry>>.from(byServer)
      ..remove(serverId),
  );
}

class ObjectInfoNotifier extends Notifier<ObjectInfoState> {
  /// 正在飞的请求。不进 state —— 它只是去重用的瞬时标记，
  /// 放进响应式状态会让每次请求都触发一次多余的重建。
  final Set<String> _inFlight = {};

  /// 一次最多同时发几个请求。
  ///
  /// 通常一个工作流就该拿到 1~3 个节点，但保不齐有人勾了满屏模型。
  /// 不做无上限并发（首页刷状态那次就是这么把上百请求一起打出去的）。
  static const int _maxConcurrent = 4;

  @override
  ObjectInfoState build() => const ObjectInfoState();

  static String _key(String serverId, String classType) =>
      '$serverId|$classType';

  /// 补齐缺失的节点说明书。**已经问到过的不重复请求。**
  ///
  /// 返回是否**全部**都问到了定义（拿到空定义算没问到）。
  /// 拿不到的一律静默 —— 说明书是加分项，不是必需品。
  ///
  /// ⚠️ 「问到过」只认 `ok` / `empty`（服务器给了答案，哪怕答案是「不认识这个节点」）。
  /// **`failure` 不算答案**：断网 / 超时是暂时的，网络恢复后应该重试。
  /// 早先的实现用 `hasNode()` 判，把 failure 也算成「问过」—— 结果一次断网就会让
  /// 配置页在整个会话里一直显示「未获取到服务器节点信息」，用户只能重启 App
  /// 才能恢复（2026-10-23 修）。
  Future<bool> ensureLoaded({
    required String serverId,
    required String baseUrl,
    required Iterable<String> classTypes,
  }) async {
    final todo = <String>[];
    for (final classType in classTypes) {
      if (classType.isEmpty) continue;
      final status = state.statusFor(serverId, classType);
      if (status != null && status != ObjectInfoFetchStatus.failure) continue;
      final k = _key(serverId, classType);
      if (_inFlight.contains(k)) continue;
      _inFlight.add(k);
      todo.add(classType);
    }
    if (todo.isEmpty) return true;

    var allResolved = true;
    for (var i = 0; i < todo.length; i += _maxConcurrent) {
      final batch = todo.skip(i).take(_maxConcurrent).toList();
      final results = await Future.wait(
        batch.map(
          (classType) =>
              ObjectInfoService.instance.fetchNodeSpec(baseUrl, classType),
        ),
      );
      for (var j = 0; j < batch.length; j++) {
        final classType = batch[j];
        _inFlight.remove(_key(serverId, classType));
        if (!results[j].hasSpec) allResolved = false;
        // 空的也写进去：否则下次进页面会再问一遍，白等一次超时。
        // 但**状态要一起写**，否则「取数失败」与「服务器不认识」就分不开了。
        state = state._withNode(
          serverId,
          classType,
          NodeSpecEntry(spec: results[j].spec, status: results[j].status),
        );
      }
    }
    return allResolved;
  }

  /// **写入式刷新**：不管缓存里有没有，都重取一遍并直接覆盖。
  ///
  /// 与 [ensureLoaded]（补缺式，已缓存就跳过）和 [refresh]（先清整桶再取）
  /// 的区别是：这里全程**不出现空档**。
  ///
  /// ⚠️ 刷新候选值/范围一律用这个。**不要**改成「先清桶再取」—— 那样首帧的
  /// 完整选项会先缩成「只剩当前值」再涨回去，观感上闪一下（方案 §3.5）。
  /// （原来有个 `refresh()` 就是这种写法，run 页改用本方法后它已无调用方，已删。）
  Future<bool> refreshInPlace({
    required String serverId,
    required String baseUrl,
    required Iterable<String> classTypes,
  }) async {
    final todo = classTypes.where((t) => t.isNotEmpty).toList();
    if (todo.isEmpty) return true;

    var allResolved = true;
    for (var i = 0; i < todo.length; i += _maxConcurrent) {
      final batch = todo.skip(i).take(_maxConcurrent).toList();
      final results = await Future.wait(
        batch.map(
          (classType) =>
              ObjectInfoService.instance.fetchNodeSpec(baseUrl, classType),
        ),
      );
      for (var j = 0; j < batch.length; j++) {
        final classType = batch[j];
        if (!results[j].hasSpec) allResolved = false;
        // 覆盖写入，不预清桶 —— 全程不出现「没有选项」的中间态。
        state = state._withNode(
          serverId,
          classType,
          NodeSpecEntry(spec: results[j].spec, status: results[j].status),
        );
      }
    }
    return allResolved;
  }

  /// 删除服务器连接时连带清掉它的缓存。
  void clearServer(String serverId) {
    state = state._withoutServer(serverId);
    _inFlight.removeWhere((k) => k.startsWith('$serverId|'));
  }
}

final objectInfoProvider =
    NotifierProvider<ObjectInfoNotifier, ObjectInfoState>(() {
      return ObjectInfoNotifier();
    });
