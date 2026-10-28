/// 图片参数的值到底指向哪个目录的哪张图。
///
/// ComfyUI 的 `LoadImage.image` 是一个字符串，三种合法写法：
/// - `x.png`                       —— 相对 input 目录（工作流里最常见）
/// - `2026-10-28/x.png`            —— input 下的子目录
/// - `ComfyUI_00001_.png [output]` —— 带目录注解，官方 `annotated_filepath` 认这种，
///   引用输出图不用复制、也不用装插件
///
/// 所以「值 → 图片位置」必须解析出来，而不是像早期那样把 type 写死成 input：
/// 用户从输出目录挑的图会被拼成 `type=input` 的预览地址，直接 404。
library;

class ImageRef {
  const ImageRef({
    required this.filename,
    this.subfolder = '',
    this.type = kDefaultImageType,
  }) : assert(filename != ''),
       assert(type == 'input' || type == 'output' || type == 'temp');

  final String filename;
  final String subfolder;

  /// `input` / `output` / `temp`
  final String type;

  /// 提交给 ComfyUI 的完整值（带注解，避免服务端再猜一次目录）
  String get value => buildImageRef(
    filename: filename,
    subfolder: subfolder,
    type: type,
  );

  /// 只看文件名，用于展示与排序
  String get displayName => filename;

  @override
  bool operator ==(Object other) =>
      other is ImageRef &&
      other.filename == filename &&
      other.subfolder == subfolder &&
      other.type == type;

  @override
  int get hashCode => Object.hash(filename, subfolder, type);

  @override
  String toString() => value;
}

/// 工作流里的裸文件名默认落在 input 目录 —— 这是 ComfyUI 自己的约定，
/// 不是我们猜的（见官方 `folder_paths.get_annotated_filepath`）。
const String kDefaultImageType = 'input';

/// 允许在选图页出现的图片扩展名。
const Set<String> kImageExtensions = {
  'png',
  'jpg',
  'jpeg',
  'webp',
  'bmp',
};

final RegExp _annotation = RegExp(
  r'^(.*?)\s*\[(input|output|temp)\]$',
  caseSensitive: false,
);

/// 把工作流里的字符串解析成 [ImageRef]；空串 / 只剩空壳时返回 null。
ImageRef? parseImageRef(String raw) {
  var s = raw.trim();
  if (s.isEmpty) return null;

  var type = kDefaultImageType;
  final m = _annotation.firstMatch(s);
  if (m != null) {
    s = m.group(1)!.trim();
    type = m.group(2)!.toLowerCase();
  }
  if (s.isEmpty) return null;

  // Windows 服务器上偶尔会回带反斜杠的路径
  s = s.replaceAll('\\', '/');
  final slash = s.lastIndexOf('/');
  final filename = slash >= 0 ? s.substring(slash + 1) : s;
  final subfolder = slash >= 0 ? s.substring(0, slash) : '';
  if (filename.isEmpty) return null;

  return ImageRef(filename: filename, subfolder: subfolder, type: type);
}

/// 拼回 ComfyUI 认的带注解字符串。
String buildImageRef({
  required String filename,
  String subfolder = '',
  String type = kDefaultImageType,
}) {
  final path = subfolder.isEmpty ? filename : '$subfolder/$filename';
  return '$path [$type]';
}

/// 选图页里要过滤掉非图片：目录里还躺着 `_output_images_will_be_put_here` 这种占位文件。
bool isImageFilename(String name) {
  final dot = name.lastIndexOf('.');
  if (dot < 0 || dot == name.length - 1) return false;
  return kImageExtensions.contains(name.substring(dot + 1).toLowerCase());
}

/// 预览地址。/view 认 `filename` + `subfolder` + `type`，
/// 传 [preview]（如 `webp;75`）可以让服务端转码成小图，省 90% 以上流量。
String imageViewUrl(
  String baseUrl,
  ImageRef ref, {
  String? preview,
}) {
  final buf = StringBuffer(baseUrl)
    ..write('/view?filename=')
    ..write(Uri.encodeComponent(ref.filename));
  if (ref.subfolder.isNotEmpty) {
    buf
      ..write('&subfolder=')
      ..write(Uri.encodeComponent(ref.subfolder));
  }
  buf.write('&type=${ref.type}');
  if (preview != null && preview.isNotEmpty) {
    buf
      ..write('&preview=')
      ..write(Uri.encodeComponent(preview));
  }
  return buf.toString();
}
