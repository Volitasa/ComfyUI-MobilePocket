import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/ai_provider_config.dart';
import 'shared_preferences_provider.dart';

/// AI 供应商配置的存储键。
///
/// ⚠️ 里面含 `apiKey`（明文，与 `comfy_github_token` 同规格）。
/// 只随请求发往用户填写的 baseUrl，不写日志、不进异常文案、不上报。
const String kAiSettingsPrefsKey = 'comfy_ai_providers';

/// 解码。坏数据一律退回空配置，不要把整页搞崩。
AiSettings decodeAiSettings(String? raw) {
  if (raw == null || raw.trim().isEmpty) return const AiSettings();
  try {
    final decoded = jsonDecode(raw);
    if (decoded is Map) {
      return AiSettings.fromJson(Map<String, dynamic>.from(decoded));
    }
  } catch (_) {
    // 旧版本 / 手改坏的数据：当作没配置过
  }
  return const AiSettings();
}

String encodeAiSettings(AiSettings settings) => jsonEncode(settings.toJson());

class AiSettingsNotifier extends Notifier<AiSettings> {
  late SharedPreferences _prefs;

  @override
  AiSettings build() {
    _prefs = ref.watch(sharedPreferencesProvider);
    return decodeAiSettings(_prefs.getString(kAiSettingsPrefsKey));
  }

  Future<void> _commit(AiSettings next) async {
    await _prefs.setString(kAiSettingsPrefsKey, encodeAiSettings(next));
    state = next;
  }

  /// 新增或覆盖（按 id 匹配）。新增第一条时自动设为当前。
  Future<void> upsert(AiProviderConfig provider) async {
    final list = [...state.providers];
    final i = list.indexWhere((p) => p.id == provider.id);
    if (i >= 0) {
      list[i] = provider;
    } else {
      list.add(provider);
    }
    final activeId = state.activeId ?? provider.id;
    await _commit(AiSettings(providers: list, activeId: activeId));
  }

  Future<void> remove(String id) async {
    final list = state.providers.where((p) => p.id != id).toList();
    var activeId = state.activeId;
    if (activeId == id) {
      activeId = list.isEmpty ? null : list.first.id;
    }
    await _commit(AiSettings(providers: list, activeId: activeId));
  }

  Future<void> setActive(String id) async {
    await _commit(state.copyWith(activeId: id));
  }
}

final aiSettingsProvider = NotifierProvider<AiSettingsNotifier, AiSettings>(
  AiSettingsNotifier.new,
);
