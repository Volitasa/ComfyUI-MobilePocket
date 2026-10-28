import 'package:flutter/material.dart';

import '../../theme.dart';

/// 配置页里单个参数的行：勾选 + 别名输入 + 当前值摘要，**一行 44px**。
///
/// 别名只出现一次 —— 输入框本身就是显示别名的地方（平时无边框、聚焦才描一圈），
/// 所以扫读时不会出现「同一串字上下叠两行」，几十行并排也不像填报表。
///
/// 代价：整行不再是点击热区，切换勾选只能点左侧 36×44 的勾选框；
/// 点别名文字/输入框只会聚焦，不会顺手把参数勾上或取消。
class ParamConfigTile extends StatefulWidget {
  const ParamConfigTile({
    super.key,
    required this.summary,
    required this.exposed,
    required this.onChanged,
    required this.aliasController,
    required this.aliasHint,
    this.onAliasChanged,
    this.warning,
    this.showCheckbox = true,
    this.onRemove,
    this.removeTooltip,
  });

  /// 行高：44 是紧凑与「点得中」的折中，不再往下压。
  static const double rowHeight = 44;

  final String summary;
  final bool exposed;

  /// 勾选变化。为 null 时（配合 `showCheckbox: false`）该行不可勾选。
  final ValueChanged<bool?>? onChanged;
  final TextEditingController aliasController;
  final String aliasHint;

  /// 是否画左侧勾选框。
  ///
  /// false 用于「已放进表单」的语境：那些参数本来就是选中的，
  /// 再放一个永远勾着的框是噪音，取消改由 [onRemove] 承担。
  final bool showCheckbox;

  /// 尾部「移出」按钮。非 null 时行尾出现一个移除图标，点击即取消选中。
  ///
  /// 与 [showCheckbox] 二选一：有这个就别再画勾选框，否则一行上出现两个
  /// 含义相反的入口（勾上 / 移出），用户要停下来想一下才敢点。
  final VoidCallback? onRemove;

  /// 移除按钮的长按提示。
  final String? removeTooltip;

  /// 别名改动回写（保存配置时用的就是 `node.alias`，不是控制器里的文本）。
  final ValueChanged<String>? onAliasChanged;

  /// 行级告警文案（如"服务器上没有这个参数"）。为空则不显示。
  ///
  /// ⚠️ 只标黄、**不拦** —— 缺参数通常只是服务器节点版本不同，
  /// 照旧提交原值比拦下来更有用（方案 §3.7）。拦截逻辑在 C4。
  final String? warning;

  /// 行尾显示的小字：有告警时优先显示告警，否则显示类型与当前值摘要。
  String get trailingText =>
      (warning != null && warning!.isNotEmpty) ? warning! : summary;

  @override
  State<ParamConfigTile> createState() => _ParamConfigTileState();
}

class _ParamConfigTileState extends State<ParamConfigTile> {
  final FocusNode _focusNode = FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_handleFocusChange);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    _focusNode.dispose();
    super.dispose();
  }

  /// 聚焦时把行尾摘要收起来：别名正在被改，这时候腾出的宽度比读值有用。
  void _handleFocusChange() {
    if (_focused == _focusNode.hasFocus) return;
    setState(() => _focused = _focusNode.hasFocus);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: ParamConfigTile.rowHeight,
      child: Row(
        children: [
          if (widget.showCheckbox)
            SizedBox(
              width: 36,
              child: Checkbox(
                value: widget.exposed,
                onChanged: widget.onChanged,
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          Expanded(
            child: TextField(
              controller: widget.aliasController,
              focusNode: _focusNode,
              onChanged: widget.onAliasChanged,
              style: const TextStyle(fontSize: 14, height: 1.2),
              decoration: InputDecoration(
                isDense: true,
                hintText: widget.aliasHint,
                hintStyle: TextStyle(
                  fontSize: 14,
                  height: 1.2,
                  color: context.textSecondary,
                ),
                // 平时看不出是输入框，聚焦才描边：可编辑性靠「点一下就有光标」传达，
                // 而不是让几十个边框把页面变成表单。
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(
                    color: theme.colorScheme.primary,
                    width: 1,
                  ),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 8,
                ),
              ),
            ),
          ),
          // 行尾写的是「属于哪个节点 · 当前值」，比原来的「类型」长得多，
          // 所以上限放到 168（原来 120 只够放「类型: 整数 · 当前值: 20」这种短句）。
          // 再长就交给省略号，无论如何都不许把左边的别名挤没；
          // 编辑别名时整段让出去，有告警时行尾让给告警（黄色）。
          if (!_focused && widget.trailingText.isNotEmpty) ...[
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 168),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.warning != null && widget.warning!.isNotEmpty) ...[
                    Icon(
                      Icons.warning_amber_rounded,
                      size: 12,
                      color: context.stateWarning,
                    ),
                    const SizedBox(width: 4),
                  ],
                  Flexible(
                    child: Text(
                      widget.trailingText,
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.2,
                        color: widget.warning != null
                            ? context.stateWarning
                            : context.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (widget.onRemove != null) ...[
            const SizedBox(width: 4),
            SizedBox(
              width: 32,
              child: IconButton(
                icon: Icon(Icons.close, size: 18, color: context.textSecondary),
                tooltip: widget.removeTooltip,
                onPressed: widget.onRemove,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
