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
import 'week_stats.dart';

/// Итоги недели: продуктивность с дельтой к прошлой неделе, задачи, лучший
/// день, идеальные дни, цели недели, достигнутые цели, средняя оценка дней
/// (рефлексия). Всё считается из УЖЕ собранных данных — никаких новых вводов.
class RetrospectiveScreen extends ConsumerStatefulWidget {
  const RetrospectiveScreen({super.key});

  @override
  ConsumerState<RetrospectiveScreen> createState() =>
      _RetrospectiveScreenState();
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
        loading ? null : computeWeekStats(_weekStart, allStats, goals, ratings);
    final prev = loading
        ? null
        : computeWeekStats(
            _weekStart.subtract(const Duration(days: 7)),
            allStats,
            goals,
            ratings,
          );

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
                  // Цели именно на эту неделю — показываем всегда, в том
                  // числе когда их не ставили: «целей не было» это тоже
                  // ответ, и без него неделя без целей выглядит так же, как
                  // неделя, где про цели просто забыли посмотреть.
                  const SizedBox(height: 8),
                  _weekGoalsCard(theme, l10n, stats),
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
      ThemeData theme, AppLocalizations l10n, WeekStats s, WeekStats prev) {
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

  Widget _miniRow(ThemeData theme, AppLocalizations l10n, WeekStats s) {
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
    final weekday = weekdayNames(l10n)[d.weekday - 1];
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

  /// Цели, поставленные ИМЕННО на эту неделю: «достигнуто N из M» + список.
  /// Когда таких целей не было — говорим об этом прямо, а не прячем карточку.
  Widget _weekGoalsCard(ThemeData theme, AppLocalizations l10n, WeekStats s) {
    if (s.weekGoals.isEmpty) {
      return Card(
        child: ListTile(
          leading: const Text('📌', style: TextStyle(fontSize: 26)),
          title: Text(l10n.weekGoalsNoneTitle),
          subtitle: Text(l10n.weekGoalsNoneSubtitle),
        ),
      );
    }
    final done = s.weekGoalsDone;
    final missed = s.weekGoals.where((g) => !g.completed).toList();
    final preview = missed.take(3).map((g) => g.title).join(' · ');
    // Grace-окно недели ещё открыто — недостигнутое можно закрыть, и об этом
    // честнее сказать, чем показывать «1 из 3» как окончательный счёт.
    final graceEnd = missed.isEmpty ? null : weekGoalsGraceEnd(_weekStart);
    return Card(
      child: ListTile(
        isThreeLine: graceEnd != null,
        leading: const Text('📌', style: TextStyle(fontSize: 26)),
        title: Text(l10n.weekGoalsTitle(done, s.weekGoals.length)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (missed.isEmpty)
              Text(l10n.weekGoalsAllDone)
            else
              // Полный список незакрытых — по наведению/долгому нажатию:
              // превью обрезано и по числу целей, и по ширине карточки.
              Tooltip(
                message: missed.map((g) => g.title).join('\n'),
                child: Text(
                  l10n.weekGoalsMissed(
                    missed.length > 3 ? '$preview …' : preview,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            if (graceEnd != null)
              Text(
                l10n.weekGoalsGraceNote(
                  weekdayNames(l10n)[graceEnd.weekday - 1],
                ),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: AppColors.warning,
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
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
        subtitle: Tooltip(
          message: goals.map((g) => g.title).join('\n'),
          child: Text(
            goals.length > 3 ? '$preview …' : preview,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
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
