/// 尺寸卡用到的预设与换算。**纯函数，不依赖 Flutter，便于单测。**
library;

/// 画面比例：显示名 → 宽 : 高
class SizeRatio {
  const SizeRatio(this.w, this.h);

  final int w;
  final int h;

  double get value => w / h;
}

const Map<String, SizeRatio> kSizeRatios = {
  '1:1': SizeRatio(1, 1),
  '4:3': SizeRatio(4, 3),
  '3:4': SizeRatio(3, 4),
  '3:2': SizeRatio(3, 2),
  '2:3': SizeRatio(2, 3),
  '16:9': SizeRatio(16, 9),
  '9:16': SizeRatio(9, 16),
};

/// 长边档位
const List<int> kLongEdgeOptions = [768, 1024, 1280, 1536];

/// 对齐单位：SDXL / Flux 这类模型按 64 对齐最稳，SD1.5 只要求 8，
/// 64 是它们的公约数里最实用的一档。
const int kSizeAlign = 64;

/// 张数步进范围
const int kBatchMin = 1;
const int kBatchMax = 8;

/// 取到 [unit] 的最近倍数；正好在中间时取小的那一档。
int alignToNearest(int v, int unit) {
  if (unit <= 0) return v;
  final lower = (v ~/ unit) * unit;
  return (v - lower) * 2 <= unit ? lower : lower + unit;
}

/// 比例 + 长边 → 宽高（都按 64 对齐）。
({int width, int height}) sizeForRatio(SizeRatio ratio, int longEdge) {
  final long = alignToNearest(longEdge, kSizeAlign);
  final wide = ratio.w >= ratio.h;
  final shortRaw = wide
      ? longEdge * ratio.h / ratio.w
      : longEdge * ratio.w / ratio.h;
  final short = alignToNearest(shortRaw.round(), kSizeAlign);
  // 极端比例下短边可能被压到 0，兜底成一个对齐单位
  final safeShort = short < kSizeAlign ? kSizeAlign : short;
  return wide
      ? (width: long, height: safeShort)
      : (width: safeShort, height: long);
}

/// 反查当前宽高最接近哪个比例（用于进页面时把 chips 选中）。
///
/// 对不上就返回 null —— 卡片不改写已有值，也就没有选中项。
String? ratioForSize(int width, int height) {
  if (width <= 0 || height <= 0) return null;
  final target = width / height;
  String? best;
  var bestDiff = double.infinity;
  for (final entry in kSizeRatios.entries) {
    final diff = (entry.value.value - target).abs();
    if (diff < bestDiff) {
      bestDiff = diff;
      best = entry.key;
    }
  }
  // 差太多就不硬套，否则选中的比例跟实际尺寸对不上
  return bestDiff <= 0.02 ? best : null;
}

/// 当前长边最接近哪个档位。
int? longEdgeForSize(int width, int height) {
  if (width <= 0 || height <= 0) return null;
  final long = width >= height ? width : height;
  int? best;
  var bestDiff = 1 << 30;
  for (final option in kLongEdgeOptions) {
    final diff = (option - long).abs();
    if (diff < bestDiff) {
      bestDiff = diff;
      best = option;
    }
  }
  return bestDiff <= 128 ? best : null;
}
