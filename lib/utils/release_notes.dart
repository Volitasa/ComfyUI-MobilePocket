/// GitHub 自动生成（generate_release_notes）的 Release 说明里混着 Markdown
/// 标记、贡献者署名和裸链接，直接当纯文本渲染会很难看（例如会出现
/// `**Full Changelog**: https://…` 这种原文）。这里做保守清洗：
/// 保留人写的描述，去掉标记与自动附带的 changelog 链接。
class ParsedReleaseNotes {
  /// 清洗后的正文，可能为空（说明里只有自动内容时）
  final String text;

  /// 自动附带的「完整变更对比」链接，可能为空
  final String changelogUrl;

  const ParsedReleaseNotes({required this.text, required this.changelogUrl});

  bool get isEmpty => text.isEmpty && changelogUrl.isEmpty;
}

/// `**Full Changelog**: https://github.com/o/r/compare/v1...v2`
final RegExp _fullChangelogRe =
    RegExp(r'^\s*[*_\s]*Full Changelog[*_\s]*:?\s*(\S+)?', caseSensitive: false);

/// commit 行尾的 ` by @someone in https://github.com/...`
final RegExp _byUserInRe = RegExp(
  r'\s+by\s+@[\w-]+\s+in\s+https?://\S+',
  caseSensitive: false,
);

final RegExp _headingRe = RegExp(r'^\s*#{1,6}\s*');
final RegExp _bulletRe = RegExp(r'^\s*[-*+]\s+');
final RegExp _mdLinkRe = RegExp(r'\[([^\]]+)\]\((https?://[^)]+)\)');
final RegExp _boldRe = RegExp(r'\*\*(.+?)\*\*');
final RegExp _inlineCodeRe = RegExp(r'`([^`]+)`');

ParsedReleaseNotes parseReleaseNotes(String raw) {
  if (raw.trim().isEmpty) {
    return const ParsedReleaseNotes(text: '', changelogUrl: '');
  }

  final lines = <String>[];
  var changelogUrl = '';

  for (final original in raw.split('\n')) {
    final full = _fullChangelogRe.firstMatch(original);
    if (full != null) {
      // 自动附带的样板行：正文里不要，但把链接留出来单独展示
      final url = full.group(1);
      if (url != null && url.isNotEmpty) changelogUrl = url;
      continue;
    }

    var line = original
        .replaceAll(_headingRe, '')
        .replaceAll(_bulletRe, '· ')
        .replaceAll(_byUserInRe, '')
        .replaceAllMapped(_mdLinkRe, (m) => m.group(1) ?? '')
        .replaceAllMapped(_boldRe, (m) => m.group(1) ?? '')
        .replaceAllMapped(_inlineCodeRe, (m) => m.group(1) ?? '')
        .trimRight();

    if (line.trim().isEmpty) continue;
    lines.add(line);
  }

  return ParsedReleaseNotes(
    text: lines.join('\n').trim(),
    changelogUrl: changelogUrl,
  );
}
