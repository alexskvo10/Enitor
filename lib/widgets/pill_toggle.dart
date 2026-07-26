import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';

/// Сегментный переключатель в стиле iOS: приглушённая «дорожка», выбранный
/// сегмент — приподнятая пилюля (белая в светлой теме) с мягкой тенью, которая
/// плавно «едет» по дорожке при переключении (AnimatedAlign).
///
/// Дженерик по [T]: значения сегментов произвольного типа (ThemeMode,
/// BackgroundStyle, int-индекс вкладки и т.п.).
class PillToggle<T> extends StatelessWidget {
  const PillToggle({
    super.key,
    required this.segments,
    required this.selected,
    required this.onChanged,
  });

  /// Пары (значение, подпись) в порядке отображения.
  final List<(T, String)> segments;
  final T selected;
  final ValueChanged<T> onChanged;

  static const _dur = Duration(milliseconds: 240);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final track = dark ? AppColors.surfaceDarkMuted : AppColors.surfaceMuted;
    final pill = dark ? AppColors.surfaceDarkElevated : Colors.white;

    final n = segments.length;
    final idx = segments.indexWhere((s) => s.$1 == selected).clamp(0, n - 1);
    // Выравнивание единственной пилюли по слоту idx: x ∈ [-1; 1] для N равных
    // сегментов. AnimatedAlign плавно «везёт» пилюлю по дорожке.
    final x = n <= 1 ? 0.0 : (2 * idx + 1 - n) / (n - 1);

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: track,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Stack(
        children: [
          // Едущая пилюля — один слой под подписями, шириной 1/N.
          Positioned.fill(
            child: AnimatedAlign(
              duration: _dur,
              curve: AppColors.easeOut,
              alignment: Alignment(x, 0),
              child: FractionallySizedBox(
                widthFactor: 1 / n,
                heightFactor: 1,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: pill,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color:
                            Colors.black.withValues(alpha: dark ? 0.30 : 0.10),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Подписи поверх пилюли.
          Row(
            children: [
              for (final (value, label) in segments)
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onChanged(value),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      child: AnimatedDefaultTextStyle(
                        duration: _dur,
                        curve: AppColors.easeOut,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium!.copyWith(
                          color: value == selected
                              ? theme.colorScheme.onSurface
                              : theme.colorScheme.onSurface
                                  .withValues(alpha: 0.55),
                          fontWeight: value == selected
                              ? FontWeight.w600
                              : FontWeight.w500,
                        ),
                        child: Text(label, textAlign: TextAlign.center),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
