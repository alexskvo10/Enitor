import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/appearance.dart';
import '../../data/models/goal.dart';
import '../../data/repositories/goal_repository.dart';
import '../../data/repositories/stats_repository.dart' show ChartGrouping;
import '../../l10n/l10n_extensions.dart';
import '../../widgets/error_view.dart';

/// График целей: выполнение + своевременность.
///
/// [periodType] — какие цели анализируем; [grouping] — гранулярность точки.
/// Смысл значения точки задаётся в data-слое ([GoalRepository]):
/// • точка ≥ период → среднее итогов периодов в бакете (агрегатный режим);
/// • точка мельче периода → нарастающий итог целей содержащего периода со
///   сбросом на границе периода (накопительный режим) + пунктирные границы,
///   подписанные итогом завершившегося периода.
class GoalProductivityChart extends ConsumerStatefulWidget {
  const GoalProductivityChart({
    super.key,
    required this.from,
    required this.to,
    required this.periodType,
    required this.grouping,
  });

  final DateTime from;
  final DateTime to;

  /// null — режим «Общий» (среднее колец всех типов периодов).
  final GoalPeriod? periodType;
  final ChartGrouping grouping;

  @override
  ConsumerState<GoalProductivityChart> createState() =>
      _GoalProductivityChartState();
}

class _GoalProductivityChartState extends ConsumerState<GoalProductivityChart> {
  static const _colorOnTime = Color(0xFFFFA726); // amber 400

  /// Контрастные, разнесённые по тону цвета границ по типам периода (режим
  /// «Общий»). Синий не берём — сольётся с линией выполнения (indigo primary),
  /// янтарный — с линией своевременности. Красный/фиолетовый/зелёный/бирюзовый
  /// различимы и между собой, и на фоне обеих линий.
  static const _boundaryColors = <GoalPeriod, Color>{
    GoalPeriod.week: Color(0xFF1E88E5), // синий
    GoalPeriod.month: Color(0xFF9C27B0), // фиолетовый
    GoalPeriod.season: Color(0xFF43A047), // зелёный
    GoalPeriod.year: Color(0xFFE53935), // красный
  };

  /// Типы, чьи границы СКРЫТЫ пользователем (режим «Общий»). По умолчанию все
  /// видимы; новые типы (появившиеся в данных) остаются видимыми.
  final Set<GoalPeriod> _hiddenBoundaries = {};

  @override
  Widget build(BuildContext context) {
    final range = GoalChartRange(
        period: widget.periodType,
        grouping: widget.grouping,
        from: widget.from,
        to: widget.to);
    final chartAsync = ref.watch(goalChartProvider(range));

    return chartAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorView(
        compact: true,
        onRetry: () => ref.invalidate(goalChartProvider(range)),
      ),
      data: (chart) {
        final rawPoints = chart.points;
        if (rawPoints.isEmpty) {
          return _EmptyState(message: context.l10n.rangeTooShortNote);
        }

        // Обрезаем пустые бакеты слева (до первых данных).
        final firstIdx = rawPoints.indexWhere((p) => p.value != null);
        final points = firstIdx <= 0 ? rawPoints : rawPoints.sublist(firstIdx);

        final prodSpots = <FlSpot>[];
        for (var i = 0; i < points.length; i++) {
          final v = points[i].value;
          if (v != null) prodSpots.add(FlSpot(i.toDouble(), v * 100));
        }
        final onTimeSpots = <FlSpot>[];
        for (var i = 0; i < points.length; i++) {
          final v = points[i].onTimeValue;
          if (v != null) onTimeSpots.add(FlSpot(i.toDouble(), v * 100));
        }

        final hasData = prodSpots.isNotEmpty;
        final hasOnTimeData = onTimeSpots.isNotEmpty;
        final showDots = points.length <= 40;

        const xPad = 0.4;
        final maxX = (points.length - 1).toDouble().clamp(1.0, double.infinity);

        // Прямые линии в обоих режимах: единообразно, а в накопительном ещё
        // и честнее (накопление дискретно, скачками на датах завершения) —
        // и сглаживание не даёт выброса на сбросе к границе периода.
        final bars = <LineChartBarData>[];
        if (hasData) {
          bars.add(LineChartBarData(
            spots: prodSpots,
            isCurved: false,
            color: AppColors.primary,
            barWidth: 3,
            isStrokeCapRound: true,
            dotData: FlDotData(show: showDots),
            belowBarData: BarAreaData(
              show: true,
              color: AppColors.primary.withValues(alpha: 0.08),
            ),
          ));
        }
        if (hasOnTimeData) {
          bars.add(LineChartBarData(
            spots: onTimeSpots,
            isCurved: false,
            color: _colorOnTime,
            barWidth: 2,
            isStrokeCapRound: true,
            dotData: FlDotData(show: showDots),
            belowBarData: BarAreaData(
              show: true,
              color: _colorOnTime.withValues(alpha: 0.06),
            ),
          ));
        }

        // Легенда границ (режим «Общий») — только реально присутствующие типы.
        final boundaryTypes = <GoalPeriod>{};
        if (chart.overall) {
          for (final p in points) {
            boundaryTypes.addAll(p.boundaries);
          }
        }

        return Column(
          children: [
            if (hasOnTimeData)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _LegendDot(color: AppColors.primary),
                    const SizedBox(width: 4),
                    Text(context.l10n.goalCompletionLegendLabel,
                        style: const TextStyle(fontSize: 11)),
                    const SizedBox(width: 16),
                    _LegendDot(color: _colorOnTime),
                    const SizedBox(width: 4),
                    Text(context.l10n.onTimeLegendLabel,
                        style: const TextStyle(fontSize: 11)),
                  ],
                ),
              ),
            // Переключатели видимости границ периодов (режим «Общий») — в шапке
            // карточки, справа; включаются/выключаются по одному, без меню.
            if (boundaryTypes.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: SizedBox(
                  width: double.infinity,
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 4,
                    runSpacing: 2,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: 2),
                        child: Text('${context.l10n.boundariesShort}:',
                            style: const TextStyle(
                                fontSize: 10, color: AppColors.textSecondary)),
                      ),
                      for (final t
                          in GoalPeriod.values.where(boundaryTypes.contains))
                        _BoundaryToggle(
                          color: _boundaryColors[t]!,
                          label: _boundaryLegendLabel(context, t),
                          on: !_hiddenBoundaries.contains(t),
                          onTap: () => setState(() {
                            if (!_hiddenBoundaries.remove(t)) {
                              _hiddenBoundaries.add(t);
                            }
                          }),
                        ),
                    ],
                  ),
                ),
              ),
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
                            final firstX = touchedSpots.isNotEmpty
                                ? touchedSpots.first.x.round()
                                : -1;
                            // Подпись = дата САМОЙ точки в её гранулярности
                            // (для Точка=День — «15 марта 2026», не месяц).
                            // НО последняя точка периода (isPeriodEnd) = итог
                            // периода → подписываем периодом («март 2026 · итог»),
                            // так ховер у границы даёт именно итог периода.
                            final label =
                                (firstX >= 0 && firstX < points.length)
                                    ? _tooltipLabel(context, points[firstX])
                                    : null;

                            return touchedSpots.map((s) {
                              final isFirst = s == touchedSpots.first;
                              final pct = s.y;
                              final pctStr = pct == pct.roundToDouble()
                                  ? '${pct.toInt()}%'
                                  : '${pct.toStringAsFixed(1)}%';
                              final isOnTime = s.barIndex == 1;

                              if (isFirst && label != null) {
                                return LineTooltipItem(
                                  label,
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
                        verticalLines: _dividers(chart, points),
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

  /// Заголовок тултипа: для итоговой точки периода — подпись периода +
  /// пометка «итог» (это значение = итог периода, доступный по ховеру у
  /// границы); иначе — дата самой точки в её гранулярности.
  String _tooltipLabel(BuildContext context, GoalProductivityPoint p) {
    if (widget.periodType != null && p.isPeriodEnd && p.periodStart != null) {
      final ru = Localizations.localeOf(context).languageCode == 'ru';
      final period = GoalPeriodRef.current(widget.periodType!, p.periodStart!)
          .labelFor(ru);
      return '$period · ${context.l10n.goalPeriodTotalHint}';
    }
    return _bucketLabel(context, p.bucketStart);
  }

  // Подпись бакета по гранулярности точки (как у графика задач).
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

  String _boundaryLegendLabel(BuildContext context, GoalPeriod t) {
    final l10n = context.l10n;
    return switch (t) {
      GoalPeriod.week => l10n.goalsPeriodWeek,
      GoalPeriod.month => l10n.goalsPeriodMonth,
      GoalPeriod.season => l10n.goalsPeriodSeason,
      GoalPeriod.year => l10n.goalsPeriodYear,
    };
  }

  String _bucketLabel(BuildContext context, DateTime d) {
    final ru = Localizations.localeOf(context).languageCode == 'ru';
    final monthGen = ru ? _monthGenRu : _monthEn;
    final monthNom = ru ? _monthNomRu : _monthEn;
    switch (widget.grouping) {
      case ChartGrouping.daily:
        return '${d.day} ${monthGen[d.month]} ${d.year}';
      case ChartGrouping.weekly:
        final end = d.add(const Duration(days: 6));
        if (d.month == end.month) {
          return '${d.day}–${end.day} ${monthGen[d.month]} ${d.year}';
        } else if (d.year == end.year) {
          final sm = monthGen[d.month].substring(0, 3);
          final em = monthGen[end.month].substring(0, 3);
          return '${d.day} $sm – ${end.day} $em ${d.year}';
        } else {
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

  double _bottomReservedSize() =>
      widget.grouping == ChartGrouping.weekly ? 40 : 28;

  Widget _buildBottomTitle(
      BuildContext context, double v, List<GoalProductivityPoint> points) {
    final locale = Localizations.localeOf(context).languageCode;
    final i = v.round();
    if ((v - i).abs() > 0.1) return const SizedBox();
    if (i < 0 || i >= points.length) return const SizedBox();
    final d = points[i].bucketStart;

    switch (widget.grouping) {
      case ChartGrouping.daily:
        return Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(DateFormat('dd.MM').format(d),
              style: const TextStyle(fontSize: 10)),
        );
      case ChartGrouping.weekly:
        final end = d.add(const Duration(days: 6));
        return Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(DateFormat('dd.MM').format(d),
                  style: const TextStyle(fontSize: 9)),
              Text(DateFormat('dd.MM').format(end),
                  style: const TextStyle(fontSize: 9)),
            ],
          ),
        );
      case ChartGrouping.monthly:
        return Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(DateFormat.MMM(locale).format(d),
              style: const TextStyle(fontSize: 10)),
        );
      case ChartGrouping.yearly:
        return Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text('${d.year}', style: const TextStyle(fontSize: 10)),
        );
    }
  }

  /// Вертикальные разделители:
  /// • накопительный режим — граница КАЖДОГО периода (там линия сбрасывается),
  ///   подпись = итог только что завершившегося периода (значение левой точки,
  ///   она всегда итоговая);
  /// • агрегатный режим — разделители годов (как у задач с месячной
  ///   группировкой), для ориентира на длинном диапазоне.
  List<VerticalLine> _dividers(
      GoalChartData chart, List<GoalProductivityPoint> points) {
    final lines = <VerticalLine>[];
    if (chart.overall) {
      // «Общий»: у каждого бакета могут начинаться экземпляры разных типов —
      // рисуем по границе на тип своим цветом (различимо), без подписи.
      // Скрытые пользователем типы (через меню в углу) пропускаем.
      for (var i = 1; i < points.length; i++) {
        for (final t in points[i].boundaries) {
          if (_hiddenBoundaries.contains(t)) continue;
          lines.add(VerticalLine(
            x: i.toDouble() - 0.5,
            color: (_boundaryColors[t] ?? AppColors.textSecondary)
                .withValues(alpha: 0.55),
            strokeWidth: 1,
            dashArray: const [4, 4],
          ));
        }
      }
    } else if (chart.cumulative) {
      // Пунктир — только визуальный маркер границы периода (без подписи:
      // при большом «Показать за» подписи налезали друг на друга). Итог
      // периода доступен по ховеру на последней точке периода (isPeriodEnd,
      // подписан периодом + %/⏰), точка стоит слева от пунктира.
      for (var i = 1; i < points.length; i++) {
        if (points[i].periodStart != points[i - 1].periodStart) {
          lines.add(VerticalLine(
            x: i.toDouble() - 0.5,
            color: AppColors.textSecondary.withValues(alpha: 0.5),
            strokeWidth: 1,
            dashArray: const [4, 4],
          ));
        }
      }
    } else if (widget.grouping == ChartGrouping.monthly) {
      for (var i = 1; i < points.length; i++) {
        if (points[i].bucketStart.year != points[i - 1].bucketStart.year) {
          lines.add(VerticalLine(
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
          ));
        }
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

/// Короткий «пунктирный» штрих для легенды границ (режим «Общий»).
class _DashMark extends StatelessWidget {
  const _DashMark({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: 16,
        height: 3,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(2),
        ),
      );
}

/// Инлайн-переключатель видимости границ одного типа (режим «Общий»): цветной
/// штрих + подпись; выключенный — приглушён и зачёркнут. Тап переключает сразу.
class _BoundaryToggle extends StatelessWidget {
  const _BoundaryToggle({
    required this.color,
    required this.label,
    required this.on,
    required this.onTap,
  });

  final Color color;
  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).colorScheme.onSurface;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _DashMark(color: on ? color : base.withValues(alpha: 0.25)),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: base.withValues(alpha: on ? 0.8 : 0.35),
                decoration: on ? null : TextDecoration.lineThrough,
              ),
            ),
          ],
        ),
      ),
    );
  }
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
          context.l10n.goalChartEmptyNote,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
          ),
        ),
      ],
    );
  }
}
