import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:enitor/data/models/goal.dart';
import 'package:enitor/data/repositories/goal_repository.dart';
import 'package:enitor/data/repositories/task_repository.dart';
import 'package:enitor/data/sources/local/local_storage.dart';

/// Цели во времени (вклад задач — минуты) и подцели (прогресс месяца идёт в год).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer c;
  late GoalRepository goals;
  late TaskRepository tasks;
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final monthRef = GoalPeriodRef.current(GoalPeriod.month, now);
  final yearRef = GoalPeriodRef.current(GoalPeriod.year, now);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    c = ProviderContainer(overrides: [
      localStorageProvider.overrideWithValue(LocalStorage(prefs)),
    ]);
    goals = c.read(goalRepositoryProvider);
    tasks = c.read(taskRepositoryProvider);
  });

  tearDown(() => c.dispose());

  Future<Goal> add(GoalPeriodRef r, String title, int target,
          {GoalUnit unit = GoalUnit.count, String? parentId}) =>
      goals.addGoal(
        title: title,
        period: r.period,
        year: r.year,
        month: r.month,
        season: r.season,
        weekStart: r.weekStart,
        targetCount: target,
        unit: unit,
        parentId: parentId,
      );

  Goal g(String id) => goals.goalById(id)!;

  test('цель в часах копит минуты фокуса привязанных задач', () async {
    final eng = await add(monthRef, 'Английский', 120, unit: GoalUnit.minutes);
    final t =
        await tasks.createAndAdd(title: 'Учебник', date: today, goalId: eng.id);

    await tasks.addActualMinutes(t.id, 25);
    expect(g(eng.id).progressCount, 25);
    await tasks.addActualMinutes(t.id, 25);
    expect(g(eng.id).progressCount, 50);
    expect(g(eng.id).completed, isFalse);

    // Без фокуса выполненная задача отдаёт оценку.
    final t2 = await tasks.createAndAdd(
        title: 'Сериал', date: today, goalId: eng.id, estimatedMinutes: 70);
    expect(g(eng.id).progressCount, 50, reason: 'не выполнена — не считается');
    await tasks.toggleCompleted(t2);
    expect(g(eng.id).progressCount, 120);
    expect(g(eng.id).completed, isTrue);
  });

  test('цель в разах по-прежнему считает выполненные задачи', () async {
    final books = await add(monthRef, 'Книги', 3);
    final t = await tasks.createAndAdd(
        title: 'Дочитать', date: today, goalId: books.id);
    await tasks.addActualMinutes(t.id, 40);
    expect(g(books.id).progressCount, 0);
    await tasks.toggleCompleted(t);
    expect(g(books.id).progressCount, 1);
  });

  test('подцель-счётчик отдаёт родителю свой прогресс, простая — 1', () async {
    final year = await add(yearRef, '24 книги', 24);
    final month = await add(monthRef, '2 книги', 2, parentId: year.id);
    await goals.incrementGoalCounter(g(month.id), 1);
    expect(g(year.id).progressCount, 1);
    await goals.incrementGoalCounter(g(month.id), 1);
    expect(g(year.id).progressCount, 2);

    final simple = await goals.addGoal(
      title: 'Война и мир',
      period: GoalPeriod.month,
      year: monthRef.year,
      month: monthRef.month,
      parentId: year.id,
    );
    expect(g(year.id).progressCount, 2);
    await goals.toggleComplete(g(simple.id));
    expect(g(year.id).progressCount, 3);

    // Ручная часть года не путается с вкладом подцелей.
    await goals.setGoalProgress(g(year.id), 5);
    expect(g(year.id).manualProgress, 2);
    expect(g(year.id).progressCount, 5);

    await goals.deleteGoal(simple.id);
    expect(g(year.id).progressCount, 4);
  });

  test('часы идут по цепочке задача → месяц → год', () async {
    final year =
        await add(yearRef, '200 ч английского', 12000, unit: GoalUnit.minutes);
    final month = await add(monthRef, '20 ч', 1200,
        unit: GoalUnit.minutes, parentId: year.id);
    final t =
        await tasks.createAndAdd(title: 'Урок', date: today, goalId: month.id);
    await tasks.addActualMinutes(t.id, 90);
    expect(g(month.id).progressCount, 90);
    expect(g(year.id).progressCount, 90);
  });

  test('цепочка неделя → месяц → сезон → год', () async {
    // Середина мая: неделя, месяц и весна лежат внутри одного года.
    final d = DateTime(2026, 5, 13);
    GoalPeriodRef r(GoalPeriod p) => GoalPeriodRef.current(p, d);

    // В разах.
    final y = await add(r(GoalPeriod.year), 'Год', 100);
    final s = await add(r(GoalPeriod.season), 'Весна', 30, parentId: y.id);
    final m = await add(r(GoalPeriod.month), 'Май', 10, parentId: s.id);
    final w = await add(r(GoalPeriod.week), 'Неделя', 3, parentId: m.id);
    expect(
        goals
            .parentCandidatesFor(r(GoalPeriod.week), childIsTime: false)
            .map((x) => x.id),
        unorderedEquals([y.id, s.id, m.id]));
    await goals.incrementGoalCounter(g(w.id), 2);
    for (final id in [w.id, m.id, s.id, y.id]) {
      expect(g(id).progressCount, 2, reason: id);
    }

    // В часах, от задачи до года.
    final yh =
        await add(r(GoalPeriod.year), 'Год, ч', 60000, unit: GoalUnit.minutes);
    final sh = await add(r(GoalPeriod.season), 'Весна, ч', 15000,
        unit: GoalUnit.minutes, parentId: yh.id);
    final mh = await add(r(GoalPeriod.month), 'Май, ч', 1200,
        unit: GoalUnit.minutes, parentId: sh.id);
    final wh = await add(r(GoalPeriod.week), 'Неделя, ч', 300,
        unit: GoalUnit.minutes, parentId: mh.id);
    final t =
        await tasks.createAndAdd(title: 'Книга', date: today, goalId: wh.id);
    await tasks.addActualMinutes(t.id, 45);
    for (final id in [wh.id, mh.id, sh.id, yh.id]) {
      expect(g(id).progressCount, 45, reason: id);
    }
  });

  test('родителем может быть только счётчик более длинного периода', () async {
    final yearCount = await add(yearRef, 'Год, разы', 10);
    final yearTime =
        await add(yearRef, 'Год, часы', 600, unit: GoalUnit.minutes);
    await add(monthRef, 'Месяц', 5);

    final forCount = goals
        .parentCandidatesFor(monthRef, childIsTime: false)
        .map((x) => x.id);
    expect(forCount, [yearCount.id], reason: 'часы не копят «разы»');
    final forTime =
        goals.parentCandidatesFor(monthRef, childIsTime: true).map((x) => x.id);
    expect(forTime, unorderedEquals([yearCount.id, yearTime.id]));
    expect(goals.parentCandidatesFor(yearRef, childIsTime: false), isEmpty);
  });

  test('перенесённый оригинал не считается дважды', () async {
    final year = await add(yearRef, 'Год', 10);
    final month = await add(monthRef, 'Месяц', 4, parentId: year.id);
    await goals.setGoalProgress(g(month.id), 3);
    expect(g(year.id).progressCount, 3);

    await goals.transferGoal(g(month.id), targetRef: monthRef.next);
    final all = await goals.watchAllGoals().first;
    final moved = all.firstWhere((x) => x.transferredFromId == month.id);
    // В декабре следующий месяц уже в другом году — родитель не годится.
    final keepsParent = !monthRef.next.start.isAfter(yearRef.endInclusive);
    expect(moved.parentId, keepsParent ? year.id : isNull);
    expect(g(year.id).progressCount, keepsParent ? 3 : 0);
  });

  test('перенос и копия задачи сохраняют цель внутри её периода', () async {
    final m = await add(monthRef, 'Книги', 5);
    final t =
        await tasks.createAndAdd(title: 'Читать', date: today, goalId: m.id);
    final inMonth = monthRef.endInclusive;
    final nextMonth = monthRef.next.start;

    await tasks.transferTask(t, targetDate: inMonth);
    await tasks.copyTasksTo(tasks: [t], targetDate: inMonth);
    await tasks.transferTask(t, targetDate: nextMonth);
    await tasks.copyTasksTo(tasks: [t], targetDate: nextMonth);

    final all = tasks.allTasks;
    String? goalOn(DateTime d) => all
        .where((x) => x.id != t.id && x.date == d)
        .map((x) => x.goalId)
        .toSet()
        .single;
    expect(goalOn(inMonth), m.id);
    expect(goalOn(nextMonth), isNull, reason: 'цель месяца там не идёт');
  });

  test('единица и родитель переживают JSON', () {
    final x = Goal(
      id: 'a',
      period: GoalPeriod.month,
      year: 2026,
      month: 11,
      title: 't',
      createdAt: now,
      updatedAt: now,
      targetCount: 600,
      unit: GoalUnit.minutes,
      parentId: 'p',
      childProgress: 30,
    );
    final y = Goal.fromJson(x.toJson());
    expect(y.isTime, isTrue);
    expect(y.parentId, 'p');
    expect(y.progressCount, 30);
    // Старые записи без полей — разы и без родителя.
    final old = Goal.fromJson(x.toJson()
      ..remove('unit')
      ..remove('parentId')
      ..remove('childProgress'));
    expect(old.unit, GoalUnit.count);
    expect(old.parentId, isNull);
  });
}
