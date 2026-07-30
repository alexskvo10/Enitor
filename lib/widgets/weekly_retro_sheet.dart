import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/utils/date_utils.dart';
import '../data/models/day_stats.dart';
import '../data/models/goal.dart';
import '../data/models/task.dart';
import '../features/retro/week_stats.dart';
import '../features/stats/estimate_accuracy.dart';
import '../l10n/app_localizations.dart';
import '../l10n/l10n_extensions.dart';
import 'delta_indicator.dart';
import 'fancy_dialog.dart';

/// Всё, что показывает окно разбора недели. Считается заранее (в роутере,
/// до показа) — окну остаётся только нарисовать: так вызывающая сторона
/// может решить «данных нет, показывать нечего» ещё до появления диалога.
class WeeklyRetroData {
  const WeeklyRetroData({
    required this.weekStart,
    required this.stats,
    required this.prev,
    required this.accuracy,
    required this.prevAccuracy,
  });

  /// Понедельник разбираемой (уже завершённой) недели.
  final DateTime weekStart;

  /// Сводка разбираемой недели и недели перед ней — для сравнения.
  final WeekStats stats;
  final WeekStats prev;

  /// Точность оценок за те же две недели. null — за неделю не набралось
  /// минимума пар «оценка + факт», сравнивать нечего.
  final EstimateAccuracy? accuracy;
  final EstimateAccuracy? prevAccuracy;

  /// Собирает разбор недели [weekStart] из сырых данных приложения.
  factory WeeklyRetroData.build({
    required DateTime weekStart,
    required List<DayStats> allStats,
    required List<Goal> goals,
    required Map<String, int> ratings,
    required List<Task> tasks,
  }) {
    final prevStart = weekStart.subtract(const Duration(days: 7));
    List<Task> tasksOfWeek(DateTime start) {
      final end = start.add(const Duration(days: 6));
      return tasks.where((t) {
        return !dateOnly(t.date).isBefore(start) &&
            !dateOnly(t.date).isAfter(end);
      }).toList();
    }

    return WeeklyRetroData(
      weekStart: weekStart,
      stats: computeWeekStats(weekStart, allStats, goals, ratings),
      prev: computeWeekStats(prevStart, allStats, goals, ratings),
      accuracy: computeEstimateAccuracy(tasksOfWeek(weekStart)),
      prevAccuracy: computeEstimateAccuracy(tasksOfWeek(prevStart)),
    );
  }

  /// Показывать нечего: неделя прошла мимо приложения.
  bool get isEmpty => stats.isEmpty;
}

/// Окно разбора прошедшей недели. Встречает при первом открытии приложения
/// после настроенного момента (по умолчанию понедельник, 19:00) — см.
/// [WeeklyRetroController]. По визуальному языку — тот же fancy-диалог, что
/// и догоняющий список переноса.
///
/// Ничего не спрашивает и никуда не ведёт: это сводка, а не действие.
Future<void> showWeeklyRetroSheet(
  BuildContext context, {
  required WeeklyRetroData data,
}) {
  return showFancyRawDialog<void>(
    context: context,
    barrierLabel: 'weekly-retro',
    builder: (ctx) => _WeeklyRetroDialog(data: data),
  );
}

class _WeeklyRetroDialog extends StatelessWidget {
  const _WeeklyRetroDialog({required this.data});

  final WeeklyRetroData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final ru = Localizations.localeOf(context).languageCode == 'ru';
    final s = data.stats;

    final weekLabel = GoalPeriodRef(
      period: GoalPeriod.week,
      year: data.weekStart.year,
      weekStart: data.weekStart,
    ).labelFor(ru);

    return FancyDialogCard(
      icon: Icons.event_available_outlined,
      iconColor: AppColors.primary,
      title: l10n.weekSummaryScreenTitle,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 6),
          Text(
            weekLabel,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          // Flexible: список забирает ровно ту высоту, что осталась в
          // карточке после медальона, заголовка и кнопки, и прокручивается,
          // если карточек больше, чем влезает. Плюс мягкий потолок — на
          // большом экране растягивать окно на всю высоту незачем.
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Продуктивность с дельтой — только если неделю вообще
                    // «прожили» в приложении. Пустой герой с прочерком
                    // ничего не сообщает, а место занимает.
                    if (s.avgProductivity != null) ...[
                      _heroCard(theme, l10n, s, data.prev),
                      const SizedBox(height: 8),
                    ],
                    if (s.daysWithData > 0) ...[
                      _miniRow(theme, l10n, s),
                      const SizedBox(height: 8),
                    ],
                    if (s.bestDay != null) ...[
                      _bestDayCard(theme, l10n, s.bestDay!),
                      const SizedBox(height: 8),
                    ],
                    _weekGoalsCard(theme, l10n, s),
                    if (s.goalsDone.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      _tile(
                        theme,
                        emoji: '🎯',
                        title: l10n.goalsAchievedCount(s.goalsDone.length),
                        subtitle: _preview(s.goalsDone.map((g) => g.title)),
                        subtitleTooltip:
                            _full(s.goalsDone.map((g) => g.title)),
                      ),
                    ],
                    if (s.avgDayRating != null) ...[
                      const SizedBox(height: 8),
                      _tile(
                        theme,
                        emoji: '⭐',
                        title: l10n
                            .avgDayRating(s.avgDayRating!.toStringAsFixed(1)),
                        subtitle: l10n.byEveningRatingsNote,
                      ),
                    ],
                    if (data.accuracy != null) ...[
                      const SizedBox(height: 8),
                      _accuracyCard(theme, l10n),
                    ],
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l10n.close),
            ),
          ),
        ],
      ),
    );
  }

  // ── Карточки ───────────────────────────────────────────────────────────

  /// Продуктивность недели + дельта к предыдущей (в процентных пунктах).
  Widget _heroCard(
    ThemeData theme,
    AppLocalizations l10n,
    WeekStats s,
    WeekStats prev,
  ) {
    final avg = s.avgProductivity!;
    final delta = prev.avgProductivity == null
        ? null
        : (avg - prev.avgProductivity!) * 100;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.weekProductivityLabel,
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${(avg * 100).round()}%',
                    style: theme.textTheme.headlineSmall?.copyWith(
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
                  l10n.retroVsPrevWeekLabel,
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
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
              child: Column(
                children: [
                  Text(
                    value,
                    style: theme.textTheme.titleSmall
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

    // Без crossAxisAlignment.stretch: Row живёт внутри прокручиваемой
    // колонки, где высота не ограничена, — растягивание там падает.
    return Row(
      children: [
        cell('${s.completedTasks}/${s.totalTasks}', l10n.tasksDoneCaption),
        const SizedBox(width: 6),
        cell(
          s.avgOnTime == null ? '—' : '${(s.avgOnTime! * 100).round()}%',
          l10n.onTimeCaptionRetro,
        ),
        const SizedBox(width: 6),
        cell('${s.perfectDays}', l10n.perfectDaysCaption),
      ],
    );
  }

  Widget _bestDayCard(ThemeData theme, AppLocalizations l10n, DayStats best) {
    final weekday = weekdayNames(l10n)[dateOnly(best.date).weekday - 1];
    return _tile(
      theme,
      emoji: '🏆',
      title: l10n.bestDayTitle(weekday),
      subtitle: '${l10n.completedOfTasks(best.completedTasks, best.totalTasks)}'
          ' · ${((best.productivity ?? 0) * 100).round()}%',
    );
  }

  /// Цели, поставленные ИМЕННО на эту неделю. Когда их не ставили — говорим
  /// об этом прямо: «не было» это тоже итог недели.
  Widget _weekGoalsCard(ThemeData theme, AppLocalizations l10n, WeekStats s) {
    if (s.weekGoals.isEmpty) {
      return _tile(
        theme,
        emoji: '📌',
        title: l10n.weekGoalsNoneTitle,
        subtitle: l10n.weekGoalsNoneSubtitle,
      );
    }
    final missed = s.weekGoals.where((g) => !g.completed).toList();
    // Пока grace-окно недели открыто, недостигнутые цели — ещё не приговор.
    final graceEnd =
        missed.isEmpty ? null : weekGoalsGraceEnd(data.weekStart);
    return _tile(
      theme,
      emoji: '📌',
      title: l10n.weekGoalsTitle(s.weekGoalsDone, s.weekGoals.length),
      subtitle: missed.isEmpty
          ? l10n.weekGoalsAllDone
          : l10n.weekGoalsMissed(_preview(missed.map((g) => g.title))),
      subtitleTooltip:
          missed.isEmpty ? null : _full(missed.map((g) => g.title)),
      note: graceEnd == null
          ? null
          : l10n.weekGoalsGraceNote(
              weekdayNames(l10n)[graceEnd.weekday - 1],
            ),
    );
  }

  /// Первые три названия через точку; если их больше — многоточие в конце.
  static String _preview(Iterable<String> titles) {
    final all = titles.toList();
    final head = all.take(3).join(' · ');
    return all.length > 3 ? '$head …' : head;
  }

  /// Полный список для тултипа: превью обрезано и по числу названий, и по
  /// ширине карточки, поэтому длинные названия иначе не прочитать вовсе.
  static String _full(Iterable<String> titles) => titles.join('\n');

  /// Точность оценок за неделю и её сдвиг относительно предыдущей.
  ///
  /// Сравниваем ВЕЛИЧИНУ промаха (|смещение|), а не смещение со знаком:
  /// уйти с −30% на +10% — это стать точнее, хотя знак поменялся.
  Widget _accuracyCard(ThemeData theme, AppLocalizations l10n) {
    final acc = data.accuracy!;
    final metric = acc.overall;
    final prev = data.prevAccuracy?.overall;

    final String comparison;
    if (prev == null) {
      comparison = l10n.retroAccuracyNoPrev;
    } else if (metric.absBias < prev.absBias - 1) {
      comparison = l10n.retroAccuracyBetter(prev.absBias, metric.absBias);
    } else if (metric.absBias > prev.absBias + 1) {
      comparison = l10n.retroAccuracyWorse(prev.absBias, metric.absBias);
    } else {
      comparison = l10n.retroAccuracySame;
    }

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('⏱', style: TextStyle(fontSize: 22)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          l10n.retroAccuracyTitle,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        metric.shortLabel,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: metric.magnitudeColor,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    comparison,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  Text(
                    l10n.retroAccuracyPairs(acc.pairs),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Компактная строка-карточка «эмодзи + заголовок + подпись». Своя, а не
  /// ListTile: у того фиксированные вертикальные отступы, и четыре подряд
  /// уже не помещаются в диалог.
  Widget _tile(
    ThemeData theme, {
    required String emoji,
    required String title,
    required String subtitle,
    String? subtitleTooltip,
    String? note,
  }) {
    Widget subtitleText = Text(
      subtitle,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.bodySmall?.copyWith(
        color: AppColors.textSecondary,
      ),
    );
    // Подпись обрезается двумя строками, а список названий — ещё и тремя
    // элементами, поэтому там, где за ней стоит список, полный текст даём по
    // наведению/долгому нажатию — как в догоняющем диалоге переноса. Без
    // текста Tooltip не навешиваем: пустой пузырёк на наведении хуже, чем
    // его отсутствие.
    if (subtitleTooltip != null && subtitleTooltip.isNotEmpty) {
      subtitleText = Tooltip(message: subtitleTooltip, child: subtitleText);
    }
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 22)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 2),
                  subtitleText,
                  if (note != null)
                    Text(
                      note,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: AppColors.warning,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
