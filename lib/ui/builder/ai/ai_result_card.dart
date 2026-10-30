import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme.dart';

/// 结果卡：建议文本 + 字数变化 + 写入/复制。
///
/// 不做 diff 视图（逐行对比要单独一屏），也不做红绿高亮。
class AiResultCard extends StatelessWidget {
  const AiResultCard({
    super.key,
    required this.text,
    required this.beforeLength,
    required this.structured,
    required this.streaming,
    required this.written,
    this.servedModel,
    required this.onWrite,
    required this.onCopy,
  });

  final String text;
  final int beforeLength;
  final bool structured;
  final bool streaming;
  final bool written;

  /// 供应商回报的实际模型名；没回报时为 null（不猜、不填预设名）。
  final String? servedModel;
  final VoidCallback onWrite;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final canWrite = !streaming && text.trim().isNotEmpty && !written;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                streaming ? l.aiGenerating : l.aiResultTitle,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
              ),
              const Spacer(),
              if (!streaming && text.isNotEmpty)
                Text(
                  l.aiCharsChange(text.length, beforeLength),
                  style: TextStyle(fontSize: 11, color: context.textSecondary),
                ),
            ],
          ),
          if (!structured && !streaming && text.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              l.aiNotStructured,
              style: TextStyle(fontSize: 11, color: context.stateWarning),
            ),
          ],
          const SizedBox(height: 6),
          Text(
            text.isEmpty ? '…' : text,
            style: const TextStyle(fontSize: 12, height: 1.6),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: canWrite ? onWrite : null,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(38),
                    backgroundColor: context.accent,
                    foregroundColor: context.onAccent,
                  ),
                  child: Text(written ? l.aiWritten : l.aiWrite),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: text.isEmpty ? null : onCopy,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(38),
                  ),
                  child: Text(l.aiCopy),
                ),
              ),
            ],
          ),
          if (servedModel != null && servedModel!.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              l.aiServedModel(servedModel!),
              style: TextStyle(fontSize: 10, color: context.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}
