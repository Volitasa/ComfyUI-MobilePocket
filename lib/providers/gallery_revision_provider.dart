import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 画廊目录的变动计数：只在「真的写盘成功」或「真的删了本地文件」之后 +1。
///
/// 画廊页监听它来决定要不要重扫目录。之所以不比较任务状态的前后快照：
/// 任务记录对象是可变的，图片落盘是就地改同一个对象，前后两帧状态共享
/// 同一批实例 —— 靠「上一次 vs 这一次」的差值判断新增本地图片，永远比不出来。
/// （旧写法 `galleryDirectoryMayHaveChanged` 就是这么失效的，2026-10-24 移除。）
final galleryRevisionProvider = StateProvider<int>((ref) => 0);
