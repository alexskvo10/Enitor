import '../../core/utils/date_utils.dart';
import '../../data/models/day_stats.dart';
import '../../data/models/goal.dart';
import '../../data/repositories/rating_repository.dart';
import '../../data/repositories/stats_repository.dart';

/// Сводка одной недели: продуктивность, задачи, лучший день, цели, средняя
/// оценка дней. Всё считается из УЖЕ собранных данных — никаких новых вводов.
///
/// Вынесено из экрана итогов, потому что ровно ту же сводку показывает окно
/// разбора недели (см. `widgets/weekly_retro_sheet.dart`). Пока расчёт жил в
/// приватном классе экрана, две поверхности неизбежно разъехались бы.
class WeekStats {
  double? avgProductivity;
  double? avgOnTime;
  int totalTasks = 0;
  int completedTasks = 0;
  int perfectDays = 0;
  int daysWithData = 0;
  DayStats? bestDay;
  double? avgDayRating;

  /// Цели ЛЮБОГО периода, достигнутые на этой неделе (месячная цель, закрытая
  /// в среду, — тоже достижение этой недели).
  List<Goal> goalsDone = [];

  /// Цели, поставленные ИМЕННО на эту неделю (period == week и та же неделя),
  /// независимо от того, достигнуты они или нет. Отдельно от [goalsDone]:
  /// «что я обещал себе на эту неделю» и «что вообще закрылось за неделю» —
  /// разные вопросы, и первый без второго не виден.
  List<Goal> weekGoals = [];

  int get weekGoalsDone => weekGoals.where((g) => g.completed).length;

  /// Совсем пустая неделя: ни одного дня с данными, ни закрытых целей, ни
  /// поставленных недельных целей. Показывать по ней нечего.
  bool get isEmpty =>
      daysWithData == 0 && goalsDone.isEmpty && weekGoals.isEmpty;
}

/// До какого дня включительно цели недели [weekStart] ещё можно закрыть, или
/// null, если grace-окно периода уже истекло.
///
/// Разбор недели по умолчанию приходит в понедельник вечером, а grace-окно
/// недельного периода длится ещё двое суток — то есть в момент разбора часть
/// «недостигнутых» целей человек вполне может закрыть. Без этой оговорки
/// окно сообщало бы приговор там, где ещё есть время.
DateTime? weekGoalsGraceEnd(DateTime weekStart) {
  final ref = GoalPeriodRef(
    period: GoalPeriod.week,
    year: weekStart.year,
    weekStart: weekStart,
  );
  final end = ref.endInclusive.add(Duration(days: ref.graceDays));
  return today().isAfter(end) ? null : end;
}

/// Считает сводку недели, начинающейся в [weekStart] (понедельник).
///
/// Дни ПОСЛЕ сегодняшнего игнорируются — иначе текущая неделя выглядела бы
/// провальной из-за ещё не наступивших дней.
WeekStats computeWeekStats(
  DateTime weekStart,
  List<DayStats> allStats,
  List<Goal> goals,
  Map<String, int> ratings,
) {
  final res = WeekStats();
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

  // Цели, поставленные на саму эту неделю. Перенесённые в следующий период
  // оригиналы НЕ отфильтровываем: цель на эту неделю была поставлена и не
  // достигнута — то, что её отложили, этого не отменяет. Так же их
  // показывает и экран «Цели» (оригинал остаётся в своём периоде с бейджем),
  // а копия живёт уже в другой неделе, так что двойного счёта нет.
  res.weekGoals = goals.where((g) {
    return g.period == GoalPeriod.week &&
        g.weekStart != null &&
        dateOnly(g.weekStart!) == weekStart;
  }).toList();

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
