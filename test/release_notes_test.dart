import 'package:flutter_test/flutter_test.dart';
import 'package:comfyui_mobilepocket/utils/release_notes.dart';

void main() {
  group('parseReleaseNotes', () {
    test('只有自动生成的 Full Changelog → 正文为空，链接被单独取出', () {
      final n = parseReleaseNotes(
        '**Full Changelog**: https://github.com/Volitasa/ComfyUI-MobilePocket/compare/v1.0.7...v1.0.8',
      );

      expect(n.text, isEmpty);
      expect(
        n.changelogUrl,
        'https://github.com/Volitasa/ComfyUI-MobilePocket/compare/v1.0.7...v1.0.8',
      );
    });

    test('典型自动说明：去掉标题标记、署名与裸链接', () {
      const raw = '''
## What's Changed
* fix: 修好 token 分支 by @Volitasa in https://github.com/Volitasa/ComfyUI-MobilePocket/pull/3
* feat: 工作流快照 by @Volitasa in https://github.com/Volitasa/ComfyUI-MobilePocket/pull/2

**Full Changelog**: https://github.com/Volitasa/ComfyUI-MobilePocket/compare/v1.0.6...v1.0.7
''';

      final n = parseReleaseNotes(raw);

      expect(n.text, contains('What\'s Changed'));
      expect(n.text, contains('· fix: 修好 token 分支'));
      expect(n.text, contains('· feat: 工作流快照'));
      // 署名与链接不该出现在正文里
      expect(n.text, isNot(contains('by @')));
      expect(n.text, isNot(contains('https://')));
      expect(n.text, isNot(contains('Full Changelog')));
      expect(n.changelogUrl, contains('compare/v1.0.6...v1.0.7'));
    });

    test('手写说明原样保留（去掉 markdown 粗体与行内代码标记）', () {
      const raw = '''
本版修复了 **私有仓库更新失败** 的问题。
`设置 → GitHub 访问令牌` 可配置只读令牌。
''';

      final n = parseReleaseNotes(raw);

      expect(n.text, '本版修复了 私有仓库更新失败 的问题。\n设置 → GitHub 访问令牌 可配置只读令牌。');
      expect(n.changelogUrl, isEmpty);
    });

    test('markdown 链接只保留可读文字', () {
      final n = parseReleaseNotes('详见 [更新说明](https://example.com/notes) 一节');

      expect(n.text, '详见 更新说明 一节');
    });

    test('空内容不报错', () {
      expect(parseReleaseNotes('').isEmpty, true);
      expect(parseReleaseNotes('   \n  \n').isEmpty, true);
      expect(parseReleaseNotes('').text, isEmpty);
    });
  });
}
