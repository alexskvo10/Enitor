import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/date_utils.dart';
import '../models/day_stats.dart';
import '../models/goal.dart';
import '../models/task.dart';
import '../sources/local/local_storage.dart';

enum ChartGrouping { daily, weekly, monthly, yearly }

/// Гранулярность для «лучшего периода» в профиле.
enum StatGranularity { day, week, month, season, year }

/// Лучший период заданной гранулярности (по составному скору).
class BestPeriod {
  const BestPeriod({
    required this.start,
    required this.productivity,
    required this.onTimeRate,
  });

  /// Начало бакета (день / понедельник / 1-е число месяца / начало сезона / 1 янв).
  final DateTime start;
  final double productivity; // 0..1
  final double? onTimeRate; // 0..1, null — не было выполненных
}

/// Серии (streaks): сколько дней подряд пользователь закрывал день на 100%.
class StreakInfo {
  const StreakInfo({required this.current, required this.best});

  /// Текущая серия (заканчивается на сегодня/последнем успешном дне).
  final int current;

  /// Самая длинная серия за всё время.
  final int best;

  static const empty = StreakInfo(current: 0, best: 0);
}

class ProductivityPoint {
  const ProductivityPoint({
    required this.bucketStart,
    required this.value,
    this.onTimeValue,
    this.totalTasks = 0,
  });

  final DateTime bucketStart;

  /// Средняя продуктивность (0..1) за бакет. null — нет данных.
  final double? value;

  /// Средняя доля своевременных среди выполненных (0..1) за бакет.
  /// null — нет выполненных задач с отслеживаемой своевременностью.
  final double? onTimeValue;

  /// Всего задач в бакете — для веса за объём при выборе «лучшего».
  final int totalTasks;
}

/// Константа насыщения для веса за объём: score × N/(N+k).
/// Малый объём (мало задач/целей) придушивает скор, большой — почти не влияет.
const double kVolumeK = 4.0;

/// Вес за объём: плавно растёт от ~0 к 1 по мере роста [n].
double volumeWeight(int n) => n / (n + kVolumeK);

/// Сводка за период.
class StatsSummary {
  const StatsSummary({
    required this.avgProductivity,
    required this.totalTasks,
    required this.completedTasks,
    required this.daysWithData,
  });

  final double? avgProductivity;
  final int totalTasks;
  final int completedTasks;
  final int daysWithData;

  static const empty = StatsSummary(
    avgProductivity: null,
    totalTasks: 0,
    completedTasks: 0,
    daysWithData: 0,
  );
}

// ─── Вспомогательный класс для агрегации бакетов ─────────────────────────────

class _Bucket {
  double productivitySum = 0;
  int count = 0;
  int onTimeCount = 0;
  int lateCount = 0;
  int taskCount = 0; // всего задач в бакете (для веса за объём)
}

const _kStatsKey = 'day_stats';

class StatsRepository {
  StatsRepository(this._storage) {
    _reload();
  }

  final LocalStorage _storage;
  final _controller = StreamController<List<DayStats>>.broadcast();
  List<DayStats> _cache = [];

  void _reload() {
    _cache = _storage.readList(_kStatsKey).map(DayStats.fromJson).toList();
    _controller.add(_cache);
  }

  Future<void> _save() async {
    await _storage.writeList(
        _kStatsKey, _cache.map((s) => s.toJson()).toList());
    _controller.add(List.unmodifiable(_cache));
  }

  // ─── On-time хелпер ────────────────────────────────────────────────────────

  /// Задача выполнена вовремя если:
  /// • выполнена раньше своего дня → вовремя;
  /// • выполнена позже своего дня → с опозданием;
  /// • в свой день — уложилась в срок: во время окончания задачи, а если оно
  ///   не задано, то до полуночи.
  ///
  /// «День» здесь — день приложения ([effectiveDay]): ночные часы относятся к
  /// уходящему дню. Без этого любая задача, законченная между 00:00 и 4:00,
  /// считалась опоздавшей — даже с проставленным временем окончания, потому
  /// что проверка календарной даты срабатывала раньше проверки времени. То
  /// есть правило «день начинается в 4:00» действовало везде, кроме метрики,
  /// которая за опоздания и наказывает.
  ///
  /// Обычная задача без времени окончания всё же считается опоздавшей, если
  /// закрыта после полуночи: её неявный срок — конец календарного дня.
  ///
  /// Публичная — единственный источник истины для всех экранов/агрегатов.
  static bool taskIsOnTime(Task task) {
    if (!task.isCompleted || task.completedAt == null) return false;
    final done = task.completedAt!;
    final completedDay = effectiveDay(done);
    final taskDay = dateOnly(task.date);
    if (completedDay.isAfter(taskDay)) return false;
    if (completedDay.isBefore(taskDay)) return true;

    // Один день: сравниваем по общей шкале минут, где ночь после полуночи
    // продолжает уходящий день (01:30 → 1530).
    final completedMins = minutesFromDayStart(done);
    final end = task.endMinutes;
    if (end == null) return completedMins <= 1440; // неявный срок — полночь
    // Задача «через полночь» (22:00 → 01:00): конец лежит уже за 1440 —
    // тот же признак, что и в _taskEndAt/_calcTimeState на экране «Сегодня».
    final start = task.startMinutes;
    final overnight = start != null && end < start;
    return completedMins <= (overnight ? end + 1440 : end);
  }

  // ─── CRUD ──────────────────────────────────────────────────────────────────

  /// Пересчитать статистику за день на основе актуального списка задач.
  Future<void> recompute(DateTime date, List<Task> tasks) async {
    final day = dateOnly(date);
    final total = tasks.length;
    final completed = tasks.where((t) => t.isCompleted).toList();
    final onTime = completed.where(taskIsOnTime).length;
    final late = completed.length - onTime;
    // Дробное выполнение: счётчик 3/5 = 0.6, чек-лист 2/3 = 0.67, обычная — 0/1.
    final fraction = tasks.fold<double>(
      0,
      (sum, t) => sum + t.completionFraction,
    );

    _cache.removeWhere((s) => dateOnly(s.date) == day);
    _cache.add(DayStats(
      date: day,
      totalTasks: total,
      completedTasks: completed.length,
      completedFraction: fraction,
      onTimeCount: onTime,
      lateCount: late,
      updatedAt: DateTime.now(),
    ));
    await _save();
  }

  Stream<DayStats?> watchDay(DateTime date) async* {
    final day = dateOnly(date);
    DayStats? find(List<DayStats> all) => all.cast<DayStats?>().firstWhere(
          (s) => s != null && dateOnly(s.date) == day,
          orElse: () => null,
        );

    yield find(_cache);
    await for (final all in _controller.stream) {
      yield find(all);
    }
  }

  /// Полный список дневной статистики (для достижений: идеальные дни и т.п.).
  Stream<List<DayStats>> watchAllStats() async* {
    yield List.unmodifiable(_cache);
    await for (final all in _controller.stream) {
      yield all;
    }
  }

  Future<double?> averageAllTime() async => _averageOf(_cache);

  Stream<double?> watchAverageAllTime() async* {
    yield _averageOf(_cache);
    await for (final all in _controller.stream) {
      yield _averageOf(all);
    }
  }

  static double? _averageOf(List<DayStats> all) {
    final todayDate = today();
    final days = all
        .where((s) => s.productivity != null && !s.date.isAfter(todayDate))
        .toList();
    if (days.isEmpty) return null;
    return days.fold<double>(0, (a, s) => a + s.productivity!) / days.length;
  }

  Future<double?> onTimeAverageAllTime() async => _onTimeAverageOf(_cache);

  /// Средняя своевременность за всё время (только дни, где были выполненные).
  Stream<double?> watchAllTimeOnTimeAverage() async* {
    yield _onTimeAverageOf(_cache);
    await for (final all in _controller.stream) {
      yield _onTimeAverageOf(all);
    }
  }

  static double? _onTimeAverageOf(List<DayStats> all) {
    final todayDate = today();
    final days = all
        .where((s) => s.timeliness != null && !s.date.isAfter(todayDate))
        .toList();
    if (days.isEmpty) return null;
    return days.fold<double>(0, (a, s) => a + s.timeliness!) / days.length;
  }

  // ─── Сводка ────────────────────────────────────────────────────────────────

  Future<StatsSummary> summaryForRange({
    required DateTime from,
    required DateTime to,
  }) async =>
      _summaryOf(_cache, from, to);

  Stream<StatsSummary> watchSummary({
    required DateTime from,
    required DateTime to,
  }) async* {
    yield _summaryOf(_cache, from, to);
    await for (final all in _controller.stream) {
      yield _summaryOf(all, from, to);
    }
  }

  static StatsSummary _summaryOf(
    List<DayStats> all,
    DateTime from,
    DateTime to,
  ) {
    final fromDay = dateOnly(from);
    final toDay = dateOnly(to);
    final todayDate = today();
    final inRange = all.where((s) =>
        !s.date.isBefore(fromDay) &&
        !s.date.isAfter(toDay) &&
        !s.date.isAfter(todayDate));

    var total = 0;
    var done = 0;
    final productive = <DayStats>[];
    for (final s in inRange) {
      total += s.totalTasks;
      done += s.completedTasks;
      if (s.productivity != null) productive.add(s);
    }

    if (productive.isEmpty) {
      return StatsSummary(
        avgProductivity: null,
        totalTasks: total,
        completedTasks: done,
        daysWithData: 0,
      );
    }

    final avg = productive.fold<double>(0, (a, s) => a + s.productivity!) /
        productive.length;

    return StatsSummary(
      avgProductivity: avg,
      totalTasks: total,
      completedTasks: done,
      daysWithData: productive.length,
    );
  }

  // ─── Точки графика ─────────────────────────────────────────────────────────

  Future<List<ProductivityPoint>> productivityPoints({
    required DateTime from,
    required DateTime to,
    required ChartGrouping grouping,
  }) async =>
      _pointsOf(_cache, from, to, grouping);

  Stream<List<ProductivityPoint>> watchProductivityPoints({
    required DateTime from,
    required DateTime to,
    required ChartGrouping grouping,
  }) async* {
    yield _pointsOf(_cache, from, to, grouping);
    await for (final all in _controller.stream) {
      yield _pointsOf(all, from, to, grouping);
    }
  }

  static List<ProductivityPoint> _pointsOf(
    List<DayStats> all,
    DateTime from,
    DateTime to,
    ChartGrouping grouping,
  ) {
    final fromDay = dateOnly(from);
    final toDay = dateOnly(to);
    final stats =
        all.where((s) => !s.date.isBefore(fromDay) && !s.date.isAfter(toDay));

    final buckets = <DateTime, _Bucket>{};
    for (final s in stats) {
      if (s.productivity == null) continue;
      final key = _bucketKeyStatic(s.date, grouping);
      final b = buckets.putIfAbsent(key, () => _Bucket());
      b.productivitySum += s.productivity!;
      b.count++;
      b.onTimeCount += s.onTimeCount;
      b.lateCount += s.lateCount;
      b.taskCount += s.totalTasks;
    }

    final result = <ProductivityPoint>[];
    var cursor = _bucketKeyStatic(from, grouping);
    final endKey = _bucketKeyStatic(to, grouping);
    while (!cursor.isAfter(endKey)) {
      final b = buckets[cursor];
      final onTimeTotal = (b?.onTimeCount ?? 0) + (b?.lateCount ?? 0);
      result.add(ProductivityPoint(
        bucketStart: cursor,
        value: b == null ? null : b.productivitySum / b.count,
        // Точка продуктивности есть → есть и точка своевр-ти: 0%, если в бакете
        // ничего не выполнено ПОЛНОСТЬЮ (напр. только частичный прогресс чек-
        // листа). Раньше была null и линия своевременности рвалась.
        onTimeValue: b == null
            ? null
            : (onTimeTotal == 0 ? 0.0 : b.onTimeCount / onTimeTotal),
        totalTasks: b?.taskCount ?? 0,
      ));
      cursor = _nextBucketStatic(cursor, grouping);
    }
    return result;
  }

  // ─── Лучшие периоды (для профиля) ───────────────────────────────────────────

  Stream<Map<StatGranularity, BestPeriod>> watchBestPeriods() async* {
    yield _bestPeriodsOf(_cache);
    await for (final all in _controller.stream) {
      yield _bestPeriodsOf(all);
    }
  }

  static Map<StatGranularity, BestPeriod> _bestPeriodsOf(List<DayStats> all) {
    final result = <StatGranularity, BestPeriod>{};
    for (final g in StatGranularity.values) {
      final best = _bestForGranularity(all, g);
      if (best != null) result[g] = best;
    }
    return result;
  }

  static BestPeriod? _bestForGranularity(
      List<DayStats> all, StatGranularity g) {
    final todayDate = today();
    final buckets = <DateTime, _Bucket>{};
    for (final s in all) {
      if (s.productivity == null) continue;
      if (s.date.isAfter(todayDate)) continue;
      final key = _granularityKey(s.date, g);
      final b = buckets.putIfAbsent(key, () => _Bucket());
      b.productivitySum += s.productivity!;
      b.count++;
      b.onTimeCount += s.onTimeCount;
      b.lateCount += s.lateCount;
      b.taskCount += s.totalTasks;
    }
    if (buckets.isEmpty) return null;

    DateTime? bestKey;
    _Bucket? bestB;
    var bestScore = -1.0;
    buckets.forEach((key, b) {
      final p = b.productivitySum / b.count;
      final totalOT = b.onTimeCount + b.lateCount;
      final t = totalOT == 0 ? 1.0 : b.onTimeCount / totalOT;
      // Вес за объём: период с парой задач не обгонит большой период.
      final score = p * (0.7 + 0.3 * t) * volumeWeight(b.taskCount);
      final better = score > bestScore + 1e-9 ||
          ((score - bestScore).abs() < 1e-9 &&
              bestKey != null &&
              key.isAfter(bestKey!));
      if (bestKey == null || better) {
        bestScore = score;
        bestKey = key;
        bestB = b;
      }
    });

    final totalOT = bestB!.onTimeCount + bestB!.lateCount;
    return BestPeriod(
      start: bestKey!,
      productivity: bestB!.productivitySum / bestB!.count,
      onTimeRate: totalOT == 0 ? null : bestB!.onTimeCount / totalOT,
    );
  }

  // ─── Серии (streaks) ────────────────────────────────────────────────────────
  //
  // День «успешный» если все задачи выполнены (productivity == 1.0) и задач ≥ 1.
  // Дни без задач — нейтральны: серию не рвут и не продлевают (пропускаются).
  // Сегодня, если ещё не закрыт на 100%, тоже не рвёт серию (день не окончен).

  /// Порог «успешного» дня для серий (доля выполнения). 1.0 = все задачи.
  static const double _streakThreshold = 1.0;

  Stream<StreakInfo> watchStreaks() async* {
    yield _streaksOf(_cache);
    await for (final all in _controller.stream) {
      yield _streaksOf(all);
    }
  }

  static StreakInfo _streaksOf(List<DayStats> all) {
    if (all.isEmpty) return StreakInfo.empty;

    final byDay = <DateTime, DayStats>{};
    DateTime? minDay;
    for (final s in all) {
      final d = dateOnly(s.date);
      byDay[d] = s;
      if (minDay == null || d.isBefore(minDay)) minDay = d;
    }
    final todayDate = today();
    if (minDay == null || minDay.isAfter(todayDate)) return StreakInfo.empty;

    // Состояние дня: 1 — успех, 0 — провал, null — нейтральный (пропуск).
    bool? statusOf(DateTime day) {
      final s = byDay[day];
      if (s == null || s.totalTasks == 0) return null; // нейтральный
      final p = s.productivity ?? 0.0;
      return p >= _streakThreshold - 1e-9;
    }

    // Лучшая серия: проходим хронологически. Нейтральные дни сохраняют run,
    // провал обнуляет. Сегодняшний провал (день не окончен) трактуем как пропуск.
    var best = 0;
    var run = 0;
    for (var cursor = minDay;
        !cursor.isAfter(todayDate);
        cursor = cursor.add(const Duration(days: 1))) {
      final st = statusOf(cursor);
      if (st == true) {
        run++;
        if (run > best) best = run;
      } else if (st == false) {
        if (cursor != todayDate) run = 0; // сегодня не рвёт (день не окончен)
      }
      // st == null → нейтральный, run без изменений
    }

    // Текущая серия: идём от сегодня назад до провала (не сегодняшнего).
    var current = 0;
    for (var cursor = todayDate;
        !cursor.isBefore(minDay);
        cursor = cursor.subtract(const Duration(days: 1))) {
      final st = statusOf(cursor);
      if (st == true) {
        current++;
      } else if (st == false) {
        if (cursor == todayDate) continue; // сегодня не рвёт
        break;
      }
      // нейтральный → пропускаем
    }

    return StreakInfo(current: current, best: best);
  }

  static DateTime _granularityKey(DateTime date, StatGranularity g) {
    switch (g) {
      case StatGranularity.day:
        return dateOnly(date);
      case StatGranularity.week:
        return startOfWeek(date);
      case StatGranularity.month:
        return startOfMonth(date);
      case StatGranularity.year:
        return startOfYear(date);
      case StatGranularity.season:
        final (y, idx) = seasonOf(date);
        return GoalPeriodRef(
          period: GoalPeriod.season,
          year: y,
          season: idx,
        ).start;
    }
  }

  static DateTime _bucketKeyStatic(DateTime date, ChartGrouping g) =>
      switch (g) {
        ChartGrouping.daily => dateOnly(date),
        ChartGrouping.weekly => startOfWeek(date),
        ChartGrouping.monthly => startOfMonth(date),
        ChartGrouping.yearly => startOfYear(date),
      };

  static DateTime _nextBucketStatic(DateTime c, ChartGrouping g) => switch (g) {
        ChartGrouping.daily => c.add(const Duration(days: 1)),
        ChartGrouping.weekly => c.add(const Duration(days: 7)),
        ChartGrouping.monthly => DateTime(c.year, c.month + 1),
        ChartGrouping.yearly => DateTime(c.year + 1),
      };

  void dispose() => _controller.close();
}

// ─── Провайдеры ───────────────────────────────────────────────────────────────

final statsRepositoryProvider = Provider<StatsRepository>((ref) {
  final repo = StatsRepository(ref.watch(localStorageProvider));
  ref.onDispose(repo.dispose);
  return repo;
});

final todayStatsProvider = StreamProvider<DayStats?>((ref) {
  return ref.watch(statsRepositoryProvider).watchDay(today());
});

final statsForDayProvider =
    StreamProvider.family<DayStats?, DateTime>((ref, date) {
  return ref.watch(statsRepositoryProvider).watchDay(date);
});

final allTimeAverageProvider = StreamProvider<double?>((ref) {
  return ref.watch(statsRepositoryProvider).watchAverageAllTime();
});

final allTimeOnTimeAverageProvider = StreamProvider<double?>((ref) {
  return ref.watch(statsRepositoryProvider).watchAllTimeOnTimeAverage();
});

final bestPeriodsProvider =
    StreamProvider<Map<StatGranularity, BestPeriod>>((ref) {
  return ref.watch(statsRepositoryProvider).watchBestPeriods();
});

final streaksProvider = StreamProvider<StreakInfo>((ref) {
  return ref.watch(statsRepositoryProvider).watchStreaks();
});

final allDayStatsProvider = StreamProvider<List<DayStats>>((ref) {
  return ref.watch(statsRepositoryProvider).watchAllStats();
});

/// Параметр для [summaryProvider]: диапазон дат включительно.
class StatsRange {
  const StatsRange(this.from, this.to);
  final DateTime from;
  final DateTime to;

  @override
  bool operator ==(Object other) =>
      other is StatsRange && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(from, to);
}

final summaryProvider =
    StreamProvider.family<StatsSummary, StatsRange>((ref, range) {
  return ref
      .watch(statsRepositoryProvider)
      .watchSummary(from: range.from, to: range.to);
});

/// Параметр для [productivityPointsProvider].
class PointsQuery {
  const PointsQuery({
    required this.from,
    required this.to,
    required this.grouping,
  });
  final DateTime from;
  final DateTime to;
  final ChartGrouping grouping;

  @override
  bool operator ==(Object other) =>
      other is PointsQuery &&
      other.from == from &&
      other.to == to &&
      other.grouping == grouping;

  @override
  int get hashCode => Object.hash(from, to, grouping);
}

final productivityPointsProvider =
    StreamProvider.family<List<ProductivityPoint>, PointsQuery>((ref, q) {
  return ref.watch(statsRepositoryProvider).watchProductivityPoints(
        from: q.from,
        to: q.to,
        grouping: q.grouping,
      );
});
