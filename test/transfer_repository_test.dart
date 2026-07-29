import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:enitor/data/models/goal.dart';
import 'package:enitor/data/repositories/backlog_repository.dart';
import 'package:enitor/data/repositories/goal_repository.dart';
import 'package:enitor/data/repositories/task_repository.dart';
import 'package:enitor/data/sources/local/local_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    container = ProviderContainer(
      overrides: [
        localStorageProvider.overrideWithValue(LocalStorage(prefs)),
      ],
    );
  });

  tearDown(() => container.dispose());

  group('TaskRepository.transferCandidates', () {
    test('невыполненная задача прошлого дня — кандидат на перенос', () async {
      final repo = container.read(taskRepositoryProvider);
      final now = DateTime.now();
      final yesterday = DateTime(now.year, now.month, now.day - 1);
      await repo.createAndAdd(title: 'Вчерашнее', date: yesterday);

      final candidates = repo.transferCandidates(now: now);
      expect(candidates.map((t) => t.title), contains('Вчерашнее'));
    });

    test('declineTransfer убирает задачу из кандидатов насовсем', () async {
      final repo = container.read(taskRepositoryProvider);
      final now = DateTime.now();
      final yesterday = DateTime(now.year, now.month, now.day - 1);
      final task = await repo.createAndAdd(title: 'Вчерашнее', date: yesterday);

      await repo.declineTransfer(task);
      final candidates = repo.transferCandidates(now: now);
      expect(candidates.map((t) => t.id), isNot(contains(task.id)));
    });

    test(
        'declineTransfer + ночное списание — задача уходит в бэклог, а не '
        'пропадает бесследно', () async {
      final repo = container.read(taskRepositoryProvider);
      final now = DateTime.now();
      final yesterday = DateTime(now.year, now.month, now.day - 1);
      final task =
          await repo.createAndAdd(title: 'Отклонённая', date: yesterday);

      await repo.declineTransfer(task);
      await repo.demoteStaleTransferredCopies(now: now);

      final backlog = container.read(backlogRepositoryProvider).all;
      expect(backlog.map((i) => i.title), contains('Отклонённая'));
    });

    test('transferSelected создаёт копию на сегодня и снимает кандидата',
        () async {
      final repo = container.read(taskRepositoryProvider);
      final now = DateTime.now();
      final yesterday = DateTime(now.year, now.month, now.day - 1);
      final task = await repo.createAndAdd(title: 'Вчерашнее', date: yesterday);

      await repo.transferSelected([task], now: now);

      expect(repo.transferCandidates(now: now), isEmpty);
      final today = DateTime(now.year, now.month, now.day);
      expect(
        repo.tasksForDay(today).map((t) => t.title),
        contains('Вчерашнее'),
      );
    });
  });

  group('GoalRepository.transferCandidates', () {
    test('невыполненная цель прошлого месяца — кандидат на перенос', () async {
      final repo = container.read(goalRepositoryProvider);
      final now = DateTime.now();
      final prevMonthDate = DateTime(now.year, now.month - 1, 1);
      await repo.addGoal(
        title: 'Прошлый месяц',
        period: GoalPeriod.month,
        year: prevMonthDate.year,
        month: prevMonthDate.month,
      );

      final candidates = repo.transferCandidates(now: now);
      expect(candidates.map((g) => g.title), contains('Прошлый месяц'));
    });

    test('declineTransfer убирает цель из кандидатов насовсем', () async {
      final repo = container.read(goalRepositoryProvider);
      final now = DateTime.now();
      final prevMonthDate = DateTime(now.year, now.month - 1, 1);
      final goal = await repo.addGoal(
        title: 'Прошлый месяц',
        period: GoalPeriod.month,
        year: prevMonthDate.year,
        month: prevMonthDate.month,
      );

      await repo.declineTransfer(goal);
      final candidates = repo.transferCandidates(now: now);
      expect(candidates.map((g) => g.id), isNot(contains(goal.id)));
    });

    test(
        'declineTransfer + списание по истечении периода — цель уходит в '
        'бэклог, а не пропадает бесследно', () async {
      final repo = container.read(goalRepositoryProvider);
      final now = DateTime.now();
      final prevMonthDate = DateTime(now.year, now.month - 1, 1);
      final goal = await repo.addGoal(
        title: 'Отклонённая цель',
        period: GoalPeriod.month,
        year: prevMonthDate.year,
        month: prevMonthDate.month,
      );

      await repo.declineTransfer(goal);
      await repo.demoteStaleTransferredCopies(now: now);

      final backlog = container.read(goalBacklogRepositoryProvider).all;
      expect(backlog.map((i) => i.title), contains('Отклонённая цель'));
    });

    test('transferSelected создаёт копию в текущем периоде и снимает кандидата',
        () async {
      final repo = container.read(goalRepositoryProvider);
      final now = DateTime.now();
      final prevMonthDate = DateTime(now.year, now.month - 1, 1);
      final goal = await repo.addGoal(
        title: 'Прошлый месяц',
        period: GoalPeriod.month,
        year: prevMonthDate.year,
        month: prevMonthDate.month,
      );

      await repo.transferSelected([goal], now: now);

      expect(repo.transferCandidates(now: now), isEmpty);
      final currentRef = GoalPeriodRef.current(GoalPeriod.month, now);
      final currentGoals = await repo.watchGoalsForRef(currentRef).first;
      expect(currentGoals.map((g) => g.title), contains('Прошлый месяц'));
    });
  });
}
