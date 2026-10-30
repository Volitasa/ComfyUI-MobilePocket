import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  /// 长按（图轨缩略图长按预览这类动作）。
  ///
  /// ⚠️ 这一类是 v1.4.2 加的，追加在末尾：枚举顺序直接决定落盘字符串的排列，
  /// 插到中间会让「同样的开关组合」写出不一样的值。
  press,
}

/// 震动强度。只用系统给的三种，不自造「长震」「双击震」这类玩法。
enum HapticStrength { selection, light, medium }

/// 存储键。值是逗号分隔的类别名，例如 `nav,check,reorder`。
const String kHapticsPrefsKey = 'comfy_ui_haptics';

/// 上一次写入时**知道有哪些类别**。
///
/// 为什么需要第二个键：这里存的是「开启的名单」，所以**缺一个名字有两种可能**
/// ——用户把它关掉了，或者写这份数据的时候还没有这一项。
/// 新增 `press` 之后，老用户存的值里必然没有它，光靠 [kHapticsPrefsKey]
/// 无法区分这两种情况：要么让一路点「全部关闭」的人升级后莫名又震起来，
/// 要么让老用户的长按升级后悄悄不震（误判成他关了）。
const String kHapticsKnownPrefsKey = 'comfy_ui_haptics_known';

/// 引进 `known` 键之前存在的类别。
///
/// 只用于「这份数据是老版本写的」这一档迁移。之后再新增类别不需要改这里——
/// 那时写的数据已经带 `known`，按同样规则自动生效。
const List<HapticCategory> kHapticsCategoriesBeforeKnown = [
  HapticCategory.nav,
  HapticCategory.check,
  HapticCategory.reorder,
  HapticCategory.fold,
  HapticCategory.submit,
];

/// 从当前存储读出开关状态，并把**新加的类别按默认开启补上**。
///
/// 见 [kHapticsKnownPrefsKey] 里写的取舍。三条分支刻意分开：
/// - 没存过 → 全开；
/// - 存了空串（用户主动全关）→ 一个都不补，连新类别也不补：
///   「全部关闭」表达的是「这 App 别震」，补一个开关进来等于违背这个选择；
/// - 存了部分名单 → 名单照旧，再把上次写入时还不认识的类别开启。
Set<HapticCategory> readHaptics(SharedPreferences prefs) {
  final raw = prefs.getString(kHapticsPrefsKey);
  if (raw == null) return HapticCategory.values.toSet();
  final enabled = decodeHaptics(raw);
  if (raw.trim().isEmpty) return enabled;

  final knownNames =
      prefs.getString(kHapticsKnownPrefsKey)?.split(',').toSet() ??
      kHapticsCategoriesBeforeKnown.map((c) => c.name).toSet();
  return enabled.union(
    HapticCategory.values.where((c) => !knownNames.contains(c.name)).toSet(),
  );
}

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
      readHaptics(ref.watch(sharedPreferencesProvider));

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
    // 顺带记下「这次写入时知道有哪些类别」，见 readHaptics 的注释：
    // 下次再新增类别时，才能把「用户关掉了」和「当时还没这一项」区分开。
    await prefs.setString(
      kHapticsKnownPrefsKey,
      HapticCategory.values.map((c) => c.name).join(','),
    );
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
