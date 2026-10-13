import 'package:comfyui_mobilepocket/l10n/app_localizations.dart';

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

  /// 浏览器下载地址（仅公开仓库可直接使用）
  final String downloadUrl;

  /// API 资产地址（形如 /repos/{owner}/{repo}/releases/assets/{id}）。
  /// 私有仓库必须走这里并携带令牌，配合 Accept: application/octet-stream。
  final String assetApiUrl;

  const ReleaseInfo({
    required this.version,
    required this.tagName,
    required this.name,
    required this.notes,
    required this.publishedAt,
    required this.assetName,
    required this.sizeBytes,
    required this.downloadUrl,
    this.assetApiUrl = '',
  });

  /// 人类可读的包大小，例如 18.4 MB
  String sizeText(AppLocalizations l10n) {
    if (sizeBytes <= 0) return l10n.unknownSize;
    final mb = sizeBytes / (1024 * 1024);
    if (mb >= 1) return '${mb.toStringAsFixed(1)} MB';
    return '${(sizeBytes / 1024).toStringAsFixed(0)} KB';
  }
}
