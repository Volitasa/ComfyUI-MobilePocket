/// AI 供应商配置（OpenAI 兼容）。
///
/// "预设"只是这组字段的初值，不是适配器：所有供应商都走
/// `{baseUrl}/chat/completions`，差异只有地址、模型名和密钥。
class AiProviderConfig {
  const AiProviderConfig({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.model,
    this.apiKey = '',
    this.temperature = 0.7,
    this.maxTokens = 1024,
    this.timeoutSec = 60,
  });

  /// 稳定 id：内置预设用固定串，自定义用 `custom_<时间戳>`。
  final String id;
  final String name;
  final String baseUrl;
  final String model;
  final String apiKey;
  final double temperature;
  final int maxTokens;
  final int timeoutSec;

  /// 请求地址：baseUrl 末尾的斜杠会被裁掉，避免出现 `//chat/completions`。
  String get endpoint {
    final base = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    return '$base/chat/completions';
  }

  /// 模型列表地址（只用于「测试连接」，失败不影响保存）。
  String get modelsEndpoint {
    final base = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    return '$base/models';
  }

  bool get isConfigured => apiKey.trim().isNotEmpty && baseUrl.trim().isNotEmpty;

  AiProviderConfig copyWith({
    String? id,
    String? name,
    String? baseUrl,
    String? model,
    String? apiKey,
    double? temperature,
    int? maxTokens,
    int? timeoutSec,
  }) {
    return AiProviderConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      baseUrl: baseUrl ?? this.baseUrl,
      model: model ?? this.model,
      apiKey: apiKey ?? this.apiKey,
      temperature: temperature ?? this.temperature,
      maxTokens: maxTokens ?? this.maxTokens,
      timeoutSec: timeoutSec ?? this.timeoutSec,
    );
  }

  factory AiProviderConfig.fromJson(Map<String, dynamic> json) {
    num asNum(Object? v, num fallback) => v is num ? v : fallback;
    return AiProviderConfig(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      baseUrl: (json['baseUrl'] ?? '').toString(),
      model: (json['model'] ?? '').toString(),
      apiKey: (json['apiKey'] ?? '').toString(),
      temperature: asNum(json['temperature'], 0.7).toDouble(),
      maxTokens: asNum(json['maxTokens'], 1024).toInt(),
      timeoutSec: asNum(json['timeoutSec'], 60).toInt(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'baseUrl': baseUrl,
    'model': model,
    'apiKey': apiKey,
    'temperature': temperature,
    'maxTokens': maxTokens,
    'timeoutSec': timeoutSec,
  };

  /// 内置预设：本期只有 DeepSeek。
  ///
  /// 模型名只是初值，用户随时可改——我们不对"这个账号能不能用视觉"做判断。
  static const AiProviderConfig deepseek = AiProviderConfig(
    id: 'deepseek',
    name: 'DeepSeek',
    baseUrl: 'https://api.deepseek.com',
    model: 'deepseek-chat',
  );

  /// 自定义（本地 Ollama / LM Studio / 任意兼容服务）。
  static AiProviderConfig custom({int now = 0}) => AiProviderConfig(
    id: 'custom_$now',
    name: 'Custom',
    baseUrl: 'http://10.0.2.2:11434/v1',
    model: '',
  );
}

/// 供应商列表 + 当前选中项。整份落一个 prefs 键，便于一次性读写与迁移。
class AiSettings {
  const AiSettings({this.providers = const [], this.activeId});

  final List<AiProviderConfig> providers;
  final String? activeId;

  /// 当前生效的供应商；没配置过或 id 失效时为 null。
  AiProviderConfig? get active {
    for (final p in providers) {
      if (p.id == activeId) return p;
    }
    return null;
  }

  bool get isReady {
    final a = active;
    return a != null && a.isConfigured;
  }

  AiSettings copyWith({List<AiProviderConfig>? providers, String? activeId}) {
    return AiSettings(
      providers: providers ?? this.providers,
      activeId: activeId ?? this.activeId,
    );
  }

  factory AiSettings.fromJson(Map<String, dynamic> json) {
    final raw = json['list'];
    final list = <AiProviderConfig>[];
    if (raw is List) {
      for (final item in raw) {
        if (item is Map) {
          list.add(AiProviderConfig.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }
    return AiSettings(
      providers: list,
      activeId: json['activeId']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'v': 1,
    'list': providers.map((p) => p.toJson()).toList(),
    'activeId': activeId,
  };
}
