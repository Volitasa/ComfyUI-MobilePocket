import 'package:flutter_test/flutter_test.dart';
import 'package:comfyui_mobilepocket/services/update_service.dart';

void main() {
  group('normalizeVersion', () {
    test('去掉 v 前缀', () {
      expect(UpdateService.normalizeVersion('v1.2.0'), '1.2.0');
      expect(UpdateService.normalizeVersion('V2.0.1'), '2.0.1');
    });

    test('去掉 +build 后缀', () {
      expect(UpdateService.normalizeVersion('1.0.0+1'), '1.0.0');
      expect(UpdateService.normalizeVersion('v1.2.0+12'), '1.2.0');
    });

    test('无前后缀时原样返回', () {
      expect(UpdateService.normalizeVersion('1.0.0'), '1.0.0');
    });
  });

  group('compareVersion', () {
    test('新版本大于旧版本', () {
      expect(UpdateService.compareVersion('1.2.0', '1.1.9'), greaterThan(0));
      expect(UpdateService.compareVersion('2.0.0', '1.9.9'), greaterThan(0));
    });

    test('旧版本小于新版本', () {
      expect(UpdateService.compareVersion('1.0.0', '1.0.1'), lessThan(0));
    });

    test('相同版本返回 0', () {
      expect(UpdateService.compareVersion('1.0.0', '1.0.0'), 0);
      // v 前缀与构建号不影响比较
      expect(UpdateService.compareVersion('v1.0.0+5', '1.0.0'), 0);
    });

    test('按数值比较而非字符串（1.10 > 1.9）', () {
      expect(UpdateService.compareVersion('1.10.0', '1.9.0'), greaterThan(0));
    });

    test('位数不等时缺失位按 0 处理', () {
      expect(UpdateService.compareVersion('1.2', '1.2.0'), 0);
      expect(UpdateService.compareVersion('1.2.1', '1.2'), greaterThan(0));
    });
  });
}
