import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../l10n/l10n_extensions.dart';
import 'fancy_dialog.dart';

/// Ряд звёзд для оценки качества (рефлексия) от 1 до [max].
///
/// • Если [onRate] задан — звёзды интерактивны (тап ставит оценку).
/// • Иначе — только отображение (заполнено [value] звёзд).
class StarRating extends StatelessWidget {
  const StarRating({
    super.key,
    required this.value,
    this.max = 10,
    this.size = 22,
    this.onRate,
    this.color,
  });

  /// Сколько звёзд заполнено (0..max).
  final int value;
  final int max;
  final double size;

  /// Колбэк выбора (1..max). null — режим отображения.
  final ValueChanged<int>? onRate;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final active = color ?? AppColors.warning;
    final inactive =
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.25);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < max; i++)
          GestureDetector(
            onTap: onRate == null ? null : () => onRate!(i + 1),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: size * 0.04),
              child: Icon(
                i < value ? Icons.star_rounded : Icons.star_outline_rounded,
                size: size,
                color: i < value ? active : inactive,
              ),
            ),
          ),
      ],
    );
  }
}

/// Показывает необязательный диалог оценки качества с вопросом [question].
/// Возвращает выбранную оценку (1..10) или null, если пользователь пропустил.
Future<int?> showQualityDialog(
  BuildContext context, {
  required String question,
  int? initial,
}) {
  return showFancyRawDialog<int>(
    context: context,
    barrierLabel: question,
    builder: (ctx) => _QualityDialog(question: question, initial: initial),
  );
}

class _QualityDialog extends StatefulWidget {
  const _QualityDialog({required this.question, this.initial});
  final String question;
  final int? initial;

  @override
  State<_QualityDialog> createState() => _QualityDialogState();
}

class _QualityDialogState extends State<_QualityDialog> {
  int? _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.initial;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    return FancyDialogCard(
      icon: Icons.star_rounded,
      iconColor: AppColors.warning,
      title: widget.question,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 14),
          // Все 10 звёзд в один ряд.
          FittedBox(
            fit: BoxFit.scaleDown,
            child: StarRating(
              value: _selected ?? 0,
              max: 10,
              size: 30,
              onRate: (v) => setState(() => _selected = v),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            _selected == null ? l10n.notRatedYet : '${_selected!} / 10',
            style: theme.textTheme.titleMedium?.copyWith(
              color: _selected == null
                  ? AppColors.textSecondary
                  : theme.colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(l10n.skipBtn),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _selected == null
                    ? null
                    : () => Navigator.pop(context, _selected),
                child: Text(l10n.saveBtn),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
