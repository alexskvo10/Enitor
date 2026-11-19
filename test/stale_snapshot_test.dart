import 'package:enitor/data/models/backlog_item.dart';
import 'package:enitor/data/models/goal.dart';
import 'package:enitor/data/models/recurrence_rule.dart';
import 'package:enitor/data/models/task.dart';
import 'package:enitor/data/repositories/goal_repository.dart';
import 'package:enitor/data/repositories/schedule_repository.dart';
import 'package:enitor/data/repositories/task_repository.dart';
import 'package:enitor/data/sources/local/local_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Правки из старых снимков и связи, которые терялись по дороге.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer c;
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final weekRef = GoalPeriodRef.current(GoalPeriod.week, now);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    c = ProviderContainer(
      overrides: [
        localStorageProvider.overrideWithValue(LocalStorage(prefs)),
      ],
    );
  });

  tearDown(() => c.dispose());

  Future<Goal> counterGoal() => c.read(goalRepositoryProvider).addGoal(
        title: 'Бег',
        period: weekRef.period,
        year: weekRef.year,
        weekStart: weekRef.weekStart,
        targetCount: 5,
      );

  test('два дня серии удалены из одного снимка — оба остаются исключениями',
      () async {
    final repo = c.read(scheduleRepositoryProvider);
    final item = await repo.create(
      title: 'Йога',
      date: today,
      startMinutes: 9 * 60,
      repeat: RecurrenceKind.interval,
    );
    await repo.deleteOccurrence(item, today.add(const Duration(days: 1)));
    await repo.deleteOccurrence(item, today.add(const Duration(days: 2)));
    // Форма открыта до удалений — её сохранение их не возвращает.
    await repo.update(item.copyWith(title: 'Йога утром'));

    final saved = repo.byId(item.id)!;
    expect(saved.title, 'Йога утром');
    expect(saved.exceptDates, hasLength(2));
  });

  test('удалённая цель отвязывается от задач и подцелей', () async {
    final goals = c.read(goalRepositoryProvider);
    final tasks = c.read(taskRepositoryProvider);
    final g = await counterGoal();
    final t = await tasks.createAndAdd(
      title: 'Пробежка',
      date: today,
      targetCount: 2,
      goalId: g.id,
    );
    final day = await goals.addGoal(
      title: 'Пробежка сегодня',
      period: weekRef.period,
      year: weekRef.year,
      weekStart: weekRef.weekStart,
      targetCount: 2,
      parentId: g.id,
    );

    await goals.deleteGoal(g.id);
    await tasks.unlinkGoal(g.id);

    expect(tasks.taskById(t.id)!.goalId, isNull);
    expect(goals.goalById(day.id)!.parentId, isNull);
  });

  test('бэклог хранит цель, теги, приоритет и набранный счётчик', () {
    final task = BacklogItem.fromJson(
      BacklogItem(
        id: 'b1',
        title: 'Отжимания',
        originalDate: today,
        addedAt: now,
        targetCount: 10,
        progressCount: 4,
        goalId: 'g1',
      ).toJson(),
    );
    expect(task.goalId, 'g1');
    expect(task.progressCount, 4);

    final goal = GoalBacklogItem.fromJson(
      GoalBacklogItem(
        id: 'gb1',
        title: 'Книга',
        period: GoalPeriod.week,
        originalRef: weekRef,
        addedAt: now,
        priority: TaskPriority.high,
        tags: const ['чтение'],
      ).toJson(),
    );
    expect(goal.priority, TaskPriority.high);
    expect(goal.tags, ['чтение']);
  });

  test('задача из бэклога возвращается с набранным счётчиком', () async {
    final tasks = c.read(taskRepositoryProvider);
    final t = await tasks.createAndAdd(
      title: 'Отжимания',
      date: today,
      targetCount: 10,
      progressCount: 4,
    );
    expect(tasks.taskById(t.id)!.progressCount, 4);
    expect(tasks.taskById(t.id)!.isCompleted, isFalse);
  });

  test('достижение цели через свёртку родителя — одно событие', () async {
    final goals = c.read(goalRepositoryProvider);
    final parent = await counterGoal();
    final child = await goals.addGoal(
      title: 'Часть',
      period: weekRef.period,
      year: weekRef.year,
      weekStart: weekRef.weekStart,
      targetCount: 5,
      parentId: parent.id,
    );
    final events = <String>[];
    final sub = goals.achievedEvents.listen((g) => events.add(g.id));
    addTearDown(sub.cancel);

    await goals.setGoalProgress(goals.goalById(parent.id)!, 3);
    await goals.setGoalProgress(goals.goalById(child.id)!, 5);
    await Future<void>.delayed(Duration.zero);

    expect(events.where((id) => id == parent.id), hasLength(1));
  });
}
