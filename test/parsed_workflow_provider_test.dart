import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:comfyui_mobilepocket/providers/connection_provider.dart';
import 'package:comfyui_mobilepocket/providers/local_workflow_provider.dart';
import 'package:comfyui_mobilepocket/providers/parsed_workflow_provider.dart';
import 'package:comfyui_mobilepocket/services/workflow_api_converter.dart';
import 'package:comfyui_mobilepocket/utils.dart';

Future<SharedPreferences> _prefsWith([Map<String, Object>? values]) async {
  SharedPreferences.setMockInitialValues(values ?? {});
  return SharedPreferences.getInstance();
}

ProviderContainer _container(SharedPreferences prefs) => ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );

Map<String, dynamic> _parsedJson() => {
      '3': {
        'inputs': {'seed': 1},
        'class_type': 'KSampler',
      },
    };

void main() {
  group('解析缓存 id', () {
    test('同一服务器同一文件永远推导出同一条', () {
      expect(ParsedWorkflowNotifier.buildId('srv1', 'a.json'),
          ParsedWorkflowNotifier.buildId('srv1', 'a.json'));
    });

    test('不同文件或不同服务器互不冲突', () {
      expect(ParsedWorkflowNotifier.buildId('srv1', 'a.json'),
          isNot(ParsedWorkflowNotifier.buildId('srv1', 'b.json')));
      expect(ParsedWorkflowNotifier.buildId('srv1', 'a.json'),
          isNot(ParsedWorkflowNotifier.buildId('srv2', 'a.json')));
    });
  });

  test('解析结果写入后可读回，并能按服务器+文件定位', () async {
    final prefs = await _prefsWith();
    final container = _container(prefs);
    addTearDown(container.dispose);

    final id = container.read(parsedWorkflowProvider.notifier).upsert(
          serverId: 'srv1',
          filename: '基础文生图.json',
          name: '基础文生图',
          sourceHash: 'hash1',
          workflowJson: _parsedJson(),
        );

    expect(id, startsWith('parsed_'));
    final cached = container.read(parsedWorkflowProvider.notifier).byId(id);
    expect(cached!.name, '基础文生图');
    expect(cached.workflowJson['3']['class_type'], 'KSampler');
    // 列表页就是靠这个定位缓存的
    expect(
      container
          .read(parsedWorkflowProvider.notifier)
          .byServerFile('srv1', '基础文生图.json'),
      isNotNull,
    );
    expect(
      container
          .read(parsedWorkflowProvider.notifier)
          .byServerFile('srv2', '基础文生图.json'),
      isNull,
    );
  });

  test('重启后解析缓存依然在（不是一次性会话）', () async {
    final prefs = await _prefsWith();
    final first = _container(prefs);
    addTearDown(first.dispose);

    first.read(parsedWorkflowProvider.notifier).upsert(
          serverId: 'srv1',
          filename: 'a.json',
          name: 'a',
          sourceHash: 'h',
          workflowJson: _parsedJson(),
        );

    final restarted = _container(prefs);
    addTearDown(restarted.dispose);

    expect(restarted.read(parsedWorkflowProvider).length, 1);
    expect(restarted.read(parsedWorkflowProvider).first.name, 'a');
  });

  test('载入时丢弃形态不对的坏缓存（历史版本取错过字段），不污染列表', () async {
    // 模拟旧版本把 UI 图存进了缓存
    final badEntry = {
      'id': 'parsed_bad',
      'serverId': 'srv1',
      'filename': 'bad.json',
      'name': 'bad',
      'sourceHash': 'h',
      'parsedAt': 0,
      'workflowJson': {
        'nodes': [
          {'id': 3, 'type': 'KSampler'}
        ],
        'links': <Object>[],
      },
    };
    final goodEntry = {
      'id': 'parsed_good',
      'serverId': 'srv1',
      'filename': 'good.json',
      'name': 'good',
      'sourceHash': 'h',
      'parsedAt': 0,
      'workflowJson': _parsedJson(),
    };
    final prefs = await _prefsWith({
      parsedWorkflowsPrefsKey: jsonEncode([badEntry, goodEntry]),
    });
    final container = _container(prefs);
    addTearDown(container.dispose);

    final list = container.read(parsedWorkflowProvider);
    expect(list.length, 1);
    expect(list.first.id, 'parsed_good');
  });

  test('重复解析同一来源覆盖而不是堆积', () async {
    final prefs = await _prefsWith();
    final container = _container(prefs);
    addTearDown(container.dispose);
    final notifier = container.read(parsedWorkflowProvider.notifier);

    for (final hash in ['hash1', 'hash2']) {
      notifier.upsert(
        serverId: 'srv1',
        filename: 'a.json',
        name: 'a',
        sourceHash: hash,
        workflowJson: _parsedJson(),
      );
    }

    expect(container.read(parsedWorkflowProvider).length, 1);
    expect(container.read(parsedWorkflowProvider).first.sourceHash, 'hash2');
  });

  test('清除后回到未解析状态', () async {
    final prefs = await _prefsWith();
    final container = _container(prefs);
    addTearDown(container.dispose);
    final notifier = container.read(parsedWorkflowProvider.notifier);

    final id = notifier.upsert(
      serverId: 'srv1',
      filename: 'a.json',
      name: 'a',
      sourceHash: 'h',
      workflowJson: _parsedJson(),
    );
    notifier.remove(id);

    expect(container.read(parsedWorkflowProvider), isEmpty);
    expect(prefs.getString(parsedWorkflowsPrefsKey), '[]');
  });

  test('服务器连接被移除时连带清理，避免孤儿堆积', () async {
    final prefs = await _prefsWith();
    final container = _container(prefs);
    addTearDown(container.dispose);
    final notifier = container.read(parsedWorkflowProvider.notifier);

    notifier.upsert(
      serverId: 'srv1',
      filename: 'a.json',
      name: 'a',
      sourceHash: 'h',
      workflowJson: _parsedJson(),
    );
    notifier.upsert(
      serverId: 'srv1',
      filename: 'b.json',
      name: 'b',
      sourceHash: 'h',
      workflowJson: _parsedJson(),
    );
    notifier.upsert(
      serverId: 'srv2',
      filename: 'c.json',
      name: 'c',
      sourceHash: 'h',
      workflowJson: _parsedJson(),
    );

    notifier.removeByServer('srv1');

    final left = container.read(parsedWorkflowProvider);
    expect(left.length, 1);
    expect(left.first.serverId, 'srv2');
  });

  test('占用字节数按 UTF-8 实际长度计算', () async {
    final prefs = await _prefsWith();
    final container = _container(prefs);
    addTearDown(container.dispose);
    final notifier = container.read(parsedWorkflowProvider.notifier);

    notifier.upsert(
      serverId: 'srv1',
      filename: '中文名.json',
      name: '中文名',
      sourceHash: 'h',
      workflowJson: {'note': '中文内容'},
    );

    final entry = container.read(parsedWorkflowProvider).first;
    expect(entry.sizeBytes, utf8.encode(jsonEncode(entry.workflowJson)).length);
    expect(notifier.totalBytes, entry.sizeBytes);
  });

  test('展示名跟随服务器文件名，而不是哈希 ID', () async {
    final prefs = await _prefsWith();
    final container = _container(prefs);
    addTearDown(container.dispose);

    final id = container.read(parsedWorkflowProvider.notifier).upsert(
          serverId: 'srv1',
          filename: '基础文生图.json',
          name: '基础文生图',
          sourceHash: 'h',
          workflowJson: _parsedJson(),
        );

    expect(
      resolveWorkflowName(container.read(knownWorkflowEntriesProvider), id),
      '基础文生图',
    );
  });

  test('UI 内容变了则指纹变了（列表页据此判断有更新）', () {
    final before = '{"nodes":[]}';
    final after = '{"nodes":[{"id":1}]}';

    expect(WorkflowApiConverter.sourceHashOf(before),
        isNot(WorkflowApiConverter.sourceHashOf(after)));
  });
}
