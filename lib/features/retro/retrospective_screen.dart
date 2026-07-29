import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/appearance.dart';
import '../../core/utils/date_utils.dart';
import '../../data/models/day_stats.dart';
import '../../data/models/goal.dart';
import '../../data/repositories/goal_repository.dart';
import '../../data/repositories/rating_repository.dart';
import '../../data/repositories/stats_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/l10n_extensions.dart';
import '../../widgets/delta_indicator.dart';

/// Итоги недели: продуктивность с дельтой к прошлой неделе, задачи, лучший
/// день, идеальные дни, достигнутые цели, средняя оценка дней (рефлексия).
/// Всё считается из УЖЕ собранных данных — никаких новых вводов.
class RetrospectiveScreen extends ConsumerStatefulWidget {
  const RetrospectiveScreen({super.key});

  @override
  ConsumerState<RetrospectiveScreen> createState() =>
      _RetrospectiveScreenState();
}

/// Сводка одной недели.
class _WeekStats {
  double? avgProductivity;
  double? avgOnTime;
  int totalTasks = 0;
  int completedTasks = 0;
  int perfectDays = 0;
  int daysWithData = 0;
  DayStats? bestDay;
  double? avgDayRating;
  List<Goal> goalsDone = [];

  bool get isEmpty => daysWithData == 0 && goalsDone.isEmpty;
}

class _RetrospectiveScreenState extends ConsumerState<RetrospectiveScreen> {
  /// Понедельник просматриваемой недели. По умолчанию — последняя ЗАВЕРШЁННАЯ.
  late DateTime _weekStart;

  @override
  void initState() {
    super.initState();
    _weekStart = startOfWeek(today()).subtract(const Duration(days: 7));
  }

  bool get _isCurrentWeek => _weekStart == startOfWeek(today());

  static List<String> _weekdays(AppLocalizations l10n) => [
        l10n.weekdayMonday,
        l10n.weekdayTuesday,
        l10n.weekdayWednesday,
        l10n.weekdayThursday,
        l10n.weekdayFriday,
        l10n.weekdaySaturday,
        l10n.weekdaySunday,
      ];

  _WeekStats _compute(
    DateTime weekStart,
    List<DayStats> allStats,
    List<Goal> goals,
    Map<String, int> ratings,
  ) {
    final res = _WeekStats();
    final weekEnd = weekStart.add(const Duration(days: 6));
    bool inWeek(DateTime d) =>
        !dateOnly(d).isBefore(weekStart) && !dateOnly(d).isAfter(weekEnd);

    final todayDate = today();
    var prodSum = 0.0;
    var onTimeSum = 0.0;
    var onTimeDays = 0;
    var bestScore = -1.0;

    for (final s in allStats) {
      if (!inWeek(s.date) || s.date.isAfter(todayDate)) continue;
      res.totalTasks += s.totalTasks;
      res.completedTasks += s.completedTasks;
      final p = s.productivity;
      if (p == null) continue;
      res.daysWithData++;
      prodSum += p;
      if (p >= 1.0 - 1e-9 && s.totalTasks > 0) res.perfectDays++;
      final t = s.timeliness;
      if (t != null) {
        onTimeSum += t;
        onTimeDays++;
      }
      // Лучший день — составной скор с весом за объём (как в профиле).
      // Тайбрейк при равном скоре: более поздняя дата — детерминированно,
      // независимо от порядка обхода allStats.
      final score = p * (0.7 + 0.3 * (t ?? 1.0)) * volumeWeight(s.totalTasks);
      final better = score > bestScore + 1e-9 ||
          ((score - bestScore).abs() < 1e-9 &&
              res.bestDay != null &&
              dateOnly(s.date).isAfter(dateOnly(res.bestDay!.date)));
      if (res.bestDay == null || better) {
        bestScore = score;
        res.bestDay = s;
      }
    }
    if (res.daysWithData > 0) {
      res.avgProductivity = prodSum / res.daysWithData;
    }
    if (onTimeDays > 0) res.avgOnTime = onTimeSum / onTimeDays;

    // Цели, достигнутые на этой неделе (любого типа периода).
    res.goalsDone = goals
        .where((g) => g.completedAt != null && inWeek(g.completedAt!))
        .toList();

    // Средняя оценка дней (рефлексия 1..10) — только оценённые дни.
    final weekRatings = <int>[];
    for (var i = 0; i < 7; i++) {
      final key = RatingRepository.dayKey(weekStart.add(Duration(days: i)));
      final r = ratings[key];
      if (r != null) weekRatings.add(r);
    }
    if (weekRatings.isNotEmpty) {
      res.avgDayRating =
          weekRatings.fold<int>(0, (a, b) => a + b) / weekRatings.length;
    }
    return res;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final ru = Localizations.localeOf(context).languageCode == 'ru';
    final allStats = ref.watch(allDayStatsProvider).value;
    final goals = ref.watch(allGoalsProvider).value;
    final ratings = ref.watch(dayRatingsMapProvider).value;

    final loading = allStats == null || goals == null || ratings == null;
    final stats =
        loading ? null : _compute(_weekStart, allStats, goals, ratings);
    final prev = loading
        ? null
        : _compute(_weekStart.subtract(const Duration(days: 7)), allStats,
            goals, ratings);

    final weekLabel = GoalPeriodRef(
      period: GoalPeriod.week,
      year: _weekStart.year,
      weekStart: _weekStart,
    ).labelFor(ru);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.weekSummaryScreenTitle)),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                // ── Навигация по неделям ──────────────────────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left),
                      tooltip: l10n.prevWeekTooltip,
                      onPressed: () => setState(() => _weekStart =
                          _weekStart.subtract(const Duration(days: 7))),
                    ),
                    Flexible(
                      child: Text(
                        weekLabel,
                        style: theme.textTheme.titleMedium,
                        textAlign: TextAlign.center,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_right),
                      tooltip: l10n.nextWeekTooltip,
                      onPressed: _isCurrentWeek
                          ? null
                          : () => setState(() => _weekStart =
                              _weekStart.add(const Duration(days: 7))),
                    ),
                  ],
                ),
                if (_isCurrentWeek)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      l10n.weekInProgressNote,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.warning,
                      ),
                    ),
                  ),
                if (stats!.isEmpty)
                  NotebookEmptyState(
                    icon: Icons.insights_outlined,
                    text: l10n.noDataThisWeek,
                  )
                else ...[
                  _heroCard(theme, l10n, stats, prev!),
                  const SizedBox(height: 8),
                  _miniRow(theme, l10n, stats),
                  if (stats.bestDay != null) ...[
                    const SizedBox(height: 8),
                    _bestDayCard(theme, l10n, stats.bestDay!),
                  ],
                  if (stats.goalsDone.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _goalsCard(theme, l10n, stats.goalsDone),
                  ],
                  if (stats.avgDayRating != null) ...[
                    const SizedBox(height: 8),
                    _ratingCard(theme, l10n, stats.avgDayRating!),
                  ],
                ],
              ],
            ),
    );
  }

  /// Главная карточка: продуктивность недели + дельта к прошлой.
  Widget _heroCard(
      ThemeData theme, AppLocalizations l10n, _WeekStats s, _WeekStats prev) {
    final avg = s.avgProductivity;
    final delta = (avg != null && prev.avgProductivity != null)
        ? (avg - prev.avgProductivity!) * 100
        : null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.weekProductivityLabel,
                      style: theme.textTheme.bodySmall),
                  const SizedBox(height: 4),
                  Text(
                    avg == null ? '—' : '${(avg * 100).round()}%',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    l10n.daysWithDataLabel(s.daysWithData),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                DeltaIndicator(deltaPercent: delta),
                Text(
                  l10n.vsLastWeekLabel,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _miniRow(ThemeData theme, AppLocalizations l10n, _WeekStats s) {
    Widget cell(String value, String caption) => Expanded(
          child: Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
              child: Column(
                children: [
                  Text(
                    value,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    caption,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color:
                          theme.colorScheme.onSurface.withValues(alpha: 0.55),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );

    return Row(
      children: [
        cell('${s.completedTasks}/${s.totalTasks}', l10n.tasksDoneCaption),
        const SizedBox(width: 8),
        cell(
          s.avgOnTime == null ? '—' : '${(s.avgOnTime! * 100).round()}%',
          l10n.onTimeCaptionRetro,
        ),
        const SizedBox(width: 8),
        cell('${s.perfectDays}', l10n.perfectDaysCaption),
      ],
    );
  }

  Widget _bestDayCard(ThemeData theme, AppLocalizations l10n, DayStats best) {
    final d = dateOnly(best.date);
    final weekday = _weekdays(l10n)[d.weekday - 1];
    return Card(
      child: ListTile(
        leading: const Text('🏆', style: TextStyle(fontSize: 26)),
        title: Text(l10n.bestDayTitle(weekday)),
        subtitle: Text(
          '${l10n.completedOfTasks(best.completedTasks, best.totalTasks)} · '
          '${((best.productivity ?? 0) * 100).round()}%',
        ),
      ),
    );
  }

  Widget _goalsCard(ThemeData theme, AppLocalizations l10n, List<Goal> goals) {
    final preview = goals.take(3).map((g) => g.title).join(' · ');
    return Card(
      child: ListTile(
        leading: const Text('🎯', style: TextStyle(fontSize: 26)),
        title: Text(l10n.goalsAchievedCount(goals.length)),
        subtitle: Text(
          goals.length > 3 ? '$preview …' : preview,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  Widget _ratingCard(ThemeData theme, AppLocalizations l10n, double avg) {
    return Card(
      child: ListTile(
        leading: const Text('⭐', style: TextStyle(fontSize: 26)),
        title: Text(l10n.avgDayRating(avg.toStringAsFixed(1))),
        subtitle: Text(l10n.byEveningRatingsNote),
      ),
    );
  }
}
