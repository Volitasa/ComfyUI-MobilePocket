import 'package:flutter/material.dart';

/// 配置页里单个参数的行：勾选 + 别名输入框。
///
/// 紧凑版（方案 A2）：勾选行 44 + 别名输入框 36，比原来的
/// 「勾选行 48 + 副标题一行 + 缩进 40 的输入框 44」省掉约 20px / 参数。
/// 别名输入框**保持常显** —— 运行页的字段标签就是它，藏起来等于让人忘了
/// 自己能改名字；这里只是把它从「独占一行、缩进 40」压成「贴着卡片左缘、
/// 36 高」。
///
/// 类型说明不再单独占一行：与当前值合并成行尾的一行小字。
class ParamConfigTile extends StatelessWidget {
  const ParamConfigTile({
    super.key,
    required this.alias,
    required this.summary,
    required this.exposed,
    required this.onChanged,
    required this.aliasController,
    required this.aliasHint,
    this.onAliasChanged,
  });

  /// 勾选行高度：44 是紧凑与「点得中」的折中，不再往下压。
  static const double rowHeight = 44;

  /// 别名输入框高度。
  static const double fieldHeight = 36;

  final String alias;
  final String summary;
  final bool exposed;
  final ValueChanged<bool?> onChanged;
  final TextEditingController aliasController;
  final String aliasHint;

  /// 别名改动回写（保存配置时用的就是 `node.alias`，不是控制器里的文本）。
  final ValueChanged<String>? onAliasChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: rowHeight,
          child: InkWell(
            onTap: () => onChanged(!exposed),
            child: Row(
              children: [
                SizedBox(
                  width: 36,
                  child: Checkbox(
                    value: exposed,
                    onChanged: onChanged,
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
                Expanded(
                  child: Text(
                    alias,
                    style: const TextStyle(fontSize: 14, height: 1.2),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                // 当前值只占行尾一小段，长值截断，不把别名挤没
                Flexible(
                  child: Text(
                    summary,
                    style: const TextStyle(
                      fontSize: 11,
                      height: 1.2,
                      color: Colors.grey,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 12),
          child: SizedBox(
            height: fieldHeight,
            child: TextField(
              controller: aliasController,
              onChanged: onAliasChanged,
              style: const TextStyle(fontSize: 14, height: 1.2),
              decoration: InputDecoration(
                isDense: true,
                hintText: aliasHint,
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 8,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
