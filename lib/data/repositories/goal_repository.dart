import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/utils/date_utils.dart';
import '../../core/utils/haptics.dart';
import '../models/backlog_item.dart';
import '../models/goal.dart';
import '../models/task.dart' show SubTask, TaskPriority;
import '../sources/local/local_storage.dart';
import 'backlog_repository.dart';
import 'stats_repository.dart' show ChartGrouping;

const _kGoalsKey = 'goals';
const _kSnapshotsKey = 'goal_ring_snapshots';
const _uuid = Uuid();

// ─── Сводная статистика по целям одного типа периода ─────────────────────────

// ─── Статистика по целям, ограниченная диапазоном дат (для экрана Статистики,
// раздел «Цели») ───────────────────────────────────────────────────────────
//
// В отличие от [GoalPeriodStats] (накопительная, за всё время), эти считаются
// по аналогии с [StatsSummary]/[ProductivityPoint] задач: только по периодам,
// чей старт попадает в [from, to] и уже начался (не в будущем).

/// Одна точка графика целей. Смысл зависит от соотношения гранулярности
/// точки ([ChartGrouping]) и типа анализируемого периода ([GoalPeriod]):
/// • точка КРУПНЕЕ/РАВНА периоду — [value] = среднее итогов периодов, чей
///   старт попал в бакет («агрегатный» режим);
/// • точка МЕЛЬЧЕ периода — [value] = нарастающий итог целей содержащего
///   периода на конец бакета, сбрасывается на границе периода
///   («накопительный» режим); тогда [periodStart] != null и UI рисует
///   пунктирную границу там, где [periodStart] меняется.
class GoalProductivityPoint {
  const GoalProductivityPoint({
    required this.bucketStart,
    required this.value,
    this.onTimeValue,
    this.totalGoals = 0,
    this.periodStart,
    this.isPeriodEnd = false,
    this.boundaries = const [],
  });

  /// Начало бакета точки (день/неделя/месяц/год — по [ChartGrouping]).
  final DateTime bucketStart;

  /// Значение выполнения (0..1). null — нет данных (период не начался/нет
  /// целей этого типа в бакете).
  final double? value;

  /// Своевременность (0..1) — по той же логике, что и [value]. null — нет
  /// выполненных к этому моменту.
  final double? onTimeValue;

  /// Всего целей типа в бакете — вес за объём для «лучшего периода».
  final int totalGoals;

  /// Только для накопительного режима: старт goal-периода, к которому
  /// относится точка. Смена значения между соседними точками = граница
  /// периода (пунктир + сброс линии). null в агрегатном режиме.
  final DateTime? periodStart;

  /// Накопительный режим: точка — последний бакет своего периода, т.е. её
  /// значение = ИТОГ периода (для тултипа: подпись периодом, а не датой дня).
  final bool isPeriodEnd;

  /// Режим «Общий»: типы периодов, у которых на этом бакете НАЧАЛСЯ новый
  /// экземпляр (относительно предыдущего бакета) — UI рисует по ним пунктирные
  /// границы своим цветом на каждый тип, чтобы концы недель/месяцев/сезонов/лет
  /// можно было различить. Пусто в обычных режимах.
  final List<GoalPeriod> boundaries;
}

/// Результат для графика: точки + (в накопительном режиме) достаточно
/// информации, чтобы UI нарисовал пунктирные границы периодов. Границы
/// вычисляются в UI по смене [GoalProductivityPoint.periodStart] у соседних
/// точек — значение только что закончившегося периода = value левой точки
/// (она всегда итоговая, т.к. её бакет заканчивается концом периода).
class GoalChartData {
  const GoalChartData({
    required this.points,
    required this.cumulative,
    this.overall = false,
  });

  final List<GoalProductivityPoint> points;

  /// true — накопительный режим (точка мельче периода): UI рисует границы
  /// периодов по смене periodStart. false — агрегатный (точка ≥ период).
  final bool cumulative;

  /// true — режим «Общий» (среднее колец всех типов периодов): UI рисует
  /// границы по [GoalProductivityPoint.boundaries] (цвет на каждый тип), а не
  /// по periodStart; тултип не показывает «итог периода».
  final bool overall;

  static const empty = GoalChartData(points: [], cumulative: false);
}

/// Сводка за диапазон (аналог StatsSummary для задач).
class GoalStatsSummary {
  const GoalStatsSummary({
    required this.avgCompletion,
    required this.totalGoals,
    required this.completedGoals,
    required this.periodsWithData,
    required this.bestPeriod,
    required this.bestCompletion,
    this.bestOnTimeRate,
  });

  /// Средняя доля выполнения (0..1) по периодам с данными в диапазоне.
  final double? avgCompletion;
  final int totalGoals;
  final int completedGoals;
  final int periodsWithData;

  /// Лучший период по составному скору (см. [GoalRepository._compositeScore]).
  final GoalPeriodRef? bestPeriod;
  final double? bestCompletion;
  final double? bestOnTimeRate;

  static const empty = GoalStatsSummary(
    avgCompletion: null,
    totalGoals: 0,
    completedGoals: 0,
    periodsWithData: 0,
    bestPeriod: null,
    bestCompletion: null,
    bestOnTimeRate: null,
  );
}

class GoalRepository {
  GoalRepository(this._storage, this._goalBacklogRepo) {
    _reload();
  }

  final LocalStorage _storage;
  final GoalBacklogRepository _goalBacklogRepo;
  final _controller = StreamController<List<Goal>>.broadcast();
  List<Goal> _cache = [];

  /// Снимки кольца прогресса по дням: goalId → (день-эпохи → completionValue).
  /// Ведутся ТОЛЬКО для целей-счётчиков/чек-листов (у простых 0/1 completedAt
  /// и так точен). На каждом сохранении upsert записи «сегодня» = последнему
  /// значению дня; после смены дня запись «замерзает» (новых записей на ту
  /// дату нет). Позволяет строить нарастающую линию по фактическому кольцу на
  /// конец каждого дня — задним числом (до внедрения) данных нет, работает
  /// вперёд. Простые цели и отсутствующие дни — фоллбэк по completedAt.
  final Map<String, Map<int, double>> _snapshots = {};

  static int _dayKey(DateTime d) =>
      dateOnly(d).millisecondsSinceEpoch ~/ 86400000;

  void _reload() {
    _cache = _storage.readList(_kGoalsKey).map(Goal.fromJson).toList();
    _loadSnapshots();
    _controller.add(_cache);
  }

  void _loadSnapshots() {
    _snapshots.clear();
    final raw = _storage.readMap(_kSnapshotsKey);
    if (raw == null) return;
    raw.forEach((id, m) {
      _snapshots[id] = (m as Map).map(
          (k, v) => MapEntry(int.parse(k as String), (v as num).toDouble()));
    });
  }

  /// Обновляет снимки кольца на «сегодня» для counter/чек-лист целей.
  /// Возвращает true, если что-то изменилось (нужно персистить).
  bool _recordSnapshots() {
    final dayKey = _dayKey(DateTime.now());
    final liveIds = _cache.map((g) => g.id).toSet();
    var changed = false;
    // Убираем снимки удалённых целей.
    _snapshots.removeWhere((id, _) {
      final gone = !liveIds.contains(id);
      if (gone) changed = true;
      return gone;
    });
    for (final g in _cache) {
      if (!g.isCounter && !g.isChecklist) {
        // Простой цели снимок не нужен (completedAt точен); если раньше была
        // счётчиком и стала простой — чистим.
        if (_snapshots.remove(g.id) != null) changed = true;
        continue;
      }
      final m = _snapshots.putIfAbsent(g.id, () => {});
      final v = g.completionValue;
      if (m[dayKey] != v) {
        m[dayKey] = v;
        changed = true;
      }
    }
    return changed;
  }

  Future<void> _persistSnapshots() => _storage.writeMap(
        _kSnapshotsKey,
        _snapshots.map((id, m) =>
            MapEntry(id, m.map((k, v) => MapEntry(k.toString(), v)))),
      );

  Future<void> _save() async {
    await _storage.writeList(
        _kGoalsKey, _cache.map((g) => g.toJson()).toList());
    if (_recordSnapshots()) await _persistSnapshots();
    _controller.add(List.unmodifiable(_cache));
  }

  /// Значение кольца цели [g] на конец дня [d]: живое (текущее) для сегодня,
  /// иначе — последний снимок с датой ≤ d, а при отсутствии снимков —
  /// фоллбэк по completedAt (точен для простых целей и полного выполнения).
  double _ringAsOf(Goal g, DateTime d, int todayKey) {
    final dk = _dayKey(d);
    if (dk >= todayKey) return g.completionValue; // сегодня/будущее — вживую
    final snaps = _snapshots[g.id];
    if (snaps != null && snaps.isNotEmpty) {
      int? best;
      for (final k in snaps.keys) {
        if (k <= dk && (best == null || k > best)) best = k;
      }
      if (best != null) return snaps[best]!;
    }
    // Фоллбэк: до первого снимка / для простых целей.
    if (g.completedAt != null && !dateOnly(g.completedAt!).isAfter(d)) {
      return g.completionValue;
    }
    return 0.0;
  }

  // ─── Фильтрация по периоду ─────────────────────────────────────────────────

  static bool _matches(Goal g, GoalPeriodRef ref) {
    if (g.period != ref.period) return false;
    switch (ref.period) {
      case GoalPeriod.week:
        return g.weekStart != null &&
            dateOnly(g.weekStart!) == dateOnly(ref.weekStart!);
      case GoalPeriod.month:
        return g.year == ref.year && g.month == ref.month;
      case GoalPeriod.season:
        return g.year == ref.year && g.season == ref.season;
      case GoalPeriod.year:
        return g.year == ref.year;
    }
  }

  // ─── Подписки ──────────────────────────────────────────────────────────────

  Stream<List<Goal>> watchGoalsForRef(GoalPeriodRef ref) async* {
    yield _cache.where((g) => _matches(g, ref)).toList();
    await for (final all in _controller.stream) {
      yield all.where((g) => _matches(g, ref)).toList();
    }
  }

  Stream<List<Goal>> watchAllGoals() async* {
    yield List.unmodifiable(_cache);
    await for (final all in _controller.stream) {
      yield all;
    }
  }

  /// Невыполненные, ещё не перенесённые (не «призраки») цели — для
  /// планирования уведомлений «требует внимания»/«просрочена» (аналог
  /// TaskRepository.timedTasks для задач).
  List<Goal> activeGoals() =>
      _cache.where((g) => !g.completed && !g.isTransferred).toList();

  static double _compositeScore(double p, double t) => p * (0.7 + 0.3 * t);

  /// Константа насыщения веса за объём (см. stats_repository.kVolumeK).
  static const double _kVolumeK = 4.0;

  // ─── Статистика по диапазону (график + сводка на экране Статистики) ───────

  Stream<GoalStatsSummary> watchGoalStatsSummary({
    required GoalPeriod? period,
    required DateTime from,
    required DateTime to,
  }) async* {
    yield _goalsSummaryOf(_cache, period, from, to);
    await for (final all in _controller.stream) {
      yield _goalsSummaryOf(all, period, from, to);
    }
  }

  Stream<GoalChartData> watchGoalChart({
    required GoalPeriod? period,
    required ChartGrouping grouping,
    required DateTime from,
    required DateTime to,
  }) async* {
    yield _goalChartOf(_cache, period, grouping, from, to);
    await for (final all in _controller.stream) {
      yield _goalChartOf(all, period, grouping, from, to);
    }
  }

  /// Группирует цели типа [period] по конкретному периоду (ref.key) — общая
  /// часть для сводки и точек графика.
  static Map<String, List<Goal>> _byPeriodKey(
      List<Goal> all, GoalPeriod period) {
    final byKey = <String, List<Goal>>{};
    for (final g in all) {
      if (g.period != period) continue;
      byKey.putIfAbsent(g.ref.key, () => []).add(g);
    }
    return byKey;
  }

  /// Сводка за диапазон. [period] == null — режим «Общий»: считаем по ВСЕМ
  /// типам, средняя доля = среднее из средних по каждому типу (равный вес на
  /// тип; тип без целей в диапазоне не участвует — как и в графике «Общий»);
  /// «лучший период» = лучшая КАЛЕНДАРНАЯ НЕДЕЛЯ по блендованной продуктивности
  /// всех типов (та же величина, что на графике «Общий»), см. [_overallBestWeek].
  GoalStatsSummary _goalsSummaryOf(
    List<Goal> all,
    GoalPeriod? period,
    DateTime from,
    DateTime to,
  ) {
    final todayDate = today();
    final toDay = dateOnly(to);
    final types = period == null ? GoalPeriod.values : [period];

    var totalGoals = 0;
    var completedGoals = 0;
    var periodsWithData = 0;
    var typeAvgSum = 0.0; // сумма средних по типам
    var typesWithData = 0;
    GoalPeriodRef? bestPeriod;
    double? bestCompletion;
    double? bestOnTimeRate;
    var bestScore = -1.0;

    for (final t in types) {
      // Нижняя граница — старт периода, СОДЕРЖАЩЕГО from (не сам from), тем же
      // способом, что и первый бакет графика — иначе сводка и график
      // расходились бы по набору периодов.
      final firstBucketStart = GoalPeriodRef.current(t, from).start;
      final inRange = <String, List<Goal>>{};
      _byPeriodKey(all, t).forEach((key, goals) {
        final start = goals.first.ref.start;
        if (start.isBefore(firstBucketStart) || start.isAfter(toDay)) return;
        if (start.isAfter(todayDate)) return; // будущий период — не считаем
        inRange[key] = goals;
      });
      if (inRange.isEmpty) continue;

      var typeSumRate = 0.0;
      inRange.forEach((key, goals) {
        totalGoals += goals.length;
        final done = goals.where((g) => g.completed).toList();
        completedGoals += done.length;
        final rate = goals.fold<double>(0, (s, g) => s + g.completionValue) /
            goals.length;
        typeSumRate += rate;
        final onTime = done.where((g) => g.isOnTime).length;
        // Своевременность для СКОРА = 0, если ни одна цель не доведена до конца:
        // период «доделано, но поздно» ранжируется выше «ничего не финишировано».
        final tRate = done.isEmpty ? 0.0 : onTime / done.length;
        final score = _compositeScore(rate, tRate) *
            (goals.length / (goals.length + _kVolumeK));
        final ref = goals.first.ref;
        final better = score > bestScore + 1e-9 ||
            ((score - bestScore).abs() < 1e-9 &&
                bestPeriod != null &&
                ref.start.isAfter(bestPeriod!.start));
        if (bestPeriod == null || better) {
          bestScore = score;
          bestPeriod = ref;
          bestCompletion = rate;
          bestOnTimeRate = done.isEmpty ? null : onTime / done.length;
        }
      });
      periodsWithData += inRange.length;
      typeAvgSum += typeSumRate / inRange.length;
      typesWithData++;
    }

    if (typesWithData == 0) return GoalStatsSummary.empty;

    // В режиме «Общий» «лучший период» — это лучшая неделя по продуктивности
    // всех типов сразу (см. метод), а не отдельный экземпляр одного типа.
    if (period == null) {
      final (bw, bwc, bwt) = _overallBestWeek(all, from, toDay, todayDate);
      bestPeriod = bw;
      bestCompletion = bwc;
      bestOnTimeRate = bwt;
    }

    return GoalStatsSummary(
      avgCompletion: typeAvgSum / typesWithData,
      totalGoals: totalGoals,
      completedGoals: completedGoals,
      periodsWithData: periodsWithData,
      bestPeriod: bestPeriod,
      bestCompletion: bestCompletion,
      bestOnTimeRate: bestOnTimeRate,
    );
  }

  /// «Лучшая неделя» для режима «Общий»: перебираем календарные недели диапазона
  /// и для каждой берём ту же блендованную продуктивность всех типов, что рисует
  /// график «Общий» (среднее колец недели/месяца/сезона/года на конец недели —
  /// [_ringAsOf]; тип без целей в его текущем экземпляре не участвует). Скорим
  /// той же формулой, что и обычные периоды ([_compositeScore] × вес за объём),
  /// и берём максимум. Так «лучший период» = самая продуктивная неделя, что видно
  /// на графике, и учитываются ВСЕ цели, а не только недельные.
  /// Возвращает (неделя|null, её выполнение|null, её своевременность|null).
  (GoalPeriodRef?, double?, double?) _overallBestWeek(
    List<Goal> all,
    DateTime from,
    DateTime toDay,
    DateTime todayDate,
  ) {
    final todayKey = _dayKey(todayDate);
    final byType = <GoalPeriod, Map<String, List<Goal>>>{
      for (final p in GoalPeriod.values) p: _byPeriodKey(all, p),
    };

    GoalPeriodRef? best;
    double? bestCompletion;
    double? bestOnTime;
    var bestScore = -1.0;

    var cursor = startOfWeek(from);
    final end = startOfWeek(toDay);
    var guard = 0;
    while (!cursor.isAfter(end) && guard < 100000) {
      guard++;
      if (cursor.isAfter(todayDate)) break; // будущие недели не считаем
      var weekEnd = cursor.add(const Duration(days: 6));
      if (weekEnd.isAfter(todayDate)) weekEnd = todayDate;

      var sumRing = 0.0;
      var sumOnTime = 0.0;
      var typesCounted = 0;
      var totalGoals = 0;
      var doneTotal = 0;
      for (final t in GoalPeriod.values) {
        final ref = GoalPeriodRef.current(t, weekEnd);
        final goals = byType[t]![ref.key];
        if (goals == null || goals.isEmpty) continue;
        typesCounted++;
        totalGoals += goals.length;
        sumRing += goals.fold<double>(
                0, (s, g) => s + _ringAsOf(g, weekEnd, todayKey)) /
            goals.length;
        var done = 0;
        var onTime = 0;
        for (final g in goals) {
          if (g.completedAt == null) continue;
          if (dateOnly(g.completedAt!).isAfter(weekEnd)) continue;
          done++;
          if (g.isOnTime) onTime++;
        }
        sumOnTime += done == 0 ? 0.0 : onTime / done;
        doneTotal += done;
      }

      if (typesCounted > 0) {
        final rate = sumRing / typesCounted;
        final tRate = sumOnTime / typesCounted;
        final score = _compositeScore(rate, tRate) *
            (totalGoals / (totalGoals + _kVolumeK));
        final weekRef = GoalPeriodRef.current(GoalPeriod.week, cursor);
        final better = score > bestScore + 1e-9 ||
            ((score - bestScore).abs() < 1e-9 &&
                best != null &&
                weekRef.start.isAfter(best.start));
        if (best == null || better) {
          bestScore = score;
          best = weekRef;
          bestCompletion = rate;
          // На карточке своевременность честно скрываем, если за неделю ничего
          // не доведено до конца (нечего судить «в срок»).
          bestOnTime = doneTotal == 0 ? null : tRate;
        }
      }
      cursor = cursor.add(const Duration(days: 7));
    }
    return (best, bestCompletion, bestOnTime);
  }

  // ── Ранги гранулярности (для выбора режима графика) ──────────────────────
  // День(0) < Неделя(1) < Месяц(2) < Сезон(3) < Год(4). У точек графика сезона
  // нет, поэтому у ChartGrouping ранг сезона пропущен (сразу год=4).
  static int _chartRank(ChartGrouping g) => switch (g) {
        ChartGrouping.daily => 0,
        ChartGrouping.weekly => 1,
        ChartGrouping.monthly => 2,
        ChartGrouping.yearly => 4,
      };
  static int _periodRank(GoalPeriod p) => switch (p) {
        GoalPeriod.week => 1,
        GoalPeriod.month => 2,
        GoalPeriod.season => 3,
        GoalPeriod.year => 4,
      };

  static DateTime _chartBucketStart(DateTime d, ChartGrouping g) => switch (g) {
        ChartGrouping.daily => dateOnly(d),
        ChartGrouping.weekly => startOfWeek(d),
        ChartGrouping.monthly => startOfMonth(d),
        ChartGrouping.yearly => startOfYear(d),
      };
  static DateTime _chartNextBucket(DateTime c, ChartGrouping g) => switch (g) {
        ChartGrouping.daily => c.add(const Duration(days: 1)),
        ChartGrouping.weekly => c.add(const Duration(days: 7)),
        ChartGrouping.monthly => DateTime(c.year, c.month + 1),
        ChartGrouping.yearly => DateTime(c.year + 1),
      };

  /// Итог периода = то, что сейчас на кольце (дробно, с частичным прогрессом).
  /// Для завершённого периода это финальное состояние, для текущего — «на
  /// сейчас»; в обоих случаях = [Goal.completionValue], поэтому дата не нужна.
  /// Возвращает (доля выполнения, доля «в срок» среди достигнутых|null).
  static (double, double?) _periodTotal(List<Goal> goals) {
    final rate =
        goals.fold<double>(0, (s, g) => s + g.completionValue) / goals.length;
    final done = goals.where((g) => g.completed).toList();
    final onTime = done.where((g) => g.isOnTime).length;
    return (rate, done.isEmpty ? null : onTime / done.length);
  }

  GoalChartData _goalChartOf(
    List<Goal> all,
    GoalPeriod? period,
    ChartGrouping grouping,
    DateTime from,
    DateTime to,
  ) {
    final todayDate = today();
    final toDay = dateOnly(to);
    if (period == null) {
      // «Общий» — среднее колец всех типов периодов на конец каждого бакета.
      return GoalChartData(
        points: _overallPoints(all, grouping, from, toDay, todayDate),
        cumulative: true,
        overall: true,
      );
    }
    final byKey = _byPeriodKey(all, period);
    final cumulative = _chartRank(grouping) < _periodRank(period);

    return cumulative
        ? GoalChartData(
            points: _cumulativePoints(
                byKey, period, grouping, from, toDay, todayDate),
            cumulative: true,
          )
        : GoalChartData(
            points: _aggregatePoints(
                byKey, period, grouping, from, toDay, todayDate),
            cumulative: false,
          );
  }

  /// Агрегатный режим (точка ≥ период): каждый бакет графика = среднее итогов
  /// периодов выбранного типа, ЗАВЕРШИВШИХСЯ в бакете (итог существует только
  /// когда период окончен). Текущий незавершённый период кладётся в бакет
  /// «сегодня» — его итог берётся «на сейчас».
  static List<GoalProductivityPoint> _aggregatePoints(
    Map<String, List<Goal>> byKey,
    GoalPeriod period,
    ChartGrouping grouping,
    DateTime from,
    DateTime toDay,
    DateTime todayDate,
  ) {
    // Период кладём в бакет по дате его КОНЦА (для текущего — «сегодня»).
    final periodsByBucket = <DateTime, List<List<Goal>>>{};
    byKey.forEach((key, goals) {
      final ref = goals.first.ref;
      if (ref.start.isAfter(todayDate)) return; // ещё не начался
      final endDate =
          ref.endInclusive.isBefore(todayDate) ? ref.endInclusive : todayDate;
      final bucket = _chartBucketStart(endDate, grouping);
      periodsByBucket.putIfAbsent(bucket, () => []).add(goals);
    });

    final points = <GoalProductivityPoint>[];
    var cursor = _chartBucketStart(from, grouping);
    final end = _chartBucketStart(toDay, grouping);
    var guard = 0;
    while (!cursor.isAfter(end) && guard < 100000) {
      guard++;
      final periods = periodsByBucket[cursor];
      if (periods == null || periods.isEmpty) {
        points.add(GoalProductivityPoint(bucketStart: cursor, value: null));
      } else {
        var sumRate = 0.0;
        var sumOnTime = 0.0;
        var totalGoals = 0;
        for (final goals in periods) {
          final (rate, ot) = _periodTotal(goals);
          sumRate += rate;
          totalGoals += goals.length;
          // Если в периоде ничего не выполнено полностью — своевременность 0%,
          // а не «нет данных»: точка выполнения есть → есть и точка своевр-ти.
          sumOnTime += ot ?? 0.0;
        }
        points.add(GoalProductivityPoint(
          bucketStart: cursor,
          value: sumRate / periods.length,
          onTimeValue: sumOnTime / periods.length,
          totalGoals: totalGoals,
        ));
      }
      cursor = _chartNextBucket(cursor, grouping);
    }
    return points;
  }

  /// Накопительный режим (точка мельче периода): точки идут по гранулярности
  /// графика; значение = нарастающий итог целей содержащего goal-периода на
  /// КОНЕЦ бакета — фактическое кольцо прогресса на тот день (снимки, а при их
  /// отсутствии — фоллбэк по completedAt), см. [_ringAsOf]. Своевременность —
  /// доля вовремя достигнутых среди достигнутых к тому моменту. periodStart
  /// меняется на границе периода → UI рисует пунктир и линия сбрасывается;
  /// [GoalProductivityPoint.isPeriodEnd] помечает последний бакет периода
  /// (его значение = итог периода).
  List<GoalProductivityPoint> _cumulativePoints(
    Map<String, List<Goal>> byKey,
    GoalPeriod period,
    ChartGrouping grouping,
    DateTime from,
    DateTime toDay,
    DateTime todayDate,
  ) {
    final todayKey = _dayKey(todayDate);
    final points = <GoalProductivityPoint>[];
    var cursor = _chartBucketStart(from, grouping);
    final end = _chartBucketStart(toDay, grouping);
    var guard = 0;
    while (!cursor.isAfter(end) && guard < 100000) {
      guard++;
      final ref = GoalPeriodRef.current(period, cursor);
      // Конец бакета, но не позже конца периода и не позже сегодня.
      var bucketEnd =
          _chartNextBucket(cursor, grouping).subtract(const Duration(days: 1));
      if (bucketEnd.isAfter(ref.endInclusive)) bucketEnd = ref.endInclusive;
      if (bucketEnd.isAfter(todayDate)) bucketEnd = todayDate;

      final goals = byKey[ref.key];
      final periodStarted = !ref.start.isAfter(todayDate);
      if (!periodStarted || goals == null || goals.isEmpty) {
        points.add(GoalProductivityPoint(
          bucketStart: cursor,
          value: null,
          periodStart: ref.start,
        ));
      } else {
        // Выполнение = среднее колец на конец бакета (реальное значение того
        // дня). Своевременность = среди достигнутых к bucketEnd — доля в срок.
        final rate = goals.fold<double>(
                0, (s, g) => s + _ringAsOf(g, bucketEnd, todayKey)) /
            goals.length;
        var done = 0;
        var onTime = 0;
        for (final g in goals) {
          if (g.completedAt == null) continue;
          if (dateOnly(g.completedAt!).isAfter(bucketEnd)) continue;
          done++;
          if (g.isOnTime) onTime++;
        }
        final periodEval =
            ref.endInclusive.isBefore(todayDate) ? ref.endInclusive : todayDate;
        points.add(GoalProductivityPoint(
          bucketStart: cursor,
          value: rate,
          // Точка выполнения есть → точка своевр-ти тоже: 0%, если пока ни одна
          // цель периода не достигнута полностью.
          onTimeValue: done == 0 ? 0.0 : onTime / done,
          totalGoals: goals.length,
          periodStart: ref.start,
          isPeriodEnd: !bucketEnd.isBefore(periodEval),
        ));
      }
      cursor = _chartNextBucket(cursor, grouping);
    }
    return points;
  }

  /// Режим «Общий»: на конец каждого бакета берём кольцо КАЖДОГО типа периода
  /// (недели/месяца/сезона/года), содержащего этот момент, и усредняем.
  /// • тип без целей в текущем экземпляре — НЕ учитывается (не занижает);
  /// • тип с целями, но без достижений — учитывается как своё кольцо (0 или
  ///   частичный прогресс);
  /// • своевременность — по той же схеме (среднее долей «в срок» по учтённым
  ///   типам), с тем же спариванием (есть точка выполнения → есть и своевр-ти).
  /// В [GoalProductivityPoint.boundaries] пишем типы, у которых на этом бакете
  /// начался новый экземпляр (для различимых пунктирных границ), но только для
  /// типов КРУПНЕЕ гранулярности точки — иначе граница мельче бакета зашумила
  /// бы график (напр. границы недель при месячной точке).
  List<GoalProductivityPoint> _overallPoints(
    List<Goal> all,
    ChartGrouping grouping,
    DateTime from,
    DateTime toDay,
    DateTime todayDate,
  ) {
    final todayKey = _dayKey(todayDate);
    final byType = <GoalPeriod, Map<String, List<Goal>>>{
      for (final p in GoalPeriod.values) p: _byPeriodKey(all, p),
    };
    final chartRank = _chartRank(grouping);

    final points = <GoalProductivityPoint>[];
    final prevKey = <GoalPeriod, String>{};
    var cursor = _chartBucketStart(from, grouping);
    final end = _chartBucketStart(toDay, grouping);
    var guard = 0;
    while (!cursor.isAfter(end) && guard < 100000) {
      guard++;
      // Бакет целиком в будущем — данных нет (не повторяем сегодняшние кольца).
      if (cursor.isAfter(todayDate)) {
        points.add(GoalProductivityPoint(bucketStart: cursor, value: null));
        cursor = _chartNextBucket(cursor, grouping);
        continue;
      }
      var bucketEnd =
          _chartNextBucket(cursor, grouping).subtract(const Duration(days: 1));
      if (bucketEnd.isAfter(todayDate)) bucketEnd = todayDate;

      var sumRing = 0.0;
      var sumOnTime = 0.0;
      var typesCounted = 0;
      var totalGoals = 0;
      final boundaries = <GoalPeriod>[];

      for (final t in GoalPeriod.values) {
        final ref = GoalPeriodRef.current(t, bucketEnd);
        // Граница типа: сменился экземпляр относительно прошлого бакета. Рисуем
        // только для типов крупнее точки (иначе внутри бакета их несколько).
        if (chartRank < _periodRank(t) &&
            prevKey.containsKey(t) &&
            prevKey[t] != ref.key) {
          boundaries.add(t);
        }
        prevKey[t] = ref.key;

        final goals = byType[t]![ref.key];
        if (goals == null || goals.isEmpty)
          continue; // нет целей типа → пропуск
        typesCounted++;
        totalGoals += goals.length;
        sumRing += goals.fold<double>(
                0, (s, g) => s + _ringAsOf(g, bucketEnd, todayKey)) /
            goals.length;
        var done = 0;
        var onTime = 0;
        for (final g in goals) {
          if (g.completedAt == null) continue;
          if (dateOnly(g.completedAt!).isAfter(bucketEnd)) continue;
          done++;
          if (g.isOnTime) onTime++;
        }
        sumOnTime += done == 0 ? 0.0 : onTime / done;
      }

      points.add(GoalProductivityPoint(
        bucketStart: cursor,
        value: typesCounted == 0 ? null : sumRing / typesCounted,
        onTimeValue: typesCounted == 0 ? null : sumOnTime / typesCounted,
        totalGoals: totalGoals,
        boundaries: boundaries,
      ));
      cursor = _chartNextBucket(cursor, grouping);
    }
    return points;
  }

  // ─── CRUD ──────────────────────────────────────────────────────────────────

  Future<Goal> addGoal({
    required String title,
    required GoalPeriod period,
    required int year,
    int? month,
    int? season,
    DateTime? weekStart,
    String? description,
    DateTime? startDate,
    DateTime? deadline,
    int? targetCount,
    List<String> subtaskTitles = const [],
    TaskPriority priority = TaskPriority.none,
    List<String> tags = const [],
  }) async {
    final now = DateTime.now();
    final goal = Goal(
      id: _uuid.v4(),
      title: title,
      period: period,
      year: year,
      month: month,
      season: season,
      weekStart: weekStart == null ? null : dateOnly(weekStart),
      description: description,
      startDate: startDate,
      deadline: deadline,
      targetCount: targetCount,
      subtasks: [
        for (final t in subtaskTitles) SubTask(id: _uuid.v4(), title: t),
      ],
      priority: priority,
      tags: tags,
      createdAt: now,
      updatedAt: now,
    );
    _cache.add(goal);
    await _save();
    return goal;
  }

  /// Пересобирает цель с новыми manual/linked, пересчитывая completed/completedAt.
  Goal _withProgress(Goal cur, {int? manual, int? linked}) {
    final now = DateTime.now();
    final m = manual ?? cur.manualProgress;
    final l = linked ?? cur.linkedProgress;
    final total = m + l;
    final reached = cur.targetCount != null && total >= cur.targetCount!;
    return cur.copyWith(
      manualProgress: m,
      linkedProgress: l,
      completed: reached,
      completedAt: reached ? (cur.completedAt ?? now) : null,
      clearCompletedAt: !reached,
      updatedAt: now,
    );
  }

  /// Изменяет счётчик цели на [delta] (обычно +1/−1) — меняет ручную часть.
  Future<void> incrementGoalCounter(Goal goal, int delta) =>
      setGoalProgress(goal, goal.progressCount + delta);

  /// Устанавливает ИТОГОВЫЙ прогресс в [value] (ручной ввод). Ручная часть
  /// выводится как value − вклад задач (не ниже 0).
  Future<void> setGoalProgress(Goal goal, int value) async {
    final idx = _cache.indexWhere((g) => g.id == goal.id);
    if (idx == -1) return;
    final cur = _cache[idx];
    if (!cur.isCounter) return;
    final desired = value.clamp(0, cur.targetCount!);
    final manual = (desired - cur.linkedProgress).clamp(0, cur.targetCount!);
    if (manual == cur.manualProgress) return;
    _cache[idx] = _withProgress(cur, manual: manual);
    if (_cache[idx].completed && !cur.completed)
      Haptics.completed(); // цель добита
    await _save();
  }

  /// Обновляет вклад привязанных задач (вызывается из TaskRepository).
  Future<void> setLinkedProgress(String goalId, int sum) async {
    final idx = _cache.indexWhere((g) => g.id == goalId);
    if (idx == -1) return;
    final cur = _cache[idx];
    if (!cur.isCounter) return;
    final l = sum.clamp(0, cur.targetCount!);
    if (l == cur.linkedProgress) return;
    _cache[idx] = _withProgress(cur, linked: l);
    await _save();
  }

  /// Цели-счётчики, чей период содержит [date] — кандидаты для привязки задачи.
  List<Goal> counterGoalsForDate(DateTime date) {
    final d = dateOnly(date);
    return _cache.where((g) {
      if (!g.isCounter) return false;
      final ref = g.ref;
      return !d.isBefore(ref.start) && !d.isAfter(ref.endInclusive);
    }).toList();
  }

  Future<void> toggleComplete(Goal goal) async {
    final idx = _cache.indexWhere((g) => g.id == goal.id);
    if (idx == -1) return;
    final now = DateTime.now();
    final nowCompleting = !goal.completed;
    if (nowCompleting) Haptics.completed(); // цель отмечена выполненной
    _cache[idx] = goal.copyWith(
      completed: nowCompleting,
      completedAt: nowCompleting ? now : null,
      clearCompletedAt: !nowCompleting,
      updatedAt: now,
    );
    await _save();
  }

  /// Переключает подзадачу цели. Когда все выполнены — цель достигается
  /// (как счётчик); если снова не все — снимается достижение.
  Future<void> toggleGoalSubtask(Goal goal, String subtaskId) async {
    final idx = _cache.indexWhere((g) => g.id == goal.id);
    if (idx == -1) return;
    final cur = _cache[idx];
    final subs = cur.subtasks
        .map((s) => s.id == subtaskId ? s.copyWith(done: !s.done) : s)
        .toList();
    final allDone = subs.isNotEmpty && subs.every((s) => s.done);
    final now = DateTime.now();
    if (allDone && !cur.completed)
      Haptics.completed(); // последняя подзадача цели
    _cache[idx] = cur.copyWith(
      subtasks: subs,
      completed: allDone,
      completedAt: allDone ? (cur.completedAt ?? now) : null,
      clearCompletedAt: !allDone,
      updatedAt: now,
    );
    await _save();
  }

  /// Отмечает все подзадачи цели как [done] разом и синхронизирует статус.
  Future<void> setAllGoalSubtasksDone(Goal goal, bool done) async {
    final idx = _cache.indexWhere((g) => g.id == goal.id);
    if (idx == -1) return;
    final cur = _cache[idx];
    if (cur.subtasks.isEmpty) return;
    final subs = cur.subtasks.map((s) => s.copyWith(done: done)).toList();
    final now = DateTime.now();
    if (done && !cur.completed) Haptics.completed(); // цель отмечена целиком
    _cache[idx] = cur.copyWith(
      subtasks: subs,
      completed: done,
      completedAt: done ? (cur.completedAt ?? now) : null,
      clearCompletedAt: !done,
      updatedAt: now,
    );
    await _save();
  }

  /// Обновляет цель целиком (включая дедлайн и заголовок).
  Future<void> updateGoal(Goal goal) async {
    final idx = _cache.indexWhere((g) => g.id == goal.id);
    if (idx == -1) return;
    _cache[idx] = goal;
    await _save();
  }

  /// Устаревший метод — оставлен для совместимости.
  Future<void> updateTitle(Goal goal, String newTitle) async =>
      updateGoal(goal.copyWith(title: newTitle, updatedAt: DateTime.now()));

  /// Ставит субъективную оценку качества достижения (рефлексия).
  Future<void> setQuality(Goal goal, int quality) async {
    final idx = _cache.indexWhere((g) => g.id == goal.id);
    if (idx == -1) return;
    _cache[idx] = _cache[idx].copyWith(quality: quality);
    await _save();
  }

  Future<void> deleteGoal(String id) async {
    final goal = _cache.where((g) => g.id == id).firstOrNull;
    _cache.removeWhere((g) => g.id == id);
    await _save();

    // Если удаляется перенесённая копия → отправляем в бэклог
    if (goal != null && goal.transferredFromId != null && !goal.completed) {
      final original =
          _cache.where((g) => g.id == goal.transferredFromId).firstOrNull;
      await _goalBacklogRepo.add(GoalBacklogItem(
        id: _uuid.v4(),
        title: goal.title,
        description: goal.description,
        period: goal.period,
        originalRef: original?.ref ?? goal.ref,
        addedAt: DateTime.now(),
        targetCount: goal.targetCount,
        progressCount: goal.manualProgress,
        subtaskTitles: goal.subtasks.map((s) => s.title).toList(),
      ));
    }
  }

  /// Копирует цели в указанный период [target]. Дедлайн и статус выполнения
  /// не копируются.
  Future<void> copyGoalsTo({
    required List<Goal> goals,
    required GoalPeriodRef target,
  }) async {
    final now = DateTime.now();
    for (final src in goals) {
      _cache.add(Goal(
        id: _uuid.v4(),
        title: src.title,
        description: src.description,
        period: target.period,
        year: target.year,
        month: target.month,
        season: target.season,
        weekStart:
            target.weekStart == null ? null : dateOnly(target.weekStart!),
        targetCount: src.targetCount,
        subtasks: [
          for (final s in src.subtasks) SubTask(id: _uuid.v4(), title: s.title),
        ],
        priority: src.priority,
        tags: src.tags,
        createdAt: now,
        updatedAt: now,
      ));
    }
    await _save();
  }

  /// Удаляет все цели указанного периода.
  Future<void> deleteAllForPeriod(GoalPeriodRef ref) async {
    _cache.removeWhere((g) => _matches(g, ref));
    await _save();
  }

  /// Возвращает отсортированный список лет, в которых есть хотя бы одна цель «на год».
  List<int> allYearGoalYears() {
    return _cache
        .where((g) => g.period == GoalPeriod.year)
        .map((g) => g.year)
        .toSet()
        .toList()
      ..sort();
  }

  // ─── Перенос целей ────────────────────────────────────────────────────────

  /// Переносит цель в период [targetRef]:
  /// • создаёт копию в целевом периоде (с [transferredFromId] = goal.id)
  /// • помечает оригинал как [isTransferred] = true
  Future<void> transferGoal(Goal goal,
      {required GoalPeriodRef targetRef}) async {
    final now = DateTime.now();
    final copy = Goal(
      id: _uuid.v4(),
      title: goal.title,
      description: goal.description,
      period: targetRef.period,
      year: targetRef.year,
      month: targetRef.month,
      season: targetRef.season,
      weekStart:
          targetRef.weekStart == null ? null : dateOnly(targetRef.weekStart!),
      targetCount: goal.targetCount,
      manualProgress: goal.manualProgress,
      // Переносим подзадачи С их состоянием (живая копия).
      subtasks: [
        for (final s in goal.subtasks)
          SubTask(id: _uuid.v4(), title: s.title, done: s.done),
      ],
      priority: goal.priority,
      tags: goal.tags,
      transferredFromId: goal.id,
      createdAt: now,
      updatedAt: now,
    );
    _cache.add(copy);
    final idx = _cache.indexWhere((g) => g.id == goal.id);
    if (idx != -1) {
      _cache[idx] = _cache[idx].copyWith(isTransferred: true, updatedAt: now);
    }
    await _save();
  }

  /// Переносит все незавершённые цели периода [ref] в [targetRef].
  Future<void> transferAllUncompletedForPeriod(GoalPeriodRef ref,
      {required GoalPeriodRef targetRef}) async {
    final toTransfer = _cache
        .where((g) =>
            _matches(g, ref) &&
            !g.completed &&
            !g.isTransferred &&
            g.transferredFromId == null)
        .toList();
    for (final g in toTransfer) {
      await transferGoal(g, targetRef: targetRef);
    }
  }

  /// Незавершённые ОРИГИНАЛЫ прошедших периодов, которые ещё не переносили
  /// и от переноса которых пользователь явно не отказался
  /// ([Goal.transferDeclined]) — кандидаты на перенос в текущий период.
  /// Чистый запрос, ничего не меняет: решение принимает пользователь
  /// (баннер/догоняющий список).
  List<Goal> transferCandidates({required DateTime now}) {
    final todayDate = dateOnly(now);
    return _cache
        .where((g) =>
            !g.completed &&
            !g.isTransferred &&
            !g.transferDeclined &&
            g.transferredFromId == null &&
            g.periodEnd.isBefore(todayDate))
        .toList();
  }

  /// Переносит выбранные цели в их текущий период — вызывается после
  /// подтверждения пользователем (баннер или догоняющий список).
  Future<void> transferSelected(List<Goal> goals,
      {required DateTime now}) async {
    for (final g in goals) {
      final currentRef = GoalPeriodRef.current(g.period, now);
      await transferGoal(g, targetRef: currentRef);
    }
  }

  /// Пользователь отказался переносить цель — помечаем, чтобы больше не
  /// предлагать; цель остаётся обычной невыполненной в своём периоде.
  Future<void> declineTransfer(Goal goal) async {
    final idx = _cache.indexWhere((g) => g.id == goal.id);
    if (idx == -1) return;
    _cache[idx] =
        _cache[idx].copyWith(transferDeclined: true, updatedAt: DateTime.now());
    await _save();
  }

  /// Незавершённые КОПИИ, чей (новый) период тоже завершился, И незавершённые
  /// ОРИГИНАЛЫ, от переноса которых пользователь явно отказался
  /// ([Goal.transferDeclined]), → в бэклог «Недостигнутые цели». Без второй
  /// ветки отказ от переноса был тупиком: цель переставала предлагаться
  /// ([transferCandidates] уже фильтрует по `!transferDeclined`) и никогда
  /// не попадала в бэклог — исчезала из вида навсегда (см. тот же фикс в
  /// TaskRepository.demoteStaleTransferredCopies). Тихая автоматическая
  /// механика списания — не тот же смысл, что «перенести или нет»: решение
  /// уже принято одним из двух способов.
  Future<void> demoteStaleTransferredCopies({required DateTime now}) async {
    final todayDate = dateOnly(now);
    final stale = _cache
        .where((g) =>
            !g.completed &&
            !g.isTransferred &&
            g.periodEnd.isBefore(todayDate) &&
            (g.transferredFromId != null || g.transferDeclined))
        .toList();
    for (final g in stale) {
      await _sendGoalToBacklogAndMark(g);
    }
  }

  /// Отправляет недостигнутую цель (перенесённую копию ИЛИ оригинал с
  /// отклонённым переносом) в бэклог и помечает её [isTransferred] (серый
  /// след в прошлом периоде — уже учтена, больше не предлагается).
  Future<void> _sendGoalToBacklogAndMark(Goal goal) async {
    final original =
        _cache.where((g) => g.id == goal.transferredFromId).firstOrNull;
    await _goalBacklogRepo.add(GoalBacklogItem(
      id: _uuid.v4(),
      title: goal.title,
      description: goal.description,
      period: goal.period,
      originalRef: original?.ref ?? goal.ref,
      addedAt: DateTime.now(),
      targetCount: goal.targetCount,
      progressCount: goal.manualProgress,
      subtaskTitles: goal.subtasks.map((s) => s.title).toList(),
    ));
    final idx = _cache.indexWhere((g) => g.id == goal.id);
    if (idx != -1) {
      _cache[idx] =
          _cache[idx].copyWith(isTransferred: true, updatedAt: DateTime.now());
      await _save();
    }
  }

  void dispose() => _controller.close();
}

final goalRepositoryProvider = Provider<GoalRepository>((ref) {
  final repo = GoalRepository(
    ref.watch(localStorageProvider),
    ref.watch(goalBacklogRepositoryProvider),
  );
  ref.onDispose(repo.dispose);
  return repo;
});

final allGoalsProvider = StreamProvider<List<Goal>>((ref) {
  return ref.watch(goalRepositoryProvider).watchAllGoals();
});

/// Параметр для [goalStatsSummaryProvider] (сводка не зависит от гранулярности
/// точки графика — только тип периода + диапазон).
class GoalStatsRange {
  const GoalStatsRange({
    required this.period,
    required this.from,
    required this.to,
  });

  /// null — режим «Общий» (все типы периодов сразу).
  final GoalPeriod? period;
  final DateTime from;
  final DateTime to;

  @override
  bool operator ==(Object other) =>
      other is GoalStatsRange &&
      other.period == period &&
      other.from == from &&
      other.to == to;

  @override
  int get hashCode => Object.hash(period, from, to);
}

/// Параметр для [goalChartProvider] — добавляет гранулярность точки графика.
class GoalChartRange {
  const GoalChartRange({
    required this.period,
    required this.grouping,
    required this.from,
    required this.to,
  });

  /// null — режим «Общий» (все типы периодов сразу).
  final GoalPeriod? period;
  final ChartGrouping grouping;
  final DateTime from;
  final DateTime to;

  @override
  bool operator ==(Object other) =>
      other is GoalChartRange &&
      other.period == period &&
      other.grouping == grouping &&
      other.from == from &&
      other.to == to;

  @override
  int get hashCode => Object.hash(period, grouping, from, to);
}

final goalStatsSummaryProvider =
    StreamProvider.family<GoalStatsSummary, GoalStatsRange>((ref, r) {
  return ref.watch(goalRepositoryProvider).watchGoalStatsSummary(
        period: r.period,
        from: r.from,
        to: r.to,
      );
});

final goalChartProvider =
    StreamProvider.family<GoalChartData, GoalChartRange>((ref, r) {
  return ref.watch(goalRepositoryProvider).watchGoalChart(
        period: r.period,
        grouping: r.grouping,
        from: r.from,
        to: r.to,
      );
});
