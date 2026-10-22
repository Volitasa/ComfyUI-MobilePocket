import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/workflow_node.dart';
import '../services/workflow_api_converter.dart';
import '../utils.dart';
import 'connection_provider.dart';
import 'parsed_workflow_provider.dart';

bool isWorkflowFile(String name) => name.endsWith('.json');

/// API 格式工作流（ComfyUI-AutoSaveAPI 生成的 `_api.json`），可直接提交运行
bool isApiWorkflowFile(String name) => name.endsWith('_api.json');

/// UI 格式工作流（ComfyUI 界面保存的 `*.json`），需转换为 API 结构后才能运行
bool isUiWorkflowFile(String name) =>
    isWorkflowFile(name) && !isApiWorkflowFile(name);

/// UI 工作流的解析状态
enum UiWorkflowStatus {
  /// 尚未检测
  unknown,

  /// 没有解析缓存，需要用户手动解析
  unparsed,

  /// 已解析，且与服务器内容一致
  parsed,

  /// 已解析，但服务器内容已变化
  stale,
}

/// 工作流节点配置的当前状态（用于列表上提示是否需要重新配置）
enum WorkflowMappingStatus {
  /// 尚未检测
  unknown,

  /// 没有任何配置
  unconfigured,

  /// 已配置，且服务端内容与配置时一致
  configured,

  /// 已配置，但服务端内容已变化
  stale,
}

class WorkflowState {
  /// API 格式工作流（`_api.json`），可直接提交运行
  final List<String> workflowList;

  /// UI 格式工作流（`*.json` 且非 `_api.json`），需转换为 API 结构后才能运行
  final List<String> uiWorkflowList;

  final bool isLoading;

  /// 正在后台比对各工作流的内容是否变化
  final bool isChecking;
  final Map<String, dynamic>? currentWorkflowData;

  /// currentWorkflowData 所属的工作流 ID。
  /// 用于防止跨工作流复用缓存：切换工作流后必须重新拉取，
  /// 否则会把上一个工作流的图提交出去（会导致服务端报错）。
  final String? currentWorkflowId;

  /// workflowId → 配置状态，由 refreshStatuses 填充
  final Map<String, WorkflowMappingStatus> statuses;

  /// UI 工作流文件名 → 解析状态，由 refreshUiStatuses 填充
  final Map<String, UiWorkflowStatus> uiStatuses;

  WorkflowState({
    this.workflowList = const [],
    this.uiWorkflowList = const [],
    this.isLoading = false,
    this.isChecking = false,
    this.currentWorkflowData,
    this.currentWorkflowId,
    this.statuses = const {},
    this.uiStatuses = const {},
  });

  bool get isEmpty => workflowList.isEmpty && uiWorkflowList.isEmpty;

  /// 指定工作流的数据是否已就绪（数据存在且归属匹配）
  bool hasDataFor(String workflowId) =>
      currentWorkflowData != null && currentWorkflowId == workflowId;

  WorkflowMappingStatus statusOf(String workflowId) =>
      statuses[workflowId] ?? WorkflowMappingStatus.unknown;

  UiWorkflowStatus uiStatusOf(String filename) =>
      uiStatuses[filename] ?? UiWorkflowStatus.unknown;

  WorkflowState copyWith({
    List<String>? workflowList,
    List<String>? uiWorkflowList,
    bool? isLoading,
    bool? isChecking,
    Map<String, dynamic>? currentWorkflowData,
    String? currentWorkflowId,
    Map<String, WorkflowMappingStatus>? statuses,
    Map<String, UiWorkflowStatus>? uiStatuses,
  }) {
    return WorkflowState(
      workflowList: workflowList ?? this.workflowList,
      uiWorkflowList: uiWorkflowList ?? this.uiWorkflowList,
      isLoading: isLoading ?? this.isLoading,
      isChecking: isChecking ?? this.isChecking,
      currentWorkflowData: currentWorkflowData ?? this.currentWorkflowData,
      currentWorkflowId: currentWorkflowId ?? this.currentWorkflowId,
      statuses: statuses ?? this.statuses,
      uiStatuses: uiStatuses ?? this.uiStatuses,
    );
  }
}

class WorkflowNotifier extends Notifier<WorkflowState> {
  late SharedPreferences _prefs;

  @override
  WorkflowState build() {
    _prefs = ref.watch(sharedPreferencesProvider);
    return WorkflowState();
  }

  // 获取线上列表
  Future<void> fetchRemoteList() async {
    final config = ref.read(connectionProvider);
    if (!config.isConnected) return;

    state = state.copyWith(isLoading: true);
    try {
      final uri = Uri.parse('${config.comfyUrl}/userdata?dir=workflows');
      final response = await http.get(uri).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        List<dynamic> filesRaw = decoded is List
            ? decoded
            : (decoded['files'] ?? []);

        final files = filesRaw
            .map((e) => e.toString())
            .where(isWorkflowFile)
            .toList();
        final apiFiles = files.where(isApiWorkflowFile).toList();
        final uiFiles = files.where(isUiWorkflowFile).toList();

        state = state.copyWith(workflowList: apiFiles, uiWorkflowList: uiFiles);

        // 列表就绪后立刻比对内容：API 工作流看配置是否过期，
        // UI 工作流看解析缓存是否过期。两者都只比对哈希，都不需要解析。
        // 这里是服务器返回的完整列表，可以清掉已删除条目的旧状态。
        await refreshStatuses(apiFiles, pruneMissing: true);
        await refreshUiStatuses(uiFiles, pruneMissing: true);
      }
    } catch (e) {
      // 生产环境可接入日志
    } finally {
      state = state.copyWith(isLoading: false);
    }
  }

  /// 逐个拉取工作流内容并比对哈希，判断已保存的配置是否还跟得上服务端。
  ///
  /// 未配置的工作流直接判定，不浪费请求；已配置但拉取失败的保持
  /// 「已配置」，不因网络抖动误报成需要重新配置。
  ///
  /// [pruneMissing] 为 true 表示传进来的 [files] 就是服务器的完整列表，
  /// 结果可以直接替换整张表（顺带清掉已被删除的条目）。
  /// 单条刷新**必须**用默认的 false：合并进现有表。
  /// 以前这里无条件整表替换，于是「点进 A 再返回」这条路径
  /// （只传 [A]）会把 B、C 的状态抹成 unknown —— 列表上显示成「未配置」，
  /// 而其实配置还在、点进去照样能直接运行；「服务器有更新」的提示也会一起丢。
  Future<void> refreshStatuses(
    List<String> files, {
    bool pruneMissing = false,
  }) async {
    final config = ref.read(connectionProvider);
    if (!config.isConnected || files.isEmpty) return;

    state = state.copyWith(isChecking: true);
    final results = <String, WorkflowMappingStatus>{};

    try {
      await Future.wait(
        files.map((filename) async {
          if (!hasMappingConfig(filename)) {
            results[filename] = WorkflowMappingStatus.unconfigured;
            return;
          }

          final data = await _fetchContent(filename);
          if (data == null) {
            results[filename] = WorkflowMappingStatus.configured;
            return;
          }

          final hash = contentHashOf(data);
          final savedHash = getMappingContentHash(filename);
          if (savedHash == null) {
            // 旧配置没有哈希记录，借这次拉取补上，之后就能正常检测
            final nodes = getMappingConfig(filename);
            if (nodes != null) {
              await saveMappingConfig(filename, nodes, contentHash: hash);
            }
            results[filename] = WorkflowMappingStatus.configured;
            return;
          }

          results[filename] = hash == savedHash
              ? WorkflowMappingStatus.configured
              : WorkflowMappingStatus.stale;
        }),
      );
    } finally {
      state = state.copyWith(
        statuses: pruneMissing ? results : {...state.statuses, ...results},
        isChecking: false,
      );
    }
  }

  /// 比对 UI 工作流的解析缓存是否还跟得上服务器。
  ///
  /// **只比对哈希，不解析**——解析要加载整个前端（约 12 MB），
  /// 比对只要拉一份几十 KB 的 JSON，所以刷新时可以批量做。
  /// 未解析的条目没有基线，不参与比对。
  ///
  /// [pruneMissing] 语义与 [refreshStatuses] 相同：只有传完整列表时才替换整张表。
  /// 单条解析完之后那次刷新如果整表替换，其它条目的「服务器有更新」会被
  /// 抹成 unknown —— 界面上退回「已解析」，用户就看不到需要重新解析了。
  Future<void> refreshUiStatuses(
    List<String> files, {
    bool pruneMissing = false,
  }) async {
    final config = ref.read(connectionProvider);
    final serverId = config.activeServerId;
    if (!config.isConnected || serverId == null || files.isEmpty) return;

    state = state.copyWith(isChecking: true);
    final results = <String, UiWorkflowStatus>{};

    try {
      await Future.wait(
        files.map((filename) async {
          final cached = ref
              .read(parsedWorkflowProvider.notifier)
              .byServerFile(serverId, filename);
          if (cached == null) {
            results[filename] = UiWorkflowStatus.unparsed;
            return;
          }

          final text = await fetchWorkflowRawText(filename);
          if (text == null) {
            // 拉取失败不误报成「有更新」
            results[filename] = UiWorkflowStatus.parsed;
            return;
          }

          results[filename] =
              WorkflowApiConverter.sourceHashOf(text) == cached.sourceHash
              ? UiWorkflowStatus.parsed
              : UiWorkflowStatus.stale;
        }),
      );
    } finally {
      state = state.copyWith(
        uiStatuses: pruneMissing ? results : {...state.uiStatuses, ...results},
        isChecking: false,
      );
    }
  }

  /// 拉取工作流文件的原始文本（不做解析）。
  /// 解析缓存的哈希基于原文计算，所以这里必须拿未经 jsonDecode 的字节。
  Future<String?> fetchWorkflowRawText(String filename) async {
    final config = ref.read(connectionProvider);
    try {
      final fileParam = Uri.encodeComponent('workflows/$filename');
      final uri = Uri.parse('${config.comfyUrl}/userdata/$fileParam');
      final response = await http.get(uri).timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) return response.body;
    } catch (e) {
      // 生产环境可接入日志
    }
    return null;
  }

  // 获取单个工作流 JSON 内容（载入时统一归一化，兼容 prompt 包装格式）
  Future<bool> fetchWorkflowContent(String filename) async {
    final data = await _fetchContent(filename);
    if (data == null) return false;
    state = state.copyWith(
      currentWorkflowData: data,
      currentWorkflowId: filename,
    );
    return true;
  }

  /// 拉取工作流内容但**不写入** currentWorkflowData。
  /// 供批量比对等场景使用，避免污染「当前工作流」缓存造成串台。
  Future<Map<String, dynamic>?> fetchWorkflowContentOnly(String filename) =>
      _fetchContent(filename);

  Future<Map<String, dynamic>?> _fetchContent(String filename) async {
    final config = ref.read(connectionProvider);
    try {
      final fileParam = Uri.encodeComponent('workflows/$filename');
      final uri = Uri.parse('${config.comfyUrl}/userdata/$fileParam');
      final response = await http.get(uri).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = Map<String, dynamic>.from(jsonDecode(response.body));
        return normalizeWorkflowJson(data);
      }
    } catch (e) {
      // 生产环境可接入日志
    }
    return null;
  }

  // 直接写入工作流数据并标注归属（本地资产、解析缓存、快照都走这里）。
  // 同样做归一化，保证与线上工作流结构一致。
  void setWorkflowData(
    Map<String, dynamic> data, {
    required String workflowId,
  }) {
    state = state.copyWith(
      currentWorkflowData: normalizeWorkflowJson(data),
      currentWorkflowId: workflowId,
    );
  }

  /// 工作流内容的指纹：基于归一化后的结构，避免包装格式差异造成误判
  static String contentHashOf(Map<String, dynamic> data) =>
      stableHash(jsonEncode(normalizeWorkflowJson(data))).toRadixString(36);

  // 保存节点配置
  Future<void> saveMappingConfig(
    String workflowId,
    List<WorkflowNode> config, {
    String? contentHash,
  }) async {
    final payload = <String, dynamic>{
      'version': 1,
      'contentHash': contentHash,
      'nodes': config.map((e) => e.toJson()).toList(),
    };
    await _prefs.setString('mapping_$workflowId', jsonEncode(payload));
  }

  // 获取已保存的节点配置
  List<WorkflowNode>? getMappingConfig(String workflowId) {
    final payload = _mappingPayload(workflowId);
    if (payload == null) return null;

    final rawNodes = payload['nodes'];
    if (rawNodes is! List) return null;
    try {
      return rawNodes.map((e) => WorkflowNode.fromJson(e)).toList();
    } catch (_) {
      return null;
    }
  }

  /// 配置里记录的内容哈希；旧配置没有该字段时返回 null
  String? getMappingContentHash(String workflowId) {
    final payload = _mappingPayload(workflowId);
    final hash = payload?['contentHash'];
    return hash is String ? hash : null;
  }

  /// 读取配置条目。兼容两种形态：
  /// 新版 `{'version':1,'contentHash':..,'nodes':[...]}`，旧版裸 `[...]`。
  Map<String, dynamic>? _mappingPayload(String workflowId) {
    final dataString = _prefs.getString('mapping_$workflowId');
    if (dataString == null) return null;

    try {
      final decoded = jsonDecode(dataString);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      // 旧格式：裸节点数组，包一层以便统一读取
      if (decoded is List) {
        return <String, dynamic>{
          'version': 0,
          'contentHash': null,
          'nodes': decoded,
        };
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  // 该工作流是否已有映射配置（用于首页判断直接进入运行页还是配置页）
  bool hasMappingConfig(String workflowId) {
    final config = getMappingConfig(workflowId);
    return config != null && config.isNotEmpty;
  }

  /// 删除节点配置（本地工作流被删除时连带清理，避免留下孤儿键）
  Future<void> removeMappingConfig(String workflowId) async {
    await _prefs.remove('mapping_$workflowId');
  }

  // 断开连接/切换服务器时清空列表和选中的缓存数据。
  // 直接构造新 state：copyWith 对 null 参数做合并，无法把字段置回 null。
  void clearList() {
    state = WorkflowState(workflowList: [], currentWorkflowData: null);
  }
}

final workflowProvider = NotifierProvider<WorkflowNotifier, WorkflowState>(() {
  return WorkflowNotifier();
});
