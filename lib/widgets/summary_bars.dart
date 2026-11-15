import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';

/// Одна строка сводки: подпись, доля 0..1 (null — «—», пустая полоса),
/// подпись справа под процентом («3.6 / 5»), цвета градиента полосы.
typedef SummaryBar = ({
  String label,
  double? value,
  String caption,
  List<Color> colors,
});

/// Сводка дня/периода полосами — компактная замена двум кольцам
/// (Настройки → Оформление → «Сводка»). Те же данные и цвета, что у колец.
class SummaryBars extends StatelessWidget {
  const SummaryBars({super.key, required this.bars});

  final List<SummaryBar> bars;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final track = dark ? AppColors.ringTrackDark : AppColors.ringTrack;
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.6);

    Widget row(SummaryBar b) {
      final target = (b.value ?? 0).clamp(0.0, 1.0);
      return TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: target),
        duration: const Duration(milliseconds: 900),
        curve: AppColors.easeOut,
        builder: (context, t, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Expanded(
                  child: Text(
                    b.label,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: muted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  b.caption,
                  style: theme.textTheme.labelMedium?.copyWith(color: muted),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 48,
                  child: Text(
                    b.value == null ? '—' : '${(t * 100).round()}%',
                    textAlign: TextAlign.end,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                height: 10,
                child: Stack(
                  children: [
                    Positioned.fill(child: ColoredBox(color: track)),
                    FractionallySizedBox(
                      widthFactor: t,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(6),
                          gradient: LinearGradient(colors: b.colors),
                        ),
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          children: [
            for (var i = 0; i < bars.length; i++) ...[
              if (i > 0) const SizedBox(height: 14),
              row(bars[i]),
            ],
          ],
        ),
      ),
    );
  }
}
