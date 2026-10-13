import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:comfyui_mobilepocket/services/png_metadata_stripper.dart';

const _sig = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

/// 组装一个 chunk：4 字节长度 + 4 字节类型 + 数据 + 4 字节 CRC。
/// CRC 填 0 即可——剥离逻辑只按类型与长度分块，不校验 CRC。
Uint8List _chunk(String type, List<int> data) {
  final b = BytesBuilder();
  b.add([
    (data.length >> 24) & 0xFF,
    (data.length >> 16) & 0xFF,
    (data.length >> 8) & 0xFF,
    data.length & 0xFF,
  ]);
  b.add(type.codeUnits);
  b.add(data);
  b.add([0, 0, 0, 0]);
  return b.toBytes();
}

String _types(Uint8List png) {
  final types = <String>[];
  var pos = 8;
  while (pos + 8 <= png.length) {
    final len =
        (png[pos] << 24) |
        (png[pos + 1] << 16) |
        (png[pos + 2] << 8) |
        png[pos + 3];
    types.add(String.fromCharCodes(png.sublist(pos + 4, pos + 8)));
    pos += 12 + len;
  }
  return types.join(',');
}

void main() {
  group('PngMetadataStripper', () {
    test('移除 tEXt / iTXt / zTXt 文本块，保留其它块', () {
      final png = Uint8List.fromList([
        ..._sig,
        ..._chunk('IHDR', List.filled(13, 1)),
        ..._chunk('tEXt', 'workflow'.codeUnits),
        ..._chunk('iTXt', 'prompt'.codeUnits),
        ..._chunk('zTXt', 'zdata'.codeUnits),
        ..._chunk('IDAT', [1, 2, 3, 4]),
        ..._chunk('IEND', []),
      ]);

      expect(_types(png), 'IHDR,tEXt,iTXt,zTXt,IDAT,IEND');

      final stripped = PngMetadataStripper.strip(png);
      expect(_types(stripped), 'IHDR,IDAT,IEND');
      expect(stripped.sublist(0, 8), _sig); // 签名保留
    });

    test('无文本块时结构不变', () {
      final png = Uint8List.fromList([
        ..._sig,
        ..._chunk('IHDR', List.filled(13, 1)),
        ..._chunk('IDAT', [9, 9]),
        ..._chunk('IEND', []),
      ]);
      expect(_types(PngMetadataStripper.strip(png)), 'IHDR,IDAT,IEND');
    });

    test('非 PNG 输入原样返回', () {
      final data = Uint8List.fromList([1, 2, 3, 4, 5]);
      expect(PngMetadataStripper.strip(data), data);
    });

    test('长度不足时原样返回', () {
      final data = Uint8List.fromList([0x89, 0x50]);
      expect(PngMetadataStripper.strip(data), data);
    });

    test('结尾残缺时不抛异常，保留已完整解析的部分', () {
      final png = Uint8List.fromList([
        ..._sig,
        ..._chunk('IHDR', List.filled(13, 1)),
        ...[0x00, 0x00, 0x00, 0x63], // 声明了长度但数据不完整
      ]);

      late Uint8List out;
      expect(() => out = PngMetadataStripper.strip(png), returnsNormally);
      expect(out.sublist(0, 8), _sig);
      expect(_types(out), 'IHDR'); // 尾部不完整部分被丢弃，而不是崩溃
    });
  });
}
