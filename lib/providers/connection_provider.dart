import 'dart:convert';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

import 'locale_provider.dart';
// export 不会把符号引入本文件作用域，本文件自己也要用到
import 'shared_preferences_provider.dart';

// 原有引用点（main.dart、各 provider）仍可从本文件拿到 SharedPreferences provider
export 'shared_preferences_provider.dart';

/// 连接探测的结果类型：只说明“发生了什么”，不含任何展示文案。
/// 以前这里直接存整句中文，界面换语言后译不了，
/// 颜色也只能靠在文案里找「不可用」两个字来判断。
enum ConnectionTestKind {
  activatedPrimary, // 启用成功，走的是主地址
  activatedBackup, // 启用成功，走的是备用地址
  activateFailed, // 启用失败：主备都不通
  testPrimaryOk, // 表单内探测：主地址可用
  testBackupOk, // 表单内探测：备用地址可用
  testAllFailed, // 表单内探测：都不可用
  emptyPrimary, // 主地址还没填
}

/// 结构化的连接探测结果。[name] 是需要插进文案的连接名，没有则留空。
class ConnectionTestResult {
  final bool ok;
  final ConnectionTestKind kind;
  final String name;

  const ConnectionTestResult({
    required this.ok,
    required this.kind,
    this.name = '',
  });
}

/// 单个服务器连接配置：支持主/备双地址（适配内外网环境）。
/// 连接时先探测主地址，不通再探测备用地址，哪个通用哪个。
class ServerConfig {
  final String id;
  String name;
  String primaryUrl;
  String backupUrl; // 可为空

  ServerConfig({
    required this.id,
    required this.name,
    required this.primaryUrl,
    this.backupUrl = '',
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'primary': primaryUrl,
    'backup': backupUrl,
  };

  factory ServerConfig.fromJson(Map<String, dynamic> json) => ServerConfig(
    id: json['id'],
    // 旧数据缺失名称时留空，由界面按当前语言补默认名——
    // 不在持久化层写死中文
    name: (json['name'] as String?) ?? '',
    primaryUrl: json['primary'] ?? '',
    backupUrl: json['backup'] ?? '',
  );

  List<String> get urls => [
    primaryUrl,
    if (backupUrl.trim().isNotEmpty) backupUrl,
  ];
}

/// 状态实体
class ConfigState {
  final List<ServerConfig> servers;
  final String? activeServerId; // 当前启用的连接（同时只能一个）
  final String comfyUrl; // 当前生效的 URL（主/备中连通的那个）
  final String clientId;
  final bool isConnected;
  final bool isTesting;
  final ConnectionTestResult? testResult;

  const ConfigState({
    this.servers = const [],
    this.activeServerId,
    this.comfyUrl = 'http://127.0.0.1:8190',
    this.clientId = '',
    this.isConnected = false,
    this.isTesting = false,
    this.testResult,
  });

  ConfigState copyWith({
    List<ServerConfig>? servers,
    String? activeServerId,
    String? comfyUrl,
    String? clientId,
    bool? isConnected,
    bool? isTesting,
    ConnectionTestResult? testResult,
    // 传 null 无法区分“不改”和“清空”，另给一个显式的清除开关
    bool clearTestResult = false,
  }) {
    return ConfigState(
      servers: servers ?? this.servers,
      activeServerId: activeServerId ?? this.activeServerId,
      comfyUrl: comfyUrl ?? this.comfyUrl,
      clientId: clientId ?? this.clientId,
      isConnected: isConnected ?? this.isConnected,
      isTesting: isTesting ?? this.isTesting,
      testResult: clearTestResult ? null : (testResult ?? this.testResult),
    );
  }
}

/// 状态控制器：多连接管理 + 主备地址探测
class ConnectionNotifier extends Notifier<ConfigState> {
  late SharedPreferences _prefs;

  @override
  ConfigState build() {
    _prefs = ref.watch(sharedPreferencesProvider);
    final servers = _loadServers();
    String? activeId = _prefs.getString('comfy_active_server');
    if (servers.isNotEmpty &&
        (activeId == null || !servers.any((s) => s.id == activeId))) {
      activeId = servers.first.id;
    }
    final activeUrl = _prefs.getString('comfyUrl') ?? 'http://127.0.0.1:8190';
    return ConfigState(
      servers: servers,
      activeServerId: activeId,
      comfyUrl: activeUrl,
      clientId: _getOrCreateClientId(),
    );
  }

  // 保证 App 单次运行期间及持久化维度的身份凭证一致性
  String _getOrCreateClientId() {
    String? id = _prefs.getString('comfy_client_id');
    if (id == null) {
      final randomStr = Random().nextInt(9999999).toRadixString(36);
      id = 'mobile_${randomStr}_${DateTime.now().millisecondsSinceEpoch}';
      _prefs.setString('comfy_client_id', id);
    }
    return id;
  }

  // ---------- 服务器列表 CRUD ----------

  List<ServerConfig> _loadServers() {
    final raw = _prefs.getString('comfy_servers');
    if (raw != null) {
      try {
        final list = jsonDecode(raw) as List;
        return list.map((e) => ServerConfig.fromJson(e)).toList();
      } catch (_) {}
    }
    // 旧版本迁移：只有单条 comfyUrl 时转成一条默认服务器，不丢数据
    final legacy = _prefs.getString('comfyUrl');
    if (legacy != null && legacy.isNotEmpty) {
      return [
        ServerConfig(
          id: _newId(),
          name: l10nFor(ref.read(localeProvider)).serverDefaultName,
          primaryUrl: legacy,
        ),
      ];
    }
    return [];
  }

  void _saveServers(List<ServerConfig> servers) {
    _prefs.setString(
      'comfy_servers',
      jsonEncode(servers.map((e) => e.toJson()).toList()),
    );
  }

  String _newId() =>
      'srv_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(9999)}';

  String _cleanUrl(String url) {
    final t = url.trim();
    return t.endsWith('/') ? t.substring(0, t.length - 1) : t;
  }

  Future<void> addServer(String name, String primary, String backup) async {
    final trimmed = name.trim();
    final server = ServerConfig(
      id: _newId(),
      name: trimmed.isEmpty
          ? l10nFor(ref.read(localeProvider))
                .serverDefaultNameWithIndex(state.servers.length + 1)
          : trimmed,
      primaryUrl: _cleanUrl(primary),
      backupUrl: _cleanUrl(backup),
    );
    final servers = [...state.servers, server];
    _saveServers(servers);
    state = state.copyWith(servers: servers);
    // 第一个连接自动启用
    if (state.activeServerId == null) {
      await activateServer(server.id);
    }
  }

  Future<void> updateServer(
    String id,
    String name,
    String primary,
    String backup,
  ) async {
    final servers = state.servers.map((s) {
      if (s.id != id) return s;
      return ServerConfig(
        id: s.id,
        name: name.trim().isEmpty ? s.name : name.trim(),
        primaryUrl: _cleanUrl(primary),
        backupUrl: _cleanUrl(backup),
      );
    }).toList();
    _saveServers(servers);
    state = state.copyWith(servers: servers);
    // 编辑的是启用中的连接时，重新探测并刷新生效地址
    if (state.activeServerId == id) {
      await activateServer(id);
    }
  }

  Future<void> removeServer(String id) async {
    final servers = state.servers.where((s) => s.id != id).toList();
    _saveServers(servers);

    if (state.activeServerId == id) {
      // 移除的是启用中的连接：直接断开（comfyUrl 置空触发 WS 断开与列表清空）
      await _prefs.remove('comfy_active_server');
      await _prefs.remove('comfyUrl');
      state = ConfigState(
        servers: servers,
        activeServerId: null,
        comfyUrl: '',
        clientId: state.clientId,
        isConnected: false,
        isTesting: false,
      );
    } else {
      state = state.copyWith(servers: servers);
    }
  }

  // ---------- 连接探测 ----------

  // 依次探测主/备地址，返回首个连通的 URL
  Future<String?> _probe(ServerConfig server) async {
    for (final url in server.urls) {
      final clean = _cleanUrl(url);
      if (clean.isEmpty) continue;
      try {
        final response = await http
            .get(Uri.parse('$clean/system_stats'))
            .timeout(const Duration(seconds: 4));
        if (response.statusCode == 200) return clean;
      } catch (_) {
        // 尝试下一个地址
      }
    }
    return null;
  }

  // 启用某连接：主/备依次探测，连通者作为生效地址
  Future<void> activateServer(String id) async {
    ServerConfig? server;
    for (final s in state.servers) {
      if (s.id == id) server = s;
    }
    if (server == null) return;

    state = state.copyWith(
      isTesting: true,
      isConnected: false,
      clearTestResult: true,
    );

    final url = await _probe(server);
    if (url == null) {
      state = state.copyWith(
        isTesting: false,
        isConnected: false,
        testResult: ConnectionTestResult(
          ok: false,
          kind: ConnectionTestKind.activateFailed,
          name: server.name,
        ),
      );
      return;
    }

    await _prefs.setString('comfy_active_server', id);
    await _prefs.setString('comfyUrl', url);
    final usedPrimary = url == _cleanUrl(server.primaryUrl);
    state = state.copyWith(
      isTesting: false,
      isConnected: true,
      activeServerId: id,
      comfyUrl: url,
      testResult: ConnectionTestResult(
        ok: true,
        kind: usedPrimary
            ? ConnectionTestKind.activatedPrimary
            : ConnectionTestKind.activatedBackup,
        name: server.name,
      ),
    );
  }

  // 编辑对话框内的双地址测试（不改变启用状态）
  Future<ConnectionTestResult> testUrls(String primary, String backup) async {
    final tmp = ServerConfig(
      id: 'tmp',
      name: 'tmp',
      primaryUrl: primary,
      backupUrl: backup,
    );
    final url = await _probe(tmp);
    if (url == null) {
      return const ConnectionTestResult(
        ok: false,
        kind: ConnectionTestKind.testAllFailed,
      );
    }
    return ConnectionTestResult(
      ok: true,
      kind: url == _cleanUrl(primary)
          ? ConnectionTestKind.testPrimaryOk
          : ConnectionTestKind.testBackupOk,
    );
  }

  // 启动时静默自动连接：先试上次生效的地址（快速路径），失败再走完整主备探测
  Future<void> autoConnect() async {
    if (state.isConnected || state.isTesting) return;
    if (state.activeServerId == null) return;

    final lastUrl = _prefs.getString('comfyUrl');
    if (lastUrl != null && lastUrl.isNotEmpty) {
      try {
        final response = await http
            .get(Uri.parse('$lastUrl/system_stats'))
            .timeout(const Duration(seconds: 5));
        if (response.statusCode == 200) {
          state = state.copyWith(isConnected: true);
          return;
        }
      } catch (_) {
        // 快速路径失败，走完整探测
      }
    }
    await activateServer(state.activeServerId!);
  }
}

final connectionProvider = NotifierProvider<ConnectionNotifier, ConfigState>(
  () {
    return ConnectionNotifier();
  },
);
