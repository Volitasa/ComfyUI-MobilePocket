import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'shared_preferences_provider.dart';

/// 会震一下的地方。每一类在设置里单独开关。
///
/// ⚠️ 新增类别时：枚举名会直接落盘，**改名等于让老用户的那一项悄悄复位**。
enum HapticCategory {
  /// 切换底部标签页
  nav,

  /// 勾选 / 取消勾选 / 节点内全选
  check,

  /// 长按拖动参数排序
  reorder,

  /// 展开 / 折叠参数卡
  fold,

  /// 任务下发成功
  submit,
}

/// 震动强度。只用系统给的三种，不自造「长震」「双击震」这类玩法。
enum HapticStrength { selection, light, medium }

/// 存储键。值是逗号分隔的类别名，例如 `nav,check,reorder`。
const String kHapticsPrefsKey = 'comfy_ui_haptics';

/// 解码。
///
/// ⚠️ **「键不存在」与「值为空」必须分开**：
/// - 键不存在 = 新装用户（或从没改过）→ 全部开启；
/// - 值为空串 = 用户主动把每一类都关掉了 → 一个都不开。
///
/// 两者混成一个默认值，就会出现「全部关闭之后再进来又变成全开」这种自相矛盾的体验。
Set<HapticCategory> decodeHaptics(String? raw) {
  if (raw == null) return HapticCategory.values.toSet();
  if (raw.trim().isEmpty) return <HapticCategory>{};
  final names = raw.split(',').map((e) => e.trim()).toSet();
  return HapticCategory.values.where((c) => names.contains(c.name)).toSet();
}

/// 编码。按枚举声明顺序输出，同样的集合永远得到同样的字符串——
/// 否则每次落盘都变一次值，`shared_preferences` 的写入没有意义。
String encodeHaptics(Set<HapticCategory> enabled) => HapticCategory.values
    .where(enabled.contains)
    .map((c) => c.name)
    .join(',');

class HapticsNotifier extends Notifier<Set<HapticCategory>> {
  @override
  Set<HapticCategory> build() =>
      decodeHaptics(ref.watch(sharedPreferencesProvider).getString(kHapticsPrefsKey));

  Future<void> toggle(HapticCategory category) async {
    final next = {...state};
    if (!next.remove(category)) next.add(category);
    await _persist(next);
  }

  Future<void> setAll(bool enabled) async {
    await _persist(enabled ? HapticCategory.values.toSet() : <HapticCategory>{});
  }

  Future<void> _persist(Set<HapticCategory> next) async {
    state = next;
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setString(kHapticsPrefsKey, encodeHaptics(next));
  }
}

final hapticsProvider =
    NotifierProvider<HapticsNotifier, Set<HapticCategory>>(HapticsNotifier.new);

/// **所有震动的唯一入口。**
///
/// 不让各调用点直接写 `HapticFeedback.xxx`：这次要给每一类做独立开关，
/// 散着写就得改五六个文件，以后再加类别还会继续散；而且「关了还震」这种 bug
/// 只会出现在漏改的那一处，最难查。
///
/// 关闭时直接返回，不产生任何平台调用。
void hapticFeedback(
  WidgetRef ref,
  HapticCategory category, {
  HapticStrength strength = HapticStrength.selection,
}) {
  if (!ref.read(hapticsProvider).contains(category)) return;
  switch (strength) {
    case HapticStrength.selection:
      HapticFeedback.selectionClick();
    case HapticStrength.light:
      HapticFeedback.lightImpact();
    case HapticStrength.medium:
      HapticFeedback.mediumImpact();
  }
}
