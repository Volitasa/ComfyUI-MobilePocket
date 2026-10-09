import 'dart:typed_data';

/// PNG 元数据工具：剥离 PNG 里的 tEXt/iTXt/zTXt 元数据块，
/// 用于「保存为普通图片」时移除内嵌的 ComfyUI 工作流信息（不重编码像素）。
class PngMetadataStripper {
  PngMetadataStripper._();

  /// 从 PNG 字节中移除文本类元数据块，返回新字节。
  /// 输入必须是合法 PNG；若格式异常则原样返回（不抛错）。
  static Uint8List strip(Uint8List bytes) {
    // PNG 签名 8 字节
    const signature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
    if (bytes.length < 8) return bytes;
    for (int i = 0; i < 8; i++) {
      if (bytes[i] != signature[i]) return bytes; // 非 PNG，原样返回
    }

    final out = BytesBuilder();
    out.add(bytes.sublist(0, 8)); // 签名

    int pos = 8;
    while (pos + 8 <= bytes.length) {
      // 4 字节长度 + 4 字节类型 + 数据 + 4 字节 CRC
      final length = _readUint32(bytes, pos);
      final typeStart = pos + 4;
      final type = String.fromCharCodes(bytes.sublist(typeStart, typeStart + 4));
      final dataStart = pos + 8;
      final dataEnd = dataStart + length;
      final chunkEnd = dataEnd + 4; // 含 CRC

      if (dataEnd + 4 > bytes.length) return bytes; // 截断，保护性返回

      // 文本类元数据块：tEXt、iTXt、zTXt
      final isTextChunk = type == 'tEXt' || type == 'iTXt' || type == 'zTXt';

      if (!isTextChunk) {
        out.add(bytes.sublist(pos, chunkEnd));
      }

      if (type == 'IEND') break; // 结束块后不再有数据

      pos = chunkEnd;
    }
    return out.toBytes();
  }

  static int _readUint32(Uint8List b, int offset) {
    return (b[offset] << 24) |
        (b[offset + 1] << 16) |
        (b[offset + 2] << 8) |
        b[offset + 3];
  }
}
