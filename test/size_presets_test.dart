import 'package:flutter_test/flutter_test.dart';
import 'package:comfyui_mobilepocket/ui/builder/param_widgets/size_presets.dart';

void main() {
  group('alignToNearest', () {
    test('正好在两档中间时取小的', () {
      // 864 离 832 与 896 都是 32
      expect(alignToNearest(864, 64), 832);
    });

    test('偏向近的一档', () {
      expect(alignToNearest(683, 64), 704);
      expect(alignToNearest(700, 64), 704);
      expect(alignToNearest(660, 64), 640);
    });

    test('本来就是倍数 → 不动', () {
      expect(alignToNearest(1024, 64), 1024);
    });
  });

  group('sizeForRatio：比例 × 长边', () {
    test('常见档位与方案里的换算表一致', () {
      expect(sizeForRatio(kSizeRatios['1:1']!, 1024), (width: 1024, height: 1024));
      expect(sizeForRatio(kSizeRatios['4:3']!, 1024), (width: 1024, height: 768));
      expect(sizeForRatio(kSizeRatios['3:4']!, 1024), (width: 768, height: 1024));
      expect(sizeForRatio(kSizeRatios['16:9']!, 1024), (width: 1024, height: 576));
      expect(sizeForRatio(kSizeRatios['9:16']!, 768), (width: 448, height: 768));
      expect(sizeForRatio(kSizeRatios['3:2']!, 1024), (width: 1024, height: 704));
      expect(sizeForRatio(kSizeRatios['2:3']!, 1536), (width: 1024, height: 1536));
    });

    test('1280 与 1536 这两档也按 64 对齐', () {
      final a = sizeForRatio(kSizeRatios['16:9']!, 1280);
      final b = sizeForRatio(kSizeRatios['16:9']!, 1536);
      expect(a.width % 64, 0);
      expect(a.height % 64, 0);
      expect(b.width % 64, 0);
      expect(b.height % 64, 0);
    });

    test('长边指较长的一边，横竖都能算', () {
      final tall = sizeForRatio(kSizeRatios['9:16']!, 1024);
      expect(tall.height, 1024);
      expect(tall.width < tall.height, isTrue);
    });
  });

  group('反查：ratioForSize / longEdgeForSize', () {
    test('标准尺寸能认出比例与档位', () {
      expect(ratioForSize(1024, 576), '16:9');
      expect(longEdgeForSize(1024, 576), 1024);
    });

    test('认不出来就返回 null（卡片不改写已有值）', () {
      expect(ratioForSize(900, 1000), isNull);
    });

    test('离档位太远 → 也不选中档位', () {
      expect(longEdgeForSize(400, 400), isNull);
    });
  });
}
