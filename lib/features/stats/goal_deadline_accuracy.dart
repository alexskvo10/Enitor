import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/date_utils.dart';
import '../../core/utils/stats_math.dart' as stats_math;
import '../../data/models/goal.dart';
import '../../data/repositories/goal_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/l10n_extensions.dart';

/// Аналитика соблюдения дедлайнов целей: на сколько дней в среднем человек
/// просрочивает (или укладывается раньше) дедлайна. Аналог «Точности оценок»
/// у задач, но вместо отношения факт/оценка — разница дата выполнения минус
/// эффективный дедлайн (deadline, либо конец периода, если он не задан),
/// в днях.
///
/// Считаются ДВЕ метрики параллельно (тот же принцип, что у задач):
///   - «по количеству целей» — обычная медиана, каждая цель весит одинаково;
///   - «по длительности периода» — медиана, взвешенная по длине периода
///     цели (неделя/месяц/сезон/год): просрочка годовой цели двигает
///     результат сильнее, чем просрочка недельной.

const _kMinPairs = 3; // меньше — не показываем вообще
const _kConfidentPairs = 10; // меньше — показываем с пометкой «мало данных»

String _goalPeriodLabel(AppLocalizations l10n, GoalPeriod p) => switch (p) {
      GoalPeriod.week => l10n.goalsPeriodWeek,
      GoalPeriod.month => l10n.goalsPeriodMonth,
      GoalPeriod.season => l10n.goalsPeriodSeason,
      GoalPeriod.year => l10n.goalsPeriodYear,
    };

/// Одна метрика просрочки — медиана разницы (дата выполнения − эффективный
/// дедлайн) в днях, со знаком: положительная — просрочка, отрицательная —
/// выполнено раньше срока.
class GoalDeadlineMetric {
  const GoalDeadlineMetric(this.medianDays);

  final int medianDays;

  int get absDays => medianDays.abs();

  /// Не позже дедлайна (включая ровно в срок).
  bool get isOnTime => medianDays <= 0;

  /// Цвет по величине просрочки: не позже срока — зелёный, небольшая
  /// просрочка (≤2 дня) — янтарный, иначе — красный.
  Color get magnitudeColor {
    if (medianDays <= 0) return AppColors.success;
    if (medianDays <= 2) return AppColors.warning;
    return AppColors.danger;
  }

  /// Короткая метка для карточки: «в срок» / «+3 дн.» / «−2 дн.».
  String shortLabel(AppLocalizations l10n) {
    if (medianDays == 0) return l10n.metDeadlineLabel;
    return medianDays > 0
        ? '+$medianDays ${l10n.daysAbbrev}'
        : '−$absDays ${l10n.daysAbbrev}';
  }

  /// Метка для строк бакетов/тегов — то же самое, что [shortLabel].
  String rowLabel(AppLocalizations l10n) => shortLabel(l10n);

  /// Короткая характеристика для подписи рядом с числом.
  String phrase(AppLocalizations l10n) =>
      isOnTime ? l10n.deadlineOnTimePhrase : l10n.deadlineOverrunPhrase;

}

/// Бакет: либо по типу периода цели ([goalPeriod]), либо по тегу ([label]).
class GoalDeadlineBucket {
  const GoalDeadlineBucket({
    this.label,
    this.goalPeriod,
    required this.pairs,
    required this.byCount,
    required this.byWeight,
  });

  final String? label;
  final GoalPeriod? goalPeriod;
  final int pairs;

  /// Медиана без веса — каждая цель считается одинаково.
  final GoalDeadlineMetric byCount;

  /// Медиана, взвешенная по длительности периода (в днях).
  final GoalDeadlineMetric byWeight;

  String displayLabel(AppLocalizations l10n) =>
      label ?? _goalPeriodLabel(l10n, goalPeriod!);
}

class GoalDeadlineStats {
  const GoalDeadlineStats({
    required this.pairs,
    required this.overall,
    required this.overallByWeight,
    required this.buckets,
    required this.byTag,
  });

  final int pairs;

  /// Общая метрика по количеству целей (равный вес каждой).
  final GoalDeadlineMetric overall;

  /// Общая метрика, взвешенная по длительности периода.
  final GoalDeadlineMetric overallByWeight;

  /// В разрезе типа периода (неделя/месяц/сезон/год).
  final List<GoalDeadlineBucket> buckets;

  /// В разрезе тегов (только теги с ≥ _kMinPairs пар; цель с несколькими
  /// тегами учитывается в каждом). Отсортированы по убыванию величины
  /// отклонения (по количеству целей).
  final List<GoalDeadlineBucket> byTag;

  bool get isConfident => pairs >= _kConfidentPairs;
}

/// Разница (дата выполнения − эффективный дедлайн) в днях, со знаком.
/// Тот же паттерн, что [Goal.isOnTime] — deadline/periodEnd уже без времени
/// суток, поэтому только completedAt приводим через [dateOnly].
double _overrunDaysOf(Goal g) {
  final effectiveDeadline = g.deadline ?? g.periodEnd;
  return dateOnly(g.completedAt!)
      .difference(effectiveDeadline)
      .inDays
      .toDouble();
}

/// Длительность периода цели в днях — вес для «по длительности периода».
double _periodWeightOf(Goal g) =>
    (g.periodEnd.difference(g.periodStart).inDays + 1).toDouble();

GoalDeadlineBucket _bucketFrom({
  String? label,
  GoalPeriod? goalPeriod,
  required List<double> diffs,
  required List<double> weights,
}) =>
    GoalDeadlineBucket(
      label: label,
      goalPeriod: goalPeriod,
      pairs: diffs.length,
      byCount: GoalDeadlineMetric(stats_math.median(diffs).round()),
      byWeight: GoalDeadlineMetric(
        stats_math.weightedMedian(diffs, weights).round(),
      ),
    );

GoalDeadlineStats? _computeGoalDeadline(List<Goal> goals) {
  // Только завершённые цели — иначе нет даты выполнения для сравнения.
  final completed =
      goals.where((g) => g.completed && g.completedAt != null).toList();
  if (completed.length < _kMinPairs) return null;

  final diffs = [for (final g in completed) _overrunDaysOf(g)];
  final weights = [for (final g in completed) _periodWeightOf(g)];

  final byPeriodDiffs = <GoalPeriod, List<double>>{};
  final byPeriodWeights = <GoalPeriod, List<double>>{};
  for (final g in completed) {
    byPeriodDiffs.putIfAbsent(g.period, () => []).add(_overrunDaysOf(g));
    byPeriodWeights.putIfAbsent(g.period, () => []).add(_periodWeightOf(g));
  }

  final byTagDiffs = <String, List<double>>{};
  final byTagWeights = <String, List<double>>{};
  for (final g in completed) {
    final d = _overrunDaysOf(g);
    final w = _periodWeightOf(g);
    for (final tag in g.tags) {
      byTagDiffs.putIfAbsent(tag, () => []).add(d);
      byTagWeights.putIfAbsent(tag, () => []).add(w);
    }
  }
  final tagBuckets = <GoalDeadlineBucket>[
    for (final e in byTagDiffs.entries)
      if (e.value.length >= _kMinPairs)
        _bucketFrom(
          label: '#${e.key}',
          diffs: e.value,
          weights: byTagWeights[e.key]!,
        ),
  ]..sort((a, b) =>
      b.byCount.medianDays.abs().compareTo(a.byCount.medianDays.abs()));

  return GoalDeadlineStats(
    pairs: completed.length,
    overall: GoalDeadlineMetric(stats_math.median(diffs).round()),
    overallByWeight: GoalDeadlineMetric(
      stats_math.weightedMedian(diffs, weights).round(),
    ),
    buckets: [
      for (final p in GoalPeriod.values)
        if (byPeriodDiffs.containsKey(p))
          _bucketFrom(
            goalPeriod: p,
            diffs: byPeriodDiffs[p]!,
            weights: byPeriodWeights[p]!,
          ),
    ],
    byTag: tagBuckets,
  );
}

/// null — данных меньше [_kMinPairs] пар (карточка скрыта).
final goalDeadlineStatsProvider = Provider<GoalDeadlineStats?>((ref) {
  final goals = ref.watch(allGoalsProvider).value;
  if (goals == null) return null;
  return _computeGoalDeadline(goals);
});

// ─── Компактная карточка для раздела «Цели» в Статистике ─────────────────────

class GoalDeadlineCard extends ConsumerWidget {
  const GoalDeadlineCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(goalDeadlineStatsProvider);
    if (stats == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final l10n = context.l10n;

    final onSurface = theme.colorScheme.onSurface;
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const GoalDeadlineScreen()),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.goalDeadlineCardTitle,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: onSurface.withValues(alpha: 0.9),
                      ),
                    ),
                  ),
                  Icon(Icons.chevron_right,
                      color: onSurface.withValues(alpha: 0.4)),
                ],
              ),
              const SizedBox(height: 12),
              _CardMetricRow(
                  label: l10n.byGoalCountLabel, metric: stats.overall),
              Divider(
                height: 21,
                thickness: 1,
                color: onSurface.withValues(alpha: 0.08),
              ),
              _CardMetricRow(
                  label: l10n.byPeriodWeightLabel,
                  metric: stats.overallByWeight),
            ],
          ),
        ),
      ),
    );
  }
}

class _CardMetricRow extends StatelessWidget {
  const _CardMetricRow({required this.label, required this.metric});

  final String label;
  final GoalDeadlineMetric metric;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final onSurface = theme.colorScheme.onSurface;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: onSurface.withValues(alpha: 0.5),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              metric.shortLabel(l10n),
              style: theme.textTheme.headlineSmall?.copyWith(
                color: metric.magnitudeColor,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                metric.phrase(l10n),
                textAlign: TextAlign.right,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: onSurface.withValues(alpha: 0.6),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ─── Детальный экран ─────────────────────────────────────────────────────────

class GoalDeadlineScreen extends ConsumerWidget {
  const GoalDeadlineScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(goalDeadlineStatsProvider);
    final theme = Theme.of(context);
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.goalDeadlineTitle)),
      body: stats == null
          ? Center(child: Text(l10n.notEnoughData))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _VerdictBlock(
                          label: l10n.byGoalCountLabel,
                          metric: stats.overall,
                        ),
                        const SizedBox(height: 16),
                        _VerdictBlock(
                          label: l10n.byPeriodWeightLabel,
                          metric: stats.overallByWeight,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          l10n.deadlineMedianOfPairs(stats.pairs),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.5),
                          ),
                        ),
                        if (!stats.isConfident) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Icon(Icons.info_outline,
                                  size: 15, color: AppColors.warning),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  l10n.lowDataNote,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: AppColors.warning,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 6),
                  child: Text(
                    l10n.deadlineBySizeLabel,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                for (final b in stats.buckets) _BucketRow(bucket: b),
                if (stats.byTag.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _TagDeadlineSection(byTag: stats.byTag),
                ],
                const SizedBox(height: 12),
                Text(
                  l10n.deadlineFooterNote,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
    );
  }
}

class _VerdictBlock extends StatelessWidget {
  const _VerdictBlock({required this.label, required this.metric});

  final String label;
  final GoalDeadlineMetric metric;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text.rich(
          metric.medianDays == 0
              ? TextSpan(text: l10n.deadlineVerdictOnTime)
              : TextSpan(
                  children: [
                    TextSpan(
                      text: metric.medianDays > 0
                          ? l10n.deadlineLateLead
                          : l10n.deadlineEarlyLead,
                    ),
                    TextSpan(
                      text: '~${metric.absDays} ${l10n.daysAbbrev}',
                      style: TextStyle(
                        color: metric.magnitudeColor,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
          style:
              theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

class _TagDeadlineSection extends StatefulWidget {
  const _TagDeadlineSection({required this.byTag});
  final List<GoalDeadlineBucket> byTag;

  @override
  State<_TagDeadlineSection> createState() => _TagDeadlineSectionState();
}

class _TagDeadlineSectionState extends State<_TagDeadlineSection> {
  bool _searching = false;
  String _query = '';
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.6);
    final q = _query.trim().toLowerCase();
    final filtered = q.isEmpty
        ? widget.byTag
        : widget.byTag
            .where((b) => (b.label ?? '').toLowerCase().contains(q))
            .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, right: 2, bottom: 6),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  l10n.byTagLabel,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: muted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              InkWell(
                onTap: () => setState(() {
                  _searching = !_searching;
                  if (!_searching) {
                    _query = '';
                    _ctrl.clear();
                  }
                }),
                borderRadius: BorderRadius.circular(20),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    _searching ? Icons.close : Icons.search,
                    size: 18,
                    color: muted,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (_searching)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: TextField(
              controller: _ctrl,
              autofocus: true,
              decoration: InputDecoration(
                isDense: true,
                hintText: l10n.searchTagTooltip,
                prefixIcon: const Icon(Icons.search, size: 18),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
        if (filtered.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            child: Text(
              l10n.noTagsFound,
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
          )
        else
          for (final b in filtered) _BucketRow(bucket: b),
      ],
    );
  }
}

class _BucketRow extends StatelessWidget {
  const _BucketRow({required this.bucket});
  final GoalDeadlineBucket bucket;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(bucket.displayLabel(l10n),
                      style: theme.textTheme.bodyLarge),
                ),
                Text(
                  l10n.goalPairsCount(bucket.pairs),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _MiniMetric(
                      label: l10n.byGoalCountLabel, metric: bucket.byCount),
                ),
                Expanded(
                  child: _MiniMetric(
                      label: l10n.byPeriodWeightLabel,
                      metric: bucket.byWeight),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniMetric extends StatelessWidget {
  const _MiniMetric({required this.label, required this.metric});

  final String label;
  final GoalDeadlineMetric metric;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.5);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: theme.textTheme.labelSmall?.copyWith(color: muted)),
        const SizedBox(height: 2),
        Text(
          metric.rowLabel(l10n),
          style: theme.textTheme.titleSmall?.copyWith(
            color: metric.magnitudeColor,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
