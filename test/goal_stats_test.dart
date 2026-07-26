import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:enitor/core/utils/date_utils.dart';
import 'package:enitor/data/models/goal.dart';
import 'package:enitor/data/repositories/goal_repository.dart';
import 'package:enitor/data/repositories/stats_repository.dart'
    show ChartGrouping;
import 'package:enitor/data/sources/local/local_storage.dart';

int _dayKey(DateTime d) =>
    DateTime(d.year, d.month, d.day).millisecondsSinceEpoch ~/ 86400000;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;
  late GoalRepository repo;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    container = ProviderContainer(
      overrides: [
        localStorageProvider.overrideWithValue(LocalStorage(prefs)),
      ],
    );
    repo = container.read(goalRepositoryProvider);
  });

  tearDown(() => container.dispose());

  // Помечает цель выполненной с ЗАДАННОЙ (в т.ч. прошлой) датой — публичный
  // toggleComplete ставит completedAt = сейчас, что не годится для истории.
  Future<void> completeAt(Goal g, DateTime at) =>
      repo.updateGoal(g.copyWith(completed: true, completedAt: at));

  GoalProductivityPoint pointOn(List<GoalProductivityPoint> pts, DateTime d) =>
      pts.firstWhere((p) => p.bucketStart == d);

  group('watchGoalStatsSummary (сводка)', () {
    test('считает выполненные/всего и среднюю долю', () async {
      final done = await repo.addGoal(
          title: 'A', period: GoalPeriod.month, year: 2025, month: 3);
      await completeAt(done, DateTime(2025, 3, 10));
      await repo.addGoal(
          title: 'B', period: GoalPeriod.month, year: 2025, month: 3);

      final summary = await repo
          .watchGoalStatsSummary(
              period: GoalPeriod.month,
              from: DateTime(2025, 3, 1),
              to: DateTime(2025, 3, 31))
          .first;

      expect(summary.totalGoals, 2);
      expect(summary.completedGoals, 1);
      expect(summary.avgCompletion, closeTo(0.5, 1e-9));
      expect(summary.periodsWithData, 1);
    });

    test('период вне диапазона не считается', () async {
      await repo.addGoal(
          title: 'A', period: GoalPeriod.month, year: 2025, month: 2);
      final summary = await repo
          .watchGoalStatsSummary(
              period: GoalPeriod.month,
              from: DateTime(2025, 3, 1),
              to: DateTime(2025, 3, 31))
          .first;
      expect(summary.totalGoals, 0);
      expect(summary.avgCompletion, isNull);
    });
  });

  group('watchGoalChart — агрегатный режим (точка ≥ период)', () {
    test('равный (месяц/monthly): точка = итог месяца', () async {
      final a = await repo.addGoal(
          title: 'A', period: GoalPeriod.month, year: 2025, month: 3);
      await completeAt(a, DateTime(2025, 3, 10)); // в срок
      await repo.addGoal(
          title: 'B', period: GoalPeriod.month, year: 2025, month: 3);
      final c = await repo.addGoal(
          title: 'C', period: GoalPeriod.month, year: 2025, month: 4);
      await completeAt(c, DateTime(2025, 4, 5));

      final chart = await repo
          .watchGoalChart(
              period: GoalPeriod.month,
              grouping: ChartGrouping.monthly,
              from: DateTime(2025, 3, 1),
              to: DateTime(2025, 4, 30))
          .first;

      expect(chart.cumulative, isFalse);
      final mar = pointOn(chart.points, DateTime(2025, 3));
      final apr = pointOn(chart.points, DateTime(2025, 4));
      expect(mar.value, closeTo(0.5, 1e-9)); // 1 из 2
      expect(mar.onTimeValue, closeTo(1.0, 1e-9)); // 1 выполнена, в срок
      expect(apr.value, closeTo(1.0, 1e-9));
    });

    test('крупнее (неделя/monthly): точка-месяц = среднее итогов недель',
        () async {
      // Две недельные цели в марте 2025: одна выполнена, вторая нет.
      final w1 = await repo.addGoal(
          title: 'w1',
          period: GoalPeriod.week,
          year: 2025,
          weekStart: DateTime(2025, 3, 3));
      await completeAt(w1, DateTime(2025, 3, 5));
      await repo.addGoal(
          title: 'w2',
          period: GoalPeriod.week,
          year: 2025,
          weekStart: DateTime(2025, 3, 10));

      final chart = await repo
          .watchGoalChart(
              period: GoalPeriod.week,
              grouping: ChartGrouping.monthly,
              from: DateTime(2025, 3, 1),
              to: DateTime(2025, 3, 31))
          .first;

      expect(chart.cumulative, isFalse);
      final mar = pointOn(chart.points, DateTime(2025, 3));
      expect(mar.value, closeTo(0.5, 1e-9)); // (1.0 + 0.0) / 2
      expect(mar.totalGoals, 2);
    });

    test('период относится к бакету по КОНЦУ (неделя мар→апр → апрель)',
        () async {
      // Неделя стартует 31 марта, заканчивается 6 апреля.
      final w = await repo.addGoal(
          title: 'w',
          period: GoalPeriod.week,
          year: 2025,
          weekStart: DateTime(2025, 3, 31));
      await completeAt(w, DateTime(2025, 4, 2));

      final chart = await repo
          .watchGoalChart(
              period: GoalPeriod.week,
              grouping: ChartGrouping.monthly,
              from: DateTime(2025, 3, 1),
              to: DateTime(2025, 4, 30))
          .first;

      // Завершилась в апреле → попала в апрель, а не в март.
      expect(pointOn(chart.points, DateTime(2025, 3)).value, isNull);
      expect(
          pointOn(chart.points, DateTime(2025, 4)).value, closeTo(1.0, 1e-9));
    });

    test('пустой бакет → value == null', () async {
      await repo.addGoal(
          title: 'A', period: GoalPeriod.month, year: 2025, month: 3);
      final chart = await repo
          .watchGoalChart(
              period: GoalPeriod.month,
              grouping: ChartGrouping.monthly,
              from: DateTime(2025, 3, 1),
              to: DateTime(2025, 5, 31))
          .first;
      // Апрель и май — без целей.
      expect(pointOn(chart.points, DateTime(2025, 4)).value, isNull);
      expect(pointOn(chart.points, DateTime(2025, 5)).value, isNull);
    });
  });

  group('watchGoalChart — накопительный режим (точка мельче периода)', () {
    test('нарастающий итог внутри месяца по датам завершения', () async {
      final g1 = await repo.addGoal(
          title: 'g1', period: GoalPeriod.month, year: 2025, month: 3);
      await completeAt(g1, DateTime(2025, 3, 10));
      final g2 = await repo.addGoal(
          title: 'g2', period: GoalPeriod.month, year: 2025, month: 3);
      await completeAt(g2, DateTime(2025, 3, 20));

      final chart = await repo
          .watchGoalChart(
              period: GoalPeriod.month,
              grouping: ChartGrouping.daily,
              from: DateTime(2025, 3, 1),
              to: DateTime(2025, 3, 31))
          .first;

      expect(chart.cumulative, isTrue);
      expect(
          pointOn(chart.points, DateTime(2025, 3, 5)).value, closeTo(0, 1e-9));
      expect(pointOn(chart.points, DateTime(2025, 3, 15)).value,
          closeTo(0.5, 1e-9));
      expect(pointOn(chart.points, DateTime(2025, 3, 25)).value,
          closeTo(1.0, 1e-9));
      // periodStart у всех точек марта = 1 марта.
      expect(pointOn(chart.points, DateTime(2025, 3, 15)).periodStart,
          DateTime(2025, 3));
    });

    test('сброс и periodStart меняются на границе месяца', () async {
      final g1 = await repo.addGoal(
          title: 'g1', period: GoalPeriod.month, year: 2025, month: 3);
      await completeAt(g1, DateTime(2025, 3, 10));
      final g2 = await repo.addGoal(
          title: 'g2', period: GoalPeriod.month, year: 2025, month: 4);
      await completeAt(g2, DateTime(2025, 4, 20));

      final chart = await repo
          .watchGoalChart(
              period: GoalPeriod.month,
              grouping: ChartGrouping.daily,
              from: DateTime(2025, 3, 1),
              to: DateTime(2025, 4, 30))
          .first;

      final mar31 = pointOn(chart.points, DateTime(2025, 3, 31));
      final apr1 = pointOn(chart.points, DateTime(2025, 4, 1));
      expect(mar31.periodStart, DateTime(2025, 3));
      expect(apr1.periodStart, DateTime(2025, 4)); // граница — сброс
      expect(mar31.value, closeTo(1.0, 1e-9)); // итог марта
      expect(apr1.value, closeTo(0.0, 1e-9)); // апрель начался с 0
    });

    test('прошлый период без снимков: незавершённый счётчик → 0 (фоллбэк)',
        () async {
      // Счётчик 2/4 в марте 2025, НЕ завершён. Прогресс выставлен «сейчас»
      // (2026) → снимков за март нет → фоллбэк по completedAt: не завершён →
      // кольцо на все дни марта = 0 (истории частичного прогресса нет).
      final g = await repo.addGoal(
          title: 'books',
          period: GoalPeriod.month,
          year: 2025,
          month: 3,
          targetCount: 4);
      await repo.setGoalProgress(g, 2);

      final chart = await repo
          .watchGoalChart(
              period: GoalPeriod.month,
              grouping: ChartGrouping.daily,
              from: DateTime(2025, 3, 1),
              to: DateTime(2025, 3, 31))
          .first;

      expect(
          pointOn(chart.points, DateTime(2025, 3, 15)).value, closeTo(0, 1e-9));
      expect(
          pointOn(chart.points, DateTime(2025, 3, 31)).value, closeTo(0, 1e-9));
    });

    test(
        'есть точка выполнения → есть и точка своевр-ти (0, если ничего не '
        'достигнуто)', () async {
      // Счётчик 2/4 в текущем месяце: значение > 0, но НИ одна цель не
      // завершена полностью → своевременность должна быть 0.0, а не null.
      final now = DateTime.now();
      final g = await repo.addGoal(
          title: 'books',
          period: GoalPeriod.month,
          year: now.year,
          month: now.month,
          targetCount: 4);
      await repo.setGoalProgress(g, 2);

      final chart = await repo
          .watchGoalChart(
              period: GoalPeriod.month,
              grouping: ChartGrouping.daily,
              from: startOfMonth(now),
              to: now)
          .first;

      final p = pointOn(chart.points, dateOnly(now));
      expect(p.value, closeTo(0.5, 1e-9)); // точка выполнения есть
      expect(p.onTimeValue, closeTo(0.0, 1e-9)); // и своевр-ти есть, = 0
      // Инвариант по всему графику: value != null ⇔ onTimeValue != null.
      for (final pt in chart.points) {
        expect(pt.value == null, pt.onTimeValue == null);
      }
    });

    test('последняя точка периода помечена isPeriodEnd', () async {
      final g = await repo.addGoal(
          title: 'g', period: GoalPeriod.month, year: 2025, month: 3);
      await completeAt(g, DateTime(2025, 3, 10));
      final chart = await repo
          .watchGoalChart(
              period: GoalPeriod.month,
              grouping: ChartGrouping.daily,
              from: DateTime(2025, 3, 1),
              to: DateTime(2025, 3, 31))
          .first;
      expect(pointOn(chart.points, DateTime(2025, 3, 31)).isPeriodEnd, isTrue);
      expect(pointOn(chart.points, DateTime(2025, 3, 15)).isPeriodEnd, isFalse);
    });
  });

  group('watchGoalChart — снимки кольца по дням (чтение истории)', () {
    test('нарастающая линия использует backdated-снимки кольца', () async {
      // Засеваем хранилище задним числом: счётчик 2/4 в марте 2025 (не
      // завершён) + снимки кольца: 0.25 с 10 марта, 0.5 с 20 марта.
      final createdAt = DateTime(2025, 3, 1);
      final goal = Goal(
        id: 'g1',
        period: GoalPeriod.month,
        year: 2025,
        month: 3,
        title: 'books',
        targetCount: 4,
        manualProgress: 2,
        createdAt: createdAt,
        updatedAt: createdAt,
      );
      SharedPreferences.setMockInitialValues({
        'goals': jsonEncode([goal.toJson()]),
        'goal_ring_snapshots': jsonEncode({
          'g1': {
            '${_dayKey(DateTime(2025, 3, 10))}': 0.25,
            '${_dayKey(DateTime(2025, 3, 20))}': 0.5,
          }
        }),
      });
      final prefs = await SharedPreferences.getInstance();
      final c = ProviderContainer(overrides: [
        localStorageProvider.overrideWithValue(LocalStorage(prefs)),
      ]);
      addTearDown(c.dispose);
      final r = c.read(goalRepositoryProvider);

      final chart = await r
          .watchGoalChart(
              period: GoalPeriod.month,
              grouping: ChartGrouping.daily,
              from: DateTime(2025, 3, 1),
              to: DateTime(2025, 3, 31))
          .first;

      // До первого снимка — 0; затем ступени кольца 0.25 → 0.5.
      expect(
          pointOn(chart.points, DateTime(2025, 3, 5)).value, closeTo(0, 1e-9));
      expect(pointOn(chart.points, DateTime(2025, 3, 15)).value,
          closeTo(0.25, 1e-9));
      expect(pointOn(chart.points, DateTime(2025, 3, 25)).value,
          closeTo(0.5, 1e-9));
      expect(pointOn(chart.points, DateTime(2025, 3, 31)).value,
          closeTo(0.5, 1e-9));
    });
  });

  group('watchGoalChart — сезон «Зима» (переход через Новый год)', () {
    test('накопительно по месяцам зимы 2025 (дек 2025 – фев 2026)', () async {
      // Зима 2025 = декабрь 2025 + январь/февраль 2026.
      final g = await repo.addGoal(
          title: 'winter', period: GoalPeriod.season, year: 2025, season: 0);
      await completeAt(g, DateTime(2026, 1, 15));

      final chart = await repo
          .watchGoalChart(
              period: GoalPeriod.season,
              grouping: ChartGrouping.monthly,
              from: DateTime(2025, 12, 1),
              to: DateTime(2026, 2, 28))
          .first;

      expect(chart.cumulative, isTrue);
      expect(pointOn(chart.points, DateTime(2025, 12)).value, closeTo(0, 1e-9));
      expect(
          pointOn(chart.points, DateTime(2026, 1)).value, closeTo(1.0, 1e-9));
      expect(
          pointOn(chart.points, DateTime(2026, 2)).value, closeTo(1.0, 1e-9));
      // Все месяцы принадлежат одному сезону → единый periodStart, без сброса.
      expect(pointOn(chart.points, DateTime(2026, 1)).periodStart,
          DateTime(2025, 12));
      expect(pointOn(chart.points, DateTime(2026, 2)).periodStart,
          DateTime(2025, 12));
    });
  });

  group('watchGoalChart — текущий (незавершённый) период', () {
    test('итог берётся «на сейчас», включая частичный прогресс', () async {
      final now = DateTime.now();
      final g = await repo.addGoal(
          title: 'books',
          period: GoalPeriod.month,
          year: now.year,
          month: now.month,
          targetCount: 4);
      await repo.setGoalProgress(g, 3); // 3/4 сейчас

      final chart = await repo
          .watchGoalChart(
              period: GoalPeriod.month,
              grouping: ChartGrouping.monthly,
              from: startOfMonth(now),
              to: now)
          .first;

      final cur = pointOn(chart.points, startOfMonth(now));
      expect(cur.value, closeTo(0.75, 1e-9)); // дробный итог на сейчас
    });
  });

  group('watchGoalChart — режим «Общий» (среднее колец всех типов)', () {
    test('тип без целей не учитывается: значение = кольцо единственного типа',
        () async {
      final now = DateTime.now();
      final m = await repo.addGoal(
          title: 'month',
          period: GoalPeriod.month,
          year: now.year,
          month: now.month);
      await completeAt(m, now); // месяц выполнен на 100%

      final chart = await repo
          .watchGoalChart(
              period: null, // «Общий»
              grouping: ChartGrouping.daily,
              from: startOfMonth(now),
              to: now)
          .first;

      expect(chart.overall, isTrue);
      // Есть цели только у месяца → среднее = кольцо месяца (неделя/сезон/год
      // без целей исключены), а не делится на 4.
      final p = pointOn(chart.points, dateOnly(now));
      expect(p.value, closeTo(1.0, 1e-9));
      expect(p.onTimeValue, closeTo(1.0, 1e-9));
    });

    test('среднее двух типов поровну; тип с целями, но без достижений = 0',
        () async {
      final now = DateTime.now();
      final m = await repo.addGoal(
          title: 'month',
          period: GoalPeriod.month,
          year: now.year,
          month: now.month);
      await completeAt(m, now); // 100%
      await repo.addGoal(
          title: 'year',
          period: GoalPeriod.year,
          year: now.year); // есть, не достигнута

      final chart = await repo
          .watchGoalChart(
              period: null,
              grouping: ChartGrouping.daily,
              from: startOfMonth(now),
              to: now)
          .first;

      final p = pointOn(chart.points, dateOnly(now));
      // (месяц 100% + год 0%) / 2 = 50%.
      expect(p.value, closeTo(0.5, 1e-9));
      // Своевременность спарена: месяц 100% (в срок), год 0% (нет достижений).
      expect(p.onTimeValue, closeTo(0.5, 1e-9));
    });

    test(
        'границы типов: при точке=День видны концы месяца (свой тип в boundaries)',
        () async {
      // Границы не зависят от наличия целей — проверяем на прошлом диапазоне.
      final chart = await repo
          .watchGoalChart(
              period: null,
              grouping: ChartGrouping.daily,
              from: DateTime(2025, 3, 20),
              to: DateTime(2025, 4, 5))
          .first;

      expect(chart.overall, isTrue);
      // 1 апреля начинается новый месяц → в boundaries его точки есть month.
      expect(pointOn(chart.points, DateTime(2025, 4, 1)).boundaries,
          contains(GoalPeriod.month));
      // У первой точки границ нет (нет предыдущего бакета).
      expect(chart.points.first.boundaries, isEmpty);
    });

    test('границы мельче точки не рисуются (точка=Месяц → без границ недель)',
        () async {
      final chart = await repo
          .watchGoalChart(
              period: null,
              grouping: ChartGrouping.monthly,
              from: DateTime(2025, 1, 1),
              to: DateTime(2025, 6, 30))
          .first;

      // Неделя и месяц мельче/равны месячной точке → их границы не рисуем.
      for (final p in chart.points) {
        expect(p.boundaries, isNot(contains(GoalPeriod.week)));
        expect(p.boundaries, isNot(contains(GoalPeriod.month)));
      }
    });

    test('сводка «Общий» = среднее средних по типам; лучший период — НЕДЕЛЯ',
        () async {
      // Месяц: март 100%, апрель 0% → среднее по типу «месяц» = 0.5.
      final mMar = await repo.addGoal(
          title: 'mMar', period: GoalPeriod.month, year: 2025, month: 3);
      await completeAt(mMar, DateTime(2025, 3, 10));
      await repo.addGoal(
          title: 'mApr', period: GoalPeriod.month, year: 2025, month: 4);
      // Год: 2025 — две цели, обе 100% → среднее по типу «год» = 1.0.
      final y1 =
          await repo.addGoal(title: 'y1', period: GoalPeriod.year, year: 2025);
      await completeAt(y1, DateTime(2025, 2, 1));
      final y2 =
          await repo.addGoal(title: 'y2', period: GoalPeriod.year, year: 2025);
      await completeAt(y2, DateTime(2025, 2, 2));

      final summary = await repo
          .watchGoalStatsSummary(
              period: null,
              from: DateTime(2025, 1, 1),
              to: DateTime(2025, 12, 31))
          .first;

      // (0.5 по месяцам + 1.0 по годам) / 2 типа = 0.75.
      expect(summary.avgCompletion, closeTo(0.75, 1e-9));
      expect(summary.totalGoals, 4);
      expect(summary.completedGoals, 3);
      // Лучший период в «Общем» — всегда КАЛЕНДАРНАЯ НЕДЕЛЯ.
      expect(summary.bestPeriod?.period, GoalPeriod.week);
    });

    test('«Общий»: лучшая неделя учитывает ВСЕ типы (не только недельные)',
        () async {
      // Недельная цель в неделе 3–9 марта, выполнена в срок → в ту неделю
      // недельное кольцо 1.0, месячное ещё 0.
      final w = await repo.addGoal(
          title: 'w',
          period: GoalPeriod.week,
          year: 2025,
          weekStart: DateTime(2025, 3, 3));
      await completeAt(w, DateTime(2025, 3, 5));
      // Месячная цель марта, выполнена 20 марта → с недели 24–30 марта месячное
      // кольцо = 1.0, и это единственный активный тип → бленд 1.0 > 0.5 у недели
      // 3–9 (там (нед 1.0 + мес 0)/2). Значит лучшая неделя — 24–30 марта,
      // хотя недельной цели там нет: считаются ВСЕ цели.
      final m = await repo.addGoal(
          title: 'm', period: GoalPeriod.month, year: 2025, month: 3);
      await completeAt(m, DateTime(2025, 3, 20));

      final summary = await repo
          .watchGoalStatsSummary(
              period: null,
              from: DateTime(2025, 3, 1),
              to: DateTime(2025, 3, 31))
          .first;

      expect(summary.bestPeriod?.period, GoalPeriod.week);
      expect(summary.bestPeriod?.start, DateTime(2025, 3, 24));
      expect(summary.bestCompletion, closeTo(1.0, 1e-9));
    });

    test('лучший период (тип): «всё поздно» > «ничего не финишировал»',
        () async {
      // Март: 1 цель выполнена ПОЗДНО (completedAt после конца месяца) →
      // rate 1.0, своевременность 0.
      final late = await repo.addGoal(
          title: 'late', period: GoalPeriod.month, year: 2025, month: 3);
      await completeAt(
          late, DateTime(2025, 4, 2)); // после 31 марта → не в срок
      // Апрель: счётчик 9/10, НЕ завершён → rate 0.9, ни одной цели не закрыто.
      final partial = await repo.addGoal(
          title: 'partial',
          period: GoalPeriod.month,
          year: 2025,
          month: 4,
          targetCount: 10);
      await repo.setGoalProgress(partial, 9);

      final summary = await repo
          .watchGoalStatsSummary(
              period:
                  GoalPeriod.month, // одиночный тип: проверяем формулу скора
              from: DateTime(2025, 1, 1),
              to: DateTime(2025, 12, 31))
          .first;

      // При старом дефолте (своевр-ть 1.0 у «ничего не финишировано») победил бы
      // апрель (0.9·1.0 > 1.0·0.7). Теперь оба множителя ×0.7, решает выполнение
      // → март (1.0) > апрель (0.9).
      expect(summary.bestPeriod?.month, 3);
      expect(summary.bestCompletion, closeTo(1.0, 1e-9));
      // Своевременность у выбранного марта = 0 (выполнено, но поздно).
      expect(summary.bestOnTimeRate, closeTo(0.0, 1e-9));
    });
  });
}
