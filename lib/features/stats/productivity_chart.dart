import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/appearance.dart';
import '../../data/repositories/stats_repository.dart';
import '../../l10n/l10n_extensions.dart';
import '../../widgets/error_view.dart';

/// График продуктивности + своевременности.
/// Две линии на одном полотне: синяя (продуктивность) и янтарная (вовремя).
class ProductivityChart extends ConsumerWidget {
  const ProductivityChart({
    super.key,
    required this.from,
    required this.to,
    required this.grouping,
  });

  final DateTime from;
  final DateTime to;
  final ChartGrouping grouping;

  static const _colorOnTime = Color(0xFFFFA726); // amber 400

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = PointsQuery(from: from, to: to, grouping: grouping);
    final pointsAsync = ref.watch(productivityPointsProvider(query));

    return pointsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorView(
        compact: true,
        onRetry: () => ref.invalidate(productivityPointsProvider(query)),
      ),
      data: (rawPoints) {
        if (rawPoints.isEmpty) {
          return _EmptyState(message: context.l10n.rangeTooShortNote);
        }

        // Обрезаем пустые бакеты слева (до первых данных — начало
        // пользования). НЕ компенсируем обрезку справа: последний бакет
        // (rawPoints.last) — это всегда «сейчас» (to = today), он должен
        // оставаться самой правой точкой. Если данных не хватает на весь
        // выбранный таймфрейм (человек недавно начал), график просто короче
        // по ширине — от первой реальной точки до «сейчас», без фиктивных
        // пустых бакетов в будущем.
        final firstIdx = rawPoints.indexWhere((p) => p.value != null);
        final points = firstIdx <= 0 ? rawPoints : rawPoints.sublist(firstIdx);

        // Споты продуктивности
        final prodSpots = <FlSpot>[];
        for (var i = 0; i < points.length; i++) {
          final v = points[i].value;
          if (v != null) prodSpots.add(FlSpot(i.toDouble(), v * 100));
        }

        // Споты своевременности (только там, где есть данные)
        final onTimeSpots = <FlSpot>[];
        for (var i = 0; i < points.length; i++) {
          final v = points[i].onTimeValue;
          if (v != null) onTimeSpots.add(FlSpot(i.toDouble(), v * 100));
        }

        final hasData = prodSpots.isNotEmpty;
        final hasOnTimeData = onTimeSpots.isNotEmpty;

        const xPad = 0.4;
        final maxX = (points.length - 1).toDouble().clamp(1.0, double.infinity);

        final bars = <LineChartBarData>[];
        if (hasData) {
          // Линия продуктивности
          bars.add(LineChartBarData(
            spots: prodSpots,
            isCurved: false,
            color: AppColors.primary,
            barWidth: 3,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: true),
            belowBarData: BarAreaData(
              show: true,
              color: AppColors.primary.withValues(alpha: 0.08),
            ),
          ));
        }
        if (hasOnTimeData) {
          // Линия своевременности
          bars.add(LineChartBarData(
            spots: onTimeSpots,
            isCurved: false,
            color: _colorOnTime,
            barWidth: 2,
            isStrokeCapRound: true,
            dashArray: null,
            dotData: const FlDotData(show: true),
            belowBarData: BarAreaData(
              show: true,
              color: _colorOnTime.withValues(alpha: 0.06),
            ),
          ));
        }

        return Column(
          children: [
            // ── Легенда ────────────────────────────────────────────────────
            if (hasOnTimeData)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _LegendDot(color: AppColors.primary),
                    const SizedBox(width: 4),
                    Text(context.l10n.productivityLegendLabel,
                        style: const TextStyle(fontSize: 11)),
                    const SizedBox(width: 16),
                    _LegendDot(color: _colorOnTime),
                    const SizedBox(width: 4),
                    Text(context.l10n.onTimeLegendLabel,
                        style: const TextStyle(fontSize: 11)),
                  ],
                ),
              ),
            // ── График ─────────────────────────────────────────────────────
            Expanded(
              child: Stack(
                children: [
                  LineChart(
                    LineChartData(
                      minY: 0,
                      maxY: 100,
                      minX: -xPad,
                      maxX: maxX + xPad,
                      clipData: const FlClipData.all(),
                      lineTouchData: LineTouchData(
                        touchTooltipData: LineTouchTooltipData(
                          getTooltipItems: (touchedSpots) {
                            // Метка периода — берём из первой точки
                            final firstX = touchedSpots.isNotEmpty
                                ? touchedSpots.first.x.round()
                                : -1;
                            final periodLabel =
                                (firstX >= 0 && firstX < points.length)
                                    ? _bucketLabel(
                                        context, points[firstX].bucketStart)
                                    : null;

                            return touchedSpots.map((s) {
                              final isFirst = s == touchedSpots.first;
                              final pct = s.y;
                              final pctStr = pct == pct.roundToDouble()
                                  ? '${pct.toInt()}%'
                                  : '${pct.toStringAsFixed(1)}%';
                              final isOnTime = s.barIndex == 1;

                              // Первый элемент: заголовок с периодом + процент
                              if (isFirst && periodLabel != null) {
                                return LineTooltipItem(
                                  periodLabel,
                                  const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 11,
                                    fontWeight: FontWeight.normal,
                                  ),
                                  children: [
                                    TextSpan(
                                      text: '\n${isOnTime ? '⏰ ' : ''}$pctStr',
                                      style: TextStyle(
                                        color: isOnTime
                                            ? _colorOnTime
                                            : Colors.white,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                );
                              }

                              // Остальные элементы: только процент
                              return LineTooltipItem(
                                '${isOnTime ? '⏰ ' : ''}$pctStr',
                                TextStyle(
                                  color: isOnTime ? _colorOnTime : Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                              );
                            }).toList();
                          },
                        ),
                      ),
                      lineBarsData: bars,
                      gridData:
                          const FlGridData(show: true, drawVerticalLine: false),
                      titlesData: FlTitlesData(
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 36,
                            interval: 25,
                            getTitlesWidget: (v, _) => Text(
                              '${v.toInt()}%',
                              style: const TextStyle(fontSize: 10),
                            ),
                          ),
                        ),
                        rightTitles: const AxisTitles(),
                        topTitles: const AxisTitles(),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            interval: _bottomInterval(points.length).toDouble(),
                            reservedSize: _bottomReservedSize(),
                            getTitlesWidget: (v, _) =>
                                _buildBottomTitle(context, v, points),
                          ),
                        ),
                      ),
                      extraLinesData: ExtraLinesData(
                        verticalLines: _yearDividers(points),
                      ),
                      borderData: FlBorderData(show: false),
                    ),
                  ),
                  if (!hasData)
                    const Positioned.fill(
                      child: IgnorePointer(
                        child: Center(child: _EmptyOverlay()),
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  // ─── Вспомогательные методы ─────────────────────────────────────────────────

  // ─── Подпись бакета для тултипа ────────────────────────────────────────────

  // Генитив месяца (нужен для «27 мая», «28 апреля»).
  static const _monthGenRu = [
    '',
    'января',
    'февраля',
    'марта',
    'апреля',
    'мая',
    'июня',
    'июля',
    'августа',
    'сентября',
    'октября',
    'ноября',
    'декабря',
  ];
  // Именительный месяца (нужен для «май 2026»).
  static const _monthNomRu = [
    '',
    'январь',
    'февраль',
    'март',
    'апрель',
    'май',
    'июнь',
    'июль',
    'август',
    'сентябрь',
    'октябрь',
    'ноябрь',
    'декабрь',
  ];
  static const _monthEn = [
    '',
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  String _bucketLabel(BuildContext context, DateTime d) {
    final ru = Localizations.localeOf(context).languageCode == 'ru';
    final monthGen = ru ? _monthGenRu : _monthEn;
    final monthNom = ru ? _monthNomRu : _monthEn;
    switch (grouping) {
      case ChartGrouping.daily:
        return '${d.day} ${monthGen[d.month]} ${d.year}';

      case ChartGrouping.weekly:
        final end = d.add(const Duration(days: 6));
        if (d.month == end.month) {
          // «24–30 мая 2026»
          return '${d.day}–${end.day} ${monthGen[d.month]} ${d.year}';
        } else if (d.year == end.year) {
          // «28 апр – 4 мая 2026»
          final sm = monthGen[d.month].substring(0, 3);
          final em = monthGen[end.month].substring(0, 3);
          return '${d.day} $sm – ${end.day} $em ${d.year}';
        } else {
          // редкий кейс: неделя пересекает год
          return '${d.day} ${monthGen[d.month]} ${d.year} –\n'
              '${end.day} ${monthGen[end.month]} ${end.year}';
        }

      case ChartGrouping.monthly:
        return '${monthNom[d.month]} ${d.year}';

      case ChartGrouping.yearly:
        return '${d.year}';
    }
  }

  int _bottomInterval(int total) {
    if (total <= 8) return 1;
    if (total <= 16) return 2;
    if (total <= 32) return 4;
    return (total / 8).ceil();
  }

  /// Высота зоны подписей оси X.
  /// Для «Неделя» нужно больше места — подпись двухстрочная (начало / конец).
  double _bottomReservedSize() => grouping == ChartGrouping.weekly ? 40 : 28;

  /// Виджет подписи для оси X.
  ///
  /// • День    → «27.05»
  /// • Неделя  → «27.05» (верхняя строка, начало) / «02.06» (нижняя, конец)
  /// • Месяц   → «май»
  /// • Год     → «2026»
  Widget _buildBottomTitle(
      BuildContext context, double v, List<ProductivityPoint> points) {
    final locale = Localizations.localeOf(context).languageCode;
    final i = v.round();
    // fl_chart вызывает getTitlesWidget для minX/maxX (= ±xPad = ±0.4), которые
    // не совпадают ни с одним бакетом — они дают дробный v, далёкий от целого.
    // Фильтруем, чтобы не дублировать метку первого/последнего бакета.
    if ((v - i).abs() > 0.1) return const SizedBox();
    if (i < 0 || i >= points.length) return const SizedBox();
    final d = points[i].bucketStart;

    switch (grouping) {
      case ChartGrouping.daily:
        return Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            DateFormat('dd.MM').format(d),
            style: const TextStyle(fontSize: 10),
          ),
        );

      case ChartGrouping.weekly:
        final end = d.add(const Duration(days: 6));
        return Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                DateFormat('dd.MM').format(d),
                style: const TextStyle(fontSize: 9),
              ),
              Text(
                DateFormat('dd.MM').format(end),
                style: const TextStyle(fontSize: 9),
              ),
            ],
          ),
        );

      case ChartGrouping.monthly:
        return Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            DateFormat.MMM(locale).format(d),
            style: const TextStyle(fontSize: 10),
          ),
        );

      case ChartGrouping.yearly:
        return Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            '${d.year}',
            style: const TextStyle(fontSize: 10),
          ),
        );
    }
  }

  List<VerticalLine> _yearDividers(List<ProductivityPoint> points) {
    if (grouping != ChartGrouping.monthly) return const [];
    final lines = <VerticalLine>[];
    for (var i = 1; i < points.length; i++) {
      if (points[i].bucketStart.year != points[i - 1].bucketStart.year) {
        lines.add(
          VerticalLine(
            x: i.toDouble() - 0.5,
            color: AppColors.textSecondary.withValues(alpha: 0.6),
            strokeWidth: 1,
            dashArray: const [4, 4],
            label: VerticalLineLabel(
              show: true,
              alignment: Alignment.topRight,
              labelResolver: (_) => '${points[i].bucketStart.year}',
              style:
                  const TextStyle(fontSize: 10, color: AppColors.textSecondary),
            ),
          ),
        );
      }
    }
    return lines;
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Center(
        child: NotebookEmptyState(
          icon: Icons.calendar_month_outlined,
          text: message,
        ),
      );
}

class _EmptyOverlay extends StatelessWidget {
  const _EmptyOverlay();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.show_chart,
          size: 48,
          color: theme.colorScheme.onSurface.withValues(alpha: 0.25),
        ),
        const SizedBox(height: 8),
        Text(
          context.l10n.chartEmptyNote,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
          ),
        ),
      ],
    );
  }
}
