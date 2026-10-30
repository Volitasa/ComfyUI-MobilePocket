import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:comfyui_mobilepocket/models/ai_provider_config.dart';
import 'package:comfyui_mobilepocket/providers/ai_settings_provider.dart';
import 'package:comfyui_mobilepocket/providers/shared_preferences_provider.dart';

const deepseek = AiProviderConfig(
  id: 'deepseek_1',
  name: 'DeepSeek',
  baseUrl: 'https://api.deepseek.com',
  model: 'deepseek-chat',
  apiKey: 'sk-1',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('坏数据退回空配置，不抛异常', () {
    expect(decodeAiSettings(null).providers, isEmpty);
    expect(decodeAiSettings('not json').providers, isEmpty);
    expect(decodeAiSettings('{"list":"x"}').providers, isEmpty);
  });

  test('编解码往返保留字段', () {
    const settings = AiSettings(providers: [deepseek], activeId: 'deepseek_1');
    final back = decodeAiSettings(encodeAiSettings(settings));
    expect(back.providers.single.model, 'deepseek-chat');
    expect(back.providers.single.apiKey, 'sk-1');
    expect(back.activeId, 'deepseek_1');
  });

  test('第一条自动成为当前，删除后自动改选', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);

    final notifier = container.read(aiSettingsProvider.notifier);
    await notifier.upsert(deepseek);
    expect(container.read(aiSettingsProvider).activeId, 'deepseek_1');

    final second = deepseek.copyWith(id: 'custom_2', name: 'Custom');
    await notifier.upsert(second);
    expect(container.read(aiSettingsProvider).providers, hasLength(2));
    expect(container.read(aiSettingsProvider).activeId, 'deepseek_1');

    await notifier.remove('deepseek_1');
    expect(container.read(aiSettingsProvider).activeId, 'custom_2');
  });

  test('没有 key 时 isReady 为 false', () {
    final settings = AiSettings(
      providers: [deepseek.copyWith(apiKey: '')],
      activeId: 'deepseek_1',
    );
    expect(settings.isReady, isFalse);
  });

  test('endpoint 去掉末尾斜杠', () {
    expect(
      deepseek.copyWith(baseUrl: 'https://x.test/v1/').endpoint,
      'https://x.test/v1/chat/completions',
    );
  });
}
