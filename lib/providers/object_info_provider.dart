import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/object_info_service.dart';

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

  final Map<String, Map<String, NodeSpec>> byServer;

  /// 该服务器的这个节点是否已经问过（问过但空的也算问过）。
  ///
  /// 「问过」与「问到了」是两回事：问过但没问到，意味着服务器不认识这个节点，
  /// 这时候绝不能反过来判定「服务器上没有这个模型」。
  bool hasNode(String serverId, String classType) =>
      (byServer[serverId]?[classType]) != null;

  /// 取参数定义；没问过或没这个参数时返回 null。
  NodeInputSpec? specFor(String serverId, String classType, String key) =>
      byServer[serverId]?[classType]?[key];

  ObjectInfoState _withNode(String serverId, String classType, NodeSpec spec) {
    final server = Map<String, NodeSpec>.from(byServer[serverId] ?? const {});
    server[classType] = spec;
    return ObjectInfoState(
      byServer: Map<String, Map<String, NodeSpec>>.from(byServer)
        ..[serverId] = server,
    );
  }

  ObjectInfoState _withoutServer(String serverId) => ObjectInfoState(
    byServer: Map<String, Map<String, NodeSpec>>.from(byServer)
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

  /// 补齐缺失的节点说明书。已经在缓存里的不重复请求。
  ///
  /// 返回是否**全部**都问到了定义（拿到空定义算没问到）。
  /// 拿不到的一律静默 —— 说明书是加分项，不是必需品。
  Future<bool> ensureLoaded({
    required String serverId,
    required String baseUrl,
    required Iterable<String> classTypes,
  }) async {
    final todo = <String>[];
    for (final classType in classTypes) {
      if (classType.isEmpty) continue;
      if (state.hasNode(serverId, classType)) continue;
      final k = _key(serverId, classType);
      if (_inFlight.contains(k)) continue;
      _inFlight.add(k);
      todo.add(classType);
    }
    if (todo.isEmpty) return true;

    var allResolved = true;
    for (var i = 0; i < todo.length; i += _maxConcurrent) {
      final batch = todo.skip(i).take(_maxConcurrent).toList();
      final specs = await Future.wait(
        batch.map(
          (classType) =>
              ObjectInfoService.instance.fetchNodeSpec(baseUrl, classType),
        ),
      );
      for (var j = 0; j < batch.length; j++) {
        final classType = batch[j];
        _inFlight.remove(_key(serverId, classType));
        if (specs[j].isEmpty) allResolved = false;
        // 空的也写进去：否则下次进页面会再问一遍，白等一次超时。
        state = state._withNode(serverId, classType, specs[j]);
      }
    }
    return allResolved;
  }

  /// 丢弃这台服务器的全部缓存并重新取一遍（刷新入口用）。
  Future<bool> refresh({
    required String serverId,
    required String baseUrl,
    required Iterable<String> classTypes,
  }) {
    state = state._withoutServer(serverId);
    _inFlight.removeWhere((k) => k.startsWith('$serverId|'));
    return ensureLoaded(
      serverId: serverId,
      baseUrl: baseUrl,
      classTypes: classTypes,
    );
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
