import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 排版规格的回归用例。
///
/// 同一角色在不同页面各写一份是我们反复犯的错：二级页顶栏标题、分组标题
/// 都出现过「三处三种写法」，改一处漏两处。靠人记靠不住，锁在这里。
void main() {
  group('顶栏标题层级', () {
    /// 从一级页钻进去的二级页：配置页 / 参数选择 / 运行 / 解析 + 设置五个子页
    const subPages = <String>[
      'lib/ui/builder/workflow_view.dart',
      'lib/ui/builder/param_picker_view.dart',
      'lib/ui/builder/run_view.dart',
      'lib/ui/builder/workflow_parse_view.dart',
      'lib/ui/settings/server_config_view.dart',
      'lib/ui/settings/github_token_view.dart',
      'lib/ui/settings/snapshot_list_view.dart',
      'lib/ui/settings/workflow_storage_view.dart',
      'lib/ui/settings/about_view.dart',
    ];

    test('二级页顶栏统一用 kSubPageTitleStyle（16 / w600）', () {
      for (final path in subPages) {
        expect(
          File(path).readAsStringSync().contains('kSubPageTitleStyle'),
          isTrue,
          reason: '$path 是二级页，顶栏标题要用 kSubPageTitleStyle，'
              '不能用一级页的大标题加粗',
        );
      }
    });

    test('一级页顶栏仍是系统大标题加粗（别被误改成二级页规格）', () {
      for (final path in <String>[
        'lib/ui/home/home_view.dart',
        'lib/ui/gallery/history_view.dart',
        'lib/ui/gallery/gallery_view.dart',
        'lib/ui/settings/settings_view.dart',
      ]) {
        expect(
          File(path)
              .readAsStringSync()
              .contains('style: const TextStyle(fontWeight: FontWeight.bold)'),
          isTrue,
          reason: '$path 是一级页（底部四个 Tab），顶栏标题应是系统大标题加粗',
        );
      }
    });
  });

  group('分组标题', () {
    const groupTitleOwners = <String>[
      'lib/ui/settings/settings_view.dart',
      'lib/ui/home/remote_workflow_section.dart',
      'lib/ui/settings/workflow_storage_view.dart',
    ];

    test('分组标题共用 SectionTitle 控件，不再各写一份', () {
      for (final path in groupTitleOwners) {
        final text = File(path).readAsStringSync();
        // 锚点必须是**定义处**：`_buildGroupTitle(` 在 build 里还有一堆调用点
        final key = text.contains('class _SectionTitle')
            ? 'class _SectionTitle'
            : 'Widget _buildGroupTitle(';
        final idx = text.indexOf(key);
        expect(idx, greaterThan(-1), reason: '$path 里找不到分组标题的定义');
        final end = idx + 400 > text.length ? text.length : idx + 400;
        expect(
          text.substring(idx, end).contains('SectionTitle('),
          isTrue,
          reason: '$path 的分组标题还在自己写 TextStyle，应改走 SectionTitle',
        );
      }
    });
  });
}
