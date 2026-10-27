import 'package:flutter/material.dart';

import '../../theme.dart';

/// 工作流列表里的一行。
///
/// 三处共用：服务器 API 工作流、服务器 UI 工作流、本地工作流。
/// 以前三处各写一份卡片（内边距 20、标题 18 号），一屏只能放 6 个；
/// 抽出来统一改成紧凑行，顺带保证行高、字号、间距不会再各自漂移。
class WorkflowTile extends StatelessWidget {
  const WorkflowTile({
    super.key,
    required this.title,
    this.statusLabel = '',
    this.statusColor,
    this.footnote = '',
    this.footnoteColor,
    this.borderColor,
    this.fillColor,
    this.showBorder = true,
    this.menu,
    this.onTap,
  });

  final String title;

  /// 右上角的状态文字（如「已配置 6 项」「未解析」「有更新」）
  final String statusLabel;
  final Color? statusColor;

  /// 第二行的信息（上次运行时间）
  final String footnote;
  final Color? footnoteColor;

  /// 「有更新」的条目用琥珀色描边 + 底色，与正常条目区分
  final Color? borderColor;
  final Color? fillColor;

  /// 未解析的 UI 条目不描边（表示它还不能用）
  final bool showBorder;

  /// 右侧的菜单按钮；为 null 时不占位
  final Widget? menu;
  final VoidCallback? onTap;

  static const double _radius = 10;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      elevation: 0,
      color: fillColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_radius),
        side: showBorder
            ? BorderSide(color: borderColor ?? Colors.grey.shade300)
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(_radius),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            // 锁行高：默认行高会让 14 号字占掉 20px，
                            // 两行字就耗掉 36，卡片高度下不来
                            style: const TextStyle(
                              fontSize: 14,
                              height: 1.2,
                              fontWeight: FontWeight.w500,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                        if (statusLabel.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Text(
                            statusLabel,
                            style: TextStyle(
                              fontSize: 11,
                              color: statusColor ?? AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (footnote.isNotEmpty) ...[
                      const SizedBox(height: 1),
                      Text(
                        footnote,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          height: 1.2,
                          color: footnoteColor ?? AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              ?menu,
            ],
          ),
        ),
      ),
    );
  }
}
