import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';

/// Чип-сегмент «Живой бумаги»: пилюля без галочки. Выбран → сплошной синий +
/// белый текст, иначе → поверхность с тонкой рамкой.
/// Единый стиль для переключателей в «Статистике» (график и теги).
class SegChip extends StatelessWidget {
  const SegChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      onSelected: (_) => onTap(),
      selectedColor: AppColors.primary,
      backgroundColor: theme.colorScheme.surface,
      labelStyle: theme.textTheme.bodyMedium?.copyWith(
        color: selected ? Colors.white : theme.colorScheme.onSurface,
        fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
      ),
      side: BorderSide(
        color: selected
            ? Colors.transparent
            : theme.colorScheme.onSurface.withValues(alpha: 0.18),
      ),
      shape: const StadiumBorder(),
      visualDensity: VisualDensity.compact,
    );
  }
}
