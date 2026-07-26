import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../data/models/goal.dart';
import '../../data/repositories/achievements_repository.dart';
import '../../data/repositories/goal_repository.dart';
import '../../data/repositories/profile_repository.dart';
import '../../data/repositories/stats_repository.dart';
import '../../data/repositories/task_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/l10n_extensions.dart';
import '../../widgets/delta_indicator.dart';
import '../../widgets/error_view.dart';
import '../achievements/achievements_screen.dart';
import '../retro/retrospective_screen.dart';
import 'year_heatmap.dart';

/// Профиль пользователя: дата начала, дней в приложении, средняя продуктивность
/// + дельта к прошлой неделе.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final profileAsync = ref.watch(profileProvider);
    final avgAsync = ref.watch(allTimeAverageProvider);
    final onTimeAvgAsync = ref.watch(allTimeOnTimeAverageProvider);
    final tasks = ref.watch(allTasksProvider).value;
    final goals = ref.watch(allGoalsProvider).value;
    final best = ref.watch(bestPeriodsProvider).value;
    final streaks = ref.watch(streaksProvider).value;
    final achievements = ref.watch(achievementsProvider);

    final tasksTotal = tasks?.length ?? 0;
    final tasksDone = tasks?.where((t) => t.isCompleted).length ?? 0;
    final goalsTotal = goals?.length ?? 0;
    final goalsDone = goals?.where((g) => g.completed).length ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.profileTitle),
        actions: [
          IconButton(
            tooltip: l10n.settingsTooltip,
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: profileAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(onRetry: () => ref.invalidate(profileProvider)),
        data: (profile) {
          if (profile == null) return const SizedBox();
          final locale = Localizations.localeOf(context).languageCode;
          final daysUsing =
              DateTime.now().difference(profile.startedAt).inDays + 1;
          final avg = avgAsync.value;
          final delta = (avg != null && profile.lastWeekAvgProductivity != null)
              ? (avg - profile.lastWeekAvgProductivity!) * 100
              : null;
          final onTimeAvg = onTimeAvgAsync.value;
          final onTimeDelta =
              (onTimeAvg != null && profile.lastWeekOnTimeAverage != null)
                  ? (onTimeAvg - profile.lastWeekOnTimeAverage!) * 100
                  : null;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // «С нами с» + «Дней в приложении» — в одну строку.
              _StatRow(
                left: _StatTile(
                  title: l10n.sinceUsTitle,
                  value: DateFormat('d MMMM y', locale)
                      .format(profile.startedAt),
                ),
                right: _StatTile(
                    title: l10n.daysUsingTitle, value: '$daysUsing'),
              ),
              // Серия — на всю ширину.
              if (streaks != null && streaks.best > 0)
                _StreakCard(current: streaks.current, best: streaks.best),
              // Средняя продуктивность + В срок — в одну строку.
              _StatRow(
                left: _StatTile(
                  title: l10n.avgProductivityAllTimeTitle,
                  value: avg == null
                      ? '—'
                      : '${(avg * 100).toStringAsFixed(1)}%',
                  trailing: DeltaIndicator(deltaPercent: delta, compact: true),
                ),
                right: _StatTile(
                  title: l10n.onTimeAllTimeTitle,
                  value: onTimeAvg == null
                      ? '—'
                      : '${(onTimeAvg * 100).toStringAsFixed(1)}%',
                  trailing:
                      DeltaIndicator(deltaPercent: onTimeDelta, compact: true),
                ),
              ),
              // Задач выполнено + Целей достигнуто — в одну строку.
              _StatRow(
                left: _StatTile(
                  title: l10n.tasksDoneTitle,
                  value: tasks == null
                      ? '—'
                      : l10n.doneOfTotal(tasksDone, tasksTotal),
                ),
                right: _StatTile(
                  title: l10n.goalsAchievedTitle,
                  value: goals == null
                      ? '—'
                      : l10n.doneOfTotal(goalsDone, goalsTotal),
                ),
              ),
              // ── Итоги недели (ретроспектива) ──────────────────────────────
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: const Text('📅', style: TextStyle(fontSize: 26)),
                  title: Text(l10n.weekSummaryTitle),
                  subtitle: Text(l10n.weekSummarySubtitle),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const RetrospectiveScreen(),
                    ),
                  ),
                ),
              ),
              // ── Тепловая карта года ───────────────────────────────────────
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.yearActivityLabel,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 12),
                      const YearHeatmap(),
                    ],
                  ),
                ),
              ),
              // ── Достижения ────────────────────────────────────────────────
              if (achievements.isNotEmpty) ...[
                const SizedBox(height: 8),
                _AchievementsTile(
                  unlocked: achievements.where((a) => a.unlocked).length,
                  total: achievements.length,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const AchievementsScreen(),
                    ),
                  ),
                ),
              ],
              // ── Лучшие периоды ────────────────────────────────────────────
              if (best != null && best.isNotEmpty) ...[
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 6),
                  child: Text(
                    l10n.bestPeriodsLabel,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.6),
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.3,
                        ),
                  ),
                ),
                for (final g in StatGranularity.values)
                  if (best[g] != null)
                    _BestTile(
                      title: _bestTitle(l10n, g),
                      label: _bestLabel(locale, g, best[g]!.start),
                      productivity: best[g]!.productivity,
                      onTimeRate: best[g]!.onTimeRate,
                    ),
              ],
            ],
          );
        },
      ),
    );
  }
}

String _bestTitle(AppLocalizations l10n, StatGranularity g) => switch (g) {
      StatGranularity.day => l10n.bestDayLabel,
      StatGranularity.week => l10n.bestWeekLabel,
      StatGranularity.month => l10n.bestMonthLabel,
      StatGranularity.season => l10n.bestSeasonLabel,
      StatGranularity.year => l10n.bestYearLabel,
    };

String _bestLabel(String locale, StatGranularity g, DateTime start) {
  final ru = locale == 'ru';
  switch (g) {
    case StatGranularity.day:
      return DateFormat('d MMMM y', locale).format(start);
    case StatGranularity.week:
      return GoalPeriodRef(
        period: GoalPeriod.week,
        year: start.year,
        weekStart: start,
      ).labelFor(ru);
    case StatGranularity.month:
      return GoalPeriodRef(
        period: GoalPeriod.month,
        year: start.year,
        month: start.month,
      ).labelFor(ru);
    case StatGranularity.season:
      final (y, idx) = seasonOf(start);
      return GoalPeriodRef(
        period: GoalPeriod.season,
        year: y,
        season: idx,
      ).labelFor(ru);
    case StatGranularity.year:
      return '${start.year}';
  }
}

class _BestTile extends StatelessWidget {
  const _BestTile({
    required this.title,
    required this.label,
    required this.productivity,
    required this.onTimeRate,
  });

  final String title;
  final String label;
  final double productivity;
  final double? onTimeRate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.bodySmall),
                  const SizedBox(height: 4),
                  Text(label, style: theme.textTheme.titleMedium),
                ],
              ),
            ),
            _metric(
              theme,
              value: '${(productivity * 100).round()}%',
              caption: context.l10n.productivityCaption,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 16),
            _metric(
              theme,
              value: onTimeRate == null
                  ? '—'
                  : '${(onTimeRate! * 100).round()}%',
              caption: context.l10n.onTimeCaption,
              color: AppColors.warning,
            ),
          ],
        ),
      ),
    );
  }

  Widget _metric(
    ThemeData theme, {
    required String value,
    required String caption,
    required Color color,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
        Text(
          caption,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
          ),
        ),
      ],
    );
  }
}

/// Карточка серий: текущая (🔥) и рекордная.
class _StreakCard extends StatelessWidget {
  const _StreakCard({required this.current, required this.best});

  final int current;
  final int best;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final active = current > 0;
    final accent = active ? Colors.deepOrange : theme.colorScheme.outline;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Text(
              active ? '🔥' : '💤',
              style: const TextStyle(fontSize: 36),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.streakLabel, style: theme.textTheme.bodySmall),
                  const SizedBox(height: 4),
                  Text(
                    active ? l10n.streakActive(current) : l10n.streakBroken,
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: accent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  l10n.streakBest(best),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  l10n.streakRecordLabel,
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
}

/// Карточка-кнопка «Достижения» с прогрессом получено/всего.
class _AchievementsTile extends StatelessWidget {
  const _AchievementsTile({
    required this.unlocked,
    required this.total,
    required this.onTap,
  });
  final int unlocked;
  final int total;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Text('🏅', style: TextStyle(fontSize: 30)),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(context.l10n.achievementsLabel,
                        style: theme.textTheme.bodySmall),
                    const SizedBox(height: 4),
                    Text(context.l10n.doneOfTotal(unlocked, total),
                        style: theme.textTheme.titleLarge),
                  ],
                ),
              ),
              Icon(Icons.chevron_right,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.4)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Две статкарточки в одну строку, равной высоты (IntrinsicHeight + stretch:
/// карточки выравниваются по самой высокой, даже если у одной заголовок длиннее).
class _StatRow extends StatelessWidget {
  const _StatRow({required this.left, required this.right});
  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: left),
          const SizedBox(width: 8),
          Expanded(child: right),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.title, required this.value, this.trailing});
  final String title;
  final String value;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.bodySmall),
                  const SizedBox(height: 4),
                  Text(value, style: theme.textTheme.titleLarge),
                ],
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}
