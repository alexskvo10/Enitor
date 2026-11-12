import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:enitor/data/models/recurrence_rule.dart';
import 'package:enitor/data/models/task.dart';
import 'package:enitor/data/repositories/recurrence_repository.dart';
import 'package:enitor/data/repositories/stats_repository.dart';
import 'package:enitor/data/repositories/task_repository.dart';
import 'package:enitor/data/sources/local/local_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// То, что синхронизация требует от репозиториев: предсказуемые id у всего,
// что Enitor создаёт сам, склейка старых дублей повторов, перечитывание.

final _day = DateTime(2026, 10, 28);
final _t0 = DateTime(2026, 10, 27, 9);

void main() {
  late ProviderContainer container;
  late LocalStorage storage;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    storage = LocalStorage(await SharedPreferences.getInstance());
    container = ProviderContainer(
      overrides: [localStorageProvider.overrideWithValue(storage)],
    );
  });
  tearDown(() => container.dispose());

  TaskRepository tasks() => container.read(taskRepositoryProvider);

  Future<void> addRule() => container.read(recurrenceRepositoryProvider).add(
        RecurrenceRule(
          id: 'rule1',
          taskTitle: 'Зарядка',
          kind: RecurrenceKind.interval,
          startDate: _day,
          subtaskTitles: const ['Разминка', 'Отжимания'],
          createdAt: _t0,
          updatedAt: _t0,
        ),
      );

  test('экземпляр повтора получает id «правило + дата», подзадачи тоже',
      () async {
    await addRule();
    await tasks().ensureRecurrencesForDay(_day);
    final t = tasks().tasksForDay(_day).single;
    expect(t.id, 'r-rule1-20261028');
    expect(t.subtasks.map((s) => s.id),
        ['r-rule1-20261028-s0', 'r-rule1-20261028-s1'],);
  });

  test('склейка дублей оставляет выполненный экземпляр и пересчитывает день',
      () async {
    await addRule();
    Task dup(String id, {DateTime? done, DateTime? updated}) => Task(
          id: id,
          title: 'Зарядка',
          date: _day,
          recurrenceRuleId: 'rule1',
          createdAt: _t0,
          updatedAt: updated ?? _t0,
          completedAt: done,
        );
    await storage.writeList('tasks', [
      dup('random-a', updated: _t0.add(const Duration(hours: 1))).toJson(),
      dup('random-b', done: _t0).toJson(),
      dup('r-rule1-20261028').toJson(),
    ]);
    tasks().reload();
    expect(await tasks().dedupeRecurrences(), isTrue);
    final left = tasks().tasksForDay(_day).single;
    expect(left.id, 'random-b');
    final stats =
        await container.read(statsRepositoryProvider).watchDay(_day).first;
    expect(stats!.totalTasks, 1);
    expect(stats.completedTasks, 1);
    expect(await tasks().dedupeRecurrences(), isFalse);
  });

  test('выбор при склейке не зависит от порядка записей', () async {
    Map<String, dynamic> dup(String id) => Task(
          id: id,
          title: 'x',
          date: _day,
          recurrenceRuleId: 'rule1',
          createdAt: _t0,
          updatedAt: _t0,
        ).toJson();
    for (final order in [
      ['b', 'a', 'r-rule1-20261028'],
      ['r-rule1-20261028', 'a', 'b'],
    ]) {
      await storage.writeList('tasks', [for (final id in order) dup(id)]);
      tasks().reload();
      await tasks().dedupeRecurrences();
      expect(tasks().allTasks.single.id, 'r-rule1-20261028');
    }
  });

  test('копия переноса и пункт бэклога — с id от исходной задачи', () async {
    final t = await tasks().createAndAdd(title: 'Отчёт', date: _day);
    await tasks()
        .transferTask(t, targetDate: _day.add(const Duration(days: 1)));
    final copy = tasks().allTasks.firstWhere((x) => x.transferredFromId == t.id);
    // От id исходной задачи, не случайный: два устройства дадут один.
    expect(
      copy.id,
      't-${sha1.convert(utf8.encode(t.id)).toString().substring(0, 20)}',
    );
  });

  test('id копии не растёт от переноса к переносу', () async {
    var t = await tasks().createAndAdd(title: 'Каждую ночь', date: _day);
    for (var i = 1; i <= 40; i++) {
      await tasks().transferTask(t, targetDate: _day.add(Duration(days: i)));
      t = tasks().allTasks.firstWhere((x) => x.transferredFromId == t.id);
    }
    expect(t.id.length, lessThanOrEqualTo(22));
  });

  test('reload подхватывает записанное в хранилище мимо репозитория', () async {
    final next = tasks().watchAllTasks().skip(1).first;
    // Поток подписывается на изменения после первого значения.
    await pumpEventQueue();
    await storage.writeList('tasks', [
      Task(
              id: 'x',
              title: 'С сервера',
              date: _day,
              createdAt: _t0,
              updatedAt: _t0,)
          .toJson(),
    ]);
    tasks().reload();
    expect((await next).single.id, 'x');
  });
}
