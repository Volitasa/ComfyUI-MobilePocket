import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 守护：`initState` 期间不能依赖 InheritedWidget（Localizations 也算）。
///
/// 背景：UI 工作流解析页曾在 `initState` 里调 `AppLocalizations.of(context)`，
/// 点「解析」直接红屏——`dependOnInheritedWidgetOfExactType` 在 initState
/// 完成前被调用会抛断言。这类问题编译期不报错、静态分析也不报，只有真的走到
/// 那条路径才崩，所以用扫描兜住。
///
/// 允许的写法：`didChangeDependencies`（配一次性标记），或在 build 里取。
/// 异步回调（`onMessageReceived`、`Timer` 闭包）在方法体里属于嵌套层级，不算违规。
void main() {
  test('initState 方法体顶层不取 AppLocalizations', () {
    final offenders = <String>[];

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final lines = entity.readAsLinesSync();

      for (var i = 0; i < lines.length; i++) {
        if (!lines[i].contains('void initState()')) continue;

        var depth = 0;
        var started = false;

        for (var j = i; j < lines.length && j < i + 80; j++) {
          final line = lines[j];
          if (started && depth <= 0) break;

          // 只在方法体顶层（depth == 1）判定；嵌套闭包是异步回调，合法
          if (started &&
              depth == 1 &&
              line.contains('AppLocalizations.of(context)')) {
            offenders.add('${entity.path}:${j + 1}  ${line.trim()}');
          }

          for (final ch in line.split('')) {
            if (ch == '{') {
              depth++;
              started = true;
            } else if (ch == '}') {
              depth--;
            }
          }
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: '以下位置在 initState 里依赖了 InheritedWidget，'
          '请移到 didChangeDependencies（配一次性标记）或在 build 里取：\n'
          '${offenders.join('\n')}',
    );
  });
}
