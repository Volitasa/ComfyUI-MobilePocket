/// GitHub Release 中的一条发布信息（只保留更新功能需要的字段）。
class ReleaseInfo {
  /// 规范化后的版本号，例如 1.2.0
  final String version;

  /// 原始 tag，例如 v1.2.0
  final String tagName;

  /// 发布标题
  final String name;

  /// 更新说明（Release body）
  final String notes;

  final DateTime? publishedAt;

  /// 选中的安装包信息
  final String assetName;
  final int sizeBytes;
  final String downloadUrl;

  const ReleaseInfo({
    required this.version,
    required this.tagName,
    required this.name,
    required this.notes,
    required this.publishedAt,
    required this.assetName,
    required this.sizeBytes,
    required this.downloadUrl,
  });

  /// 人类可读的包大小，例如 18.4 MB
  String get sizeText {
    if (sizeBytes <= 0) return '未知大小';
    final mb = sizeBytes / (1024 * 1024);
    if (mb >= 1) return '${mb.toStringAsFixed(1)} MB';
    return '${(sizeBytes / 1024).toStringAsFixed(0)} KB';
  }
}
