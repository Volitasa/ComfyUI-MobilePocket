import 'package:flutter/material.dart';

/// 二级页面顶栏标题的**统一样式**（配置页 / 添加参数页 / 运行页 / 解析页）。
///
/// 一级页面（工作流、生成记录、画廊、设置）是底部四个 Tab，标题用系统默认
/// 字号加粗；从它们钻进去的二级页小一号 —— 顶部还要放返回键和操作按钮，
/// 标题不该抢视觉。
///
/// ⚠️ 同一层的页面**必须都用这一个常量**。之前配置页的加载态与完成态各写
/// 各的：一进页面标题 20 号、取完节点信息变成 16 号，同一页的字自己会跳。
const TextStyle kSubPageTitleStyle = TextStyle(
  fontSize: 16,
  fontWeight: FontWeight.w600,
);
