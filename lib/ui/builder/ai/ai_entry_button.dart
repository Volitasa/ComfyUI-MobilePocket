import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme.dart';

/// 运行页底部「立即生成」右侧的 AI 次级按钮。
///
/// 宽度固定 64，高度由父级 `Row` 的 stretch 决定（不写死，否则主按钮一调就错位）。
class AiEntryButton extends StatelessWidget {
  const AiEntryButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Material(
      color: context.containerFill,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onPressed,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: context.borderColor),
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.auto_awesome, size: 17, color: context.accent),
              const SizedBox(width: 4),
              Text(
                l.aiEntry,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: context.accent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
