import 'package:flutter_test/flutter_test.dart';
import 'package:comfyui_mobilepocket/services/image_ref.dart';

void main() {
  group('parseImageRef', () {
    test('裸文件名按 input 处理（ComfyUI 自己的约定）', () {
      final r = parseImageRef('example.png')!;
      expect(r.filename, 'example.png');
      expect(r.subfolder, '');
      expect(r.type, 'input');
    });

    test('带目录注解时以注解为准', () {
      final r = parseImageRef('ComfyUI_00001_.png [output]')!;
      expect(r.filename, 'ComfyUI_00001_.png');
      expect(r.type, 'output');
      expect(r.value, 'ComfyUI_00001_.png [output]');
    });

    test('子目录拆成 subfolder，不影响文件名', () {
      final r = parseImageRef('2026-10-28/ComfyUI_00001_.png [output]')!;
      expect(r.subfolder, '2026-10-28');
      expect(r.filename, 'ComfyUI_00001_.png');
      expect(r.value, '2026-10-28/ComfyUI_00001_.png [output]');
    });

    test('反斜杠路径与大小写注解都能认', () {
      final r = parseImageRef(r'old\sub\x.png [OUTPUT]')!;
      expect(r.subfolder, 'old/sub');
      expect(r.filename, 'x.png');
      expect(r.type, 'output');
    });

    test('空值 / 只有一个注解壳子返回 null', () {
      expect(parseImageRef(''), isNull);
      expect(parseImageRef('   '), isNull);
      expect(parseImageRef('[output]'), isNull);
    });

    test('往返一致', () {
      const value = 'sub/ComfyUI_1.png [output]';
      expect(parseImageRef(value)!.value, value);
    });
  });

  group('isImageFilename', () {
    test('只认图片扩展名，且不区分大小写', () {
      expect(isImageFilename('a.PNG'), isTrue);
      expect(isImageFilename('a.jpeg'), isTrue);
      expect(isImageFilename('a.webp'), isTrue);
      expect(isImageFilename('a.gif'), isFalse);
      expect(isImageFilename('a.txt'), isFalse);
    });

    test('目录里的占位文件被挡掉', () {
      expect(isImageFilename('_output_images_will_be_put_here'), isFalse);
    });
  });

  group('imageViewUrl', () {
    test('带上 subfolder 与 type，中文文件名要编码', () {
      final url = imageViewUrl(
        'http://h:8190',
        const ImageRef(filename: '参考 图.png', subfolder: '子 目录', type: 'output'),
      );
      expect(url, contains('/view?filename=%E5%8F%82%E8%80%83%20%E5%9B%BE.png'));
      expect(url, contains('&subfolder=%E5%AD%90%20%E7%9B%AE%E5%BD%95'));
      expect(url, contains('&type=output'));
      expect(url, isNot(contains('preview=')));
    });

    test('传 preview 时带上转码参数', () {
      final url = imageViewUrl(
        'http://h:8190',
        const ImageRef(filename: 'a.png', type: 'input'),
        preview: 'webp;75',
      );
      expect(url, contains('&preview=webp%3B75'));
    });
  });
}
