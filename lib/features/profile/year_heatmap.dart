import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/utils/date_utils.dart';
import '../../data/models/day_stats.dart';
import '../../data/repositories/stats_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/l10n_extensions.dart';

/// Тепловая карта года (в духе GitHub): колонки — недели, строки — дни недели
/// (Пн…Вс). Цвет ячейки = составной скор дня `P × (0.7 + 0.3·T)` (продуктивность
/// с учётом своевременности, БЕЗ веса за объём — он для сравнения периодов).
/// Дни без задач — нейтральные. Объём и «в срок» — в тултипе.
class YearHeatmap extends ConsumerWidget {
  const YearHeatmap({super.key, this.weeks = 53});

  /// Сколько недель показать (вплоть до текущей включительно).
  final int weeks;

  static const _cell = 11.0;
  static const _gap = 3.0;
  static const _col = _cell + _gap;
  static const _monthRowH = 16.0;
  static const _labelW = 24.0;

  static List<String> _months(AppLocalizations l10n) => [
        l10n.monthShortJan,
        l10n.monthShortFeb,
        l10n.monthShortMar,
        l10n.monthShortApr,
        l10n.monthShortMay,
        l10n.monthShortJun,
        l10n.monthShortJul,
        l10n.monthShortAug,
        l10n.monthShortSep,
        l10n.monthShortOct,
        l10n.monthShortNov,
        l10n.monthShortDec,
      ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final months = _months(l10n);
    final statsAsync = ref.watch(allDayStatsProvider);
    final stats = statsAsync.value;
    if (stats == null) {
      return const SizedBox(
        height: 120,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final byDay = <DateTime, DayStats>{
      for (final s in stats) dateOnly(s.date): s,
    };
    final todayD = today();
    final lastWeekStart = startOfWeek(todayD);
    final firstWeekStart =
        lastWeekStart.subtract(Duration(days: 7 * (weeks - 1)));

    // Подписи месяцев: над колонкой, где начинается новый месяц.
    final monthLabels = <Widget>[];
    int? prevMonth;
    for (var w = 0; w < weeks; w++) {
      final ws = firstWeekStart.add(Duration(days: 7 * w));
      if (ws.month != prevMonth) {
        prevMonth = ws.month;
        monthLabels.add(Positioned(
          left: w * _col,
          child: Text(
            months[ws.month - 1],
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
            ),
          ),
        ));
      }
    }

    // Сетка недель.
    final columns = <Widget>[];
    for (var w = 0; w < weeks; w++) {
      final dayCells = <Widget>[];
      for (var d = 0; d < 7; d++) {
        final date = firstWeekStart.add(Duration(days: 7 * w + d));
        dayCells.add(Padding(
          padding: const EdgeInsets.only(bottom: _gap),
          child: _Cell(
            date: date,
            stats: byDay[date],
            isFuture: date.isAfter(todayD),
          ),
        ));
      }
      columns.add(Padding(
        padding: const EdgeInsets.only(right: _gap),
        child: Column(mainAxisSize: MainAxisSize.min, children: dayCells),
      ));
    }

    final grid = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: _monthRowH,
          width: weeks * _col,
          child: Stack(clipBehavior: Clip.none, children: monthLabels),
        ),
        Row(mainAxisSize: MainAxisSize.min, children: columns),
      ],
    );

    // Подписи дней недели слева (Пн/Ср/Пт).
    final weekdayLabels = [
      l10n.weekdayShortMon,
      '',
      l10n.weekdayShortWed,
      '',
      l10n.weekdayShortFri,
      '',
      '',
    ];
    final weekdayColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: _monthRowH),
        for (final l in weekdayLabels)
          SizedBox(
            height: _cell + _gap,
            width: _labelW,
            child: Text(
              l,
              style: theme.textTheme.labelSmall?.copyWith(
                fontSize: 9,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            weekdayColumn,
            Expanded(child: _EndAlignedScroll(child: grid)),
          ],
        ),
        const SizedBox(height: 8),
        _Legend(),
      ],
    );
  }
}

/// Горизонтальный скролл, открывающийся у правого края (сегодня).
/// Порядок недель естественный (старые слева, сегодня справа).
class _EndAlignedScroll extends StatefulWidget {
  const _EndAlignedScroll({required this.child});
  final Widget child;

  @override
  State<_EndAlignedScroll> createState() => _EndAlignedScrollState();
}

class _EndAlignedScrollState extends State<_EndAlignedScroll> {
  final _controller = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_controller.hasClients) {
        _controller.jumpTo(_controller.position.maxScrollExtent);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      controller: _controller,
      child: widget.child,
    );
  }
}

// Сплошные (непрозрачные) палитры — НЕ через alpha, иначе бледные клетки
// сливаются с фоном карточки. По образцу GitHub, отдельно для светлой/тёмной.
const _emptyLight = Color(0xFFEBEDF0);
const _emptyDark = Color(0xFF2D333B);
const _greensLight = [
  Color(0xFF9BE9A8),
  Color(0xFF40C463),
  Color(0xFF30A14E),
  Color(0xFF216E39),
];
const _greensDark = [
  Color(0xFF0E4429),
  Color(0xFF006D32),
  Color(0xFF26A641),
  Color(0xFF39D353),
];

/// Цвет ячейки по составному скору. null/нет задач → нейтральный.
Color cellColor(DayStats? s, ThemeData theme) {
  final dark = theme.brightness == Brightness.dark;
  if (s == null || s.totalTasks == 0) {
    return dark ? _emptyDark : _emptyLight;
  }
  final p = s.productivity ?? 0.0;
  final t = s.timeliness ?? 1.0;
  final score = p * (0.7 + 0.3 * t); // 0..1
  final level = score <= 0 ? 1 : (score * 4).ceil().clamp(1, 4);
  return (dark ? _greensDark : _greensLight)[level - 1];
}

class _Cell extends StatelessWidget {
  const _Cell({required this.date, required this.stats, required this.isFuture});
  final DateTime date;
  final DayStats? stats;
  final bool isFuture;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (isFuture) {
      // Будущие дни — пустое место (держим выравнивание сетки).
      return const SizedBox(width: YearHeatmap._cell, height: YearHeatmap._cell);
    }
    return Tooltip(
      message: _tip(context),
      triggerMode: TooltipTriggerMode.tap,
      showDuration: const Duration(seconds: 3),
      preferBelow: false,
      child: Container(
        width: YearHeatmap._cell,
        height: YearHeatmap._cell,
        decoration: BoxDecoration(
          color: cellColor(stats, theme),
          borderRadius: BorderRadius.circular(2),
          border: Border.all(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.07),
            width: 0.5,
          ),
        ),
      ),
    );
  }

  String _tip(BuildContext context) {
    final l10n = context.l10n;
    final locale = Localizations.localeOf(context).languageCode;
    final d = DateFormat('d MMMM y', locale).format(date);
    final s = stats;
    if (s == null || s.totalTasks == 0) return '$d\n${l10n.noTasksNote}';
    final pct = ((s.productivity ?? 0) * 100).round();
    final ot = s.timeliness;
    final otStr = ot == null ? '—' : '${(ot * 100).round()}%';
    return '$d\n${l10n.heatmapTooltip(s.completedTasks, s.totalTasks, pct, otStr)}';
  }
}

class _Legend extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    DayStats fake(double prod) => DayStats(
          date: DateTime(2000),
          totalTasks: 1,
          completedTasks: 1,
          completedFraction: prod,
          onTimeCount: 1,
          lateCount: 0,
          updatedAt: DateTime(2000),
        );
    final swatches = <Color>[
      cellColor(null, theme), // пусто
      cellColor(fake(0.2), theme),
      cellColor(fake(0.5), theme),
      cellColor(fake(0.8), theme),
      cellColor(fake(1.0), theme),
    ];
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text(context.l10n.lessLabel,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
            )),
        const SizedBox(width: 6),
        for (final c in swatches)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 1.5),
            child: Container(
              width: 11,
              height: 11,
              decoration: BoxDecoration(
                color: c,
                borderRadius: BorderRadius.circular(2),
                border: Border.all(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.07),
                  width: 0.5,
                ),
              ),
            ),
          ),
        const SizedBox(width: 6),
        Text(context.l10n.moreLabel,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
            )),
      ],
    );
  }
}
