import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';

/// Дельта продуктивности к прошлой неделе. Треугольник ▲/▼ + число + % .
/// Положительная — зелёная, отрицательная — красная, ноль — нейтральная.
class DeltaIndicator extends StatelessWidget {
  const DeltaIndicator({
    super.key,
    required this.deltaPercent,
    this.compact = false,
  });

  /// В процентных пунктах (например, +2.5 значит +2.5%).
  final double? deltaPercent;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (deltaPercent == null) {
      return Text(
        '—',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
        ),
      );
    }

    final value = deltaPercent!;
    final isPositive = value > 0.05;
    final isNegative = value < -0.05;
    final color = isPositive
        ? AppColors.success
        : isNegative
            ? AppColors.danger
            : theme.colorScheme.onSurface.withValues(alpha: 0.5);
    // Треугольнички ▲/▼ (юникод-глифы) вместо стрелок — тайтовые и читаются
    // как биржевой индикатор «вверх/вниз»; ноль — короткое тире.
    final glyph = isPositive
        ? '▲'
        : isNegative
            ? '▼'
            : '–';

    final formatted = '${value.abs().toStringAsFixed(1)}%';
    final textStyle =
        (compact ? theme.textTheme.bodySmall : theme.textTheme.bodyMedium)
            ?.copyWith(color: color, fontWeight: FontWeight.w600);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(glyph, style: textStyle?.copyWith(fontSize: compact ? 9 : 11)),
        const SizedBox(width: 3),
        Text(formatted, style: textStyle),
      ],
    );
  }
}
