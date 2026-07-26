import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/date_utils.dart';
import '../../data/models/goal.dart';
import '../../data/repositories/goal_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/l10n_extensions.dart';
import '../../widgets/seg_chip.dart';

/// Таймфрейм статистики по тегам целей — тот же принцип, что у задач
/// (см. _TagTf в tag_stats_screen.dart): окно по дате начала периода цели.
enum _GoalTagTf {
  week(7),
  month(30),
  months3(90),
  allTime(null);

  const _GoalTagTf(this.days);
  final int? days;

  String label(AppLocalizations l10n) => switch (this) {
        _GoalTagTf.week => l10n.goalsPeriodWeek,
        _GoalTagTf.month => l10n.goalsPeriodMonth,
        _GoalTagTf.months3 => l10n.tfMonths3,
        _GoalTagTf.allTime => l10n.tfAllTime,
      };
}

/// Накопленные показатели одного тега.
class _GoalTagAgg {
  int total = 0;
  double fractionSum = 0; // сумма дробного выполнения
  int completed = 0;
  int onTime = 0;
}

/// Статистика в разрезе тегов целей: сколько целей, % выполнения, % в срок.
/// Цель с несколькими тегами учитывается в каждом из них.
class GoalTagStatsScreen extends ConsumerStatefulWidget {
  const GoalTagStatsScreen({super.key});

  @override
  ConsumerState<GoalTagStatsScreen> createState() =>
      _GoalTagStatsScreenState();
}

class _GoalTagStatsScreenState extends ConsumerState<GoalTagStatsScreen> {
  _GoalTagTf _tf = _GoalTagTf.month;
  bool _searching = false;
  String _query = '';
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final goals = ref.watch(allGoalsProvider).value;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.goalTagStatsTitle),
        actions: [
          IconButton(
            tooltip:
                _searching ? l10n.closeSearchTooltip : l10n.searchTagTooltip,
            icon: Icon(_searching ? Icons.close : Icons.search),
            onPressed: () => setState(() {
              _searching = !_searching;
              if (!_searching) {
                _query = '';
                _searchCtrl.clear();
              }
            }),
          ),
        ],
      ),
      body: goals == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final tf in _GoalTagTf.values)
                          SegChip(
                            label: tf.label(l10n),
                            selected: _tf == tf,
                            onTap: () => setState(() => _tf = tf),
                          ),
                      ],
                    ),
                  ),
                ),
                if (_searching) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _searchCtrl,
                    autofocus: true,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: l10n.searchTagTooltip,
                      prefixIcon: const Icon(Icons.search, size: 18),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onChanged: (v) => setState(() => _query = v),
                  ),
                ],
                const SizedBox(height: 12),
                ..._buildRows(theme, l10n, goals),
              ],
            ),
    );
  }

  List<Widget> _buildRows(
      ThemeData theme, AppLocalizations l10n, List<Goal> goals) {
    final todayDate = today();
    final from =
        _tf.days == null ? null : todayDate.subtract(Duration(days: _tf.days!));

    final byTag = <String, _GoalTagAgg>{};
    for (final g in goals) {
      if (g.tags.isEmpty) continue;
      final d = dateOnly(g.ref.start);
      if (d.isAfter(todayDate)) continue; // будущее не считаем
      if (from != null && d.isBefore(from)) continue;
      for (final tag in g.tags) {
        final agg = byTag.putIfAbsent(tag, () => _GoalTagAgg());
        agg.total++;
        agg.fractionSum += g.completionValue;
        if (g.completed) {
          agg.completed++;
          if (g.isOnTime) agg.onTime++;
        }
      }
    }

    if (byTag.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 40),
          child: Center(
            child: Text(
              l10n.noTagsInPeriodGoals,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ),
        ),
      ];
    }

    final q = _query.trim().toLowerCase();
    final entries = byTag.entries
        .where((e) => q.isEmpty || e.key.toLowerCase().contains(q))
        .toList()
      ..sort((a, b) => b.value.total.compareTo(a.value.total));

    if (entries.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 40),
          child: Center(
            child: Text(
              l10n.noTagsFound,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ),
        ),
      ];
    }

    return [for (final e in entries) _GoalTagRow(tag: e.key, agg: e.value)];
  }
}

class _GoalTagRow extends StatelessWidget {
  const _GoalTagRow({required this.tag, required this.agg});
  final String tag;
  final _GoalTagAgg agg;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rate = agg.total == 0 ? 0.0 : agg.fractionSum / agg.total;
    final onTimeRate =
        agg.completed == 0 ? null : agg.onTime / agg.completed;
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.6);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '#$tag',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
                Text(
                  '${(rate * 100).round()}%',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(value: rate, minHeight: 6),
            ),
            const SizedBox(height: 6),
            Text(
              [
                context.l10n.completedOfGoals(agg.completed, agg.total),
                if (onTimeRate != null)
                  context.l10n.onTimePercent((onTimeRate * 100).round()),
              ].join(' · '),
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
          ],
        ),
      ),
    );
  }
}
