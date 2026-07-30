import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:enitor/core/utils/date_utils.dart';
import 'package:enitor/data/models/recurrence_rule.dart';
import 'package:enitor/data/repositories/recurrence_repository.dart';
import 'package:enitor/data/repositories/task_repository.dart';
import 'package:enitor/data/sources/local/local_storage.dart';

// Общие напоминания «не забудь про задачи» включены по умолчанию только
// потому, что не шлются вхолостую: расписание строится по этой карте, и день
// без невыполненного в неё не попадает вовсе.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;
  late TaskRepository tasks;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    container = ProviderContainer(
      overrides: [localStorageProvider.overrideWithValue(LocalStorage(prefs))],
    );
    tasks = container.read(taskRepositoryProvider);
  });

  tearDown(() => container.dispose());

  test('пустой список — напоминать не о чем ни в один день', () {
    expect(tasks.unfinishedCountsByDay(), isEmpty);
  });

  test('невыполненная задача даёт день, выполненная — нет', () async {
    final today = today_();
    final t = await tasks.createAndAdd(title: 'Сегодняшняя', date: today);
    expect(tasks.unfinishedCountsByDay()[0], 1);

    await tasks.toggleCompleted(t);
    expect(tasks.unfinishedCountsByDay().containsKey(0), isFalse);
  });

  test('считает по дням раздельно и не заглядывает дальше горизонта',
      () async {
    final today = today_();
    await tasks.createAndAdd(title: 'A', date: today);
    await tasks.createAndAdd(title: 'B', date: today);
    await tasks.createAndAdd(
      title: 'Послезавтра',
      date: today.add(const Duration(days: 2)),
    );
    await tasks.createAndAdd(
      title: 'Далеко',
      date: today.add(const Duration(days: 30)),
    );

    final counts = tasks.unfinishedCountsByDay();
    expect(counts[0], 2);
    expect(counts.containsKey(1), isFalse); // завтра пусто — молчим
    expect(counts[2], 1);
    expect(counts.keys.every((d) => d < 7), isTrue);
  });

  test('ещё не материализованный повтор всё равно считается', () async {
    // Повторы для будущих дней создаются лениво — если бы карта смотрела
    // только на созданные задачи, у человека с ежедневным повтором
    // напоминания замолчали бы начиная с завтра.
    final rules = container.read(recurrenceRepositoryProvider);
    await rules.add(
      RecurrenceRule(
        id: 'daily',
        taskTitle: 'Зарядка',
        kind: RecurrenceKind.interval,
        startDate: today_(),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );

    final counts = tasks.unfinishedCountsByDay();
    for (var d = 0; d < 7; d++) {
      expect(counts[d], 1, reason: 'день +$d');
    }
  });

  test('выполненный экземпляр повтора не считается дважды', () async {
    final rules = container.read(recurrenceRepositoryProvider);
    await rules.add(
      RecurrenceRule(
        id: 'daily',
        taskTitle: 'Зарядка',
        kind: RecurrenceKind.interval,
        startDate: today_(),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );
    // Материализуем сегодняшний экземпляр и закрываем его.
    await tasks.ensureRecurrencesForDay(today_());
    final instance = tasks.tasksForDay(today_()).single;
    await tasks.toggleCompleted(instance);

    final counts = tasks.unfinishedCountsByDay();
    expect(counts.containsKey(0), isFalse, reason: 'сегодня уже закрыто');
    expect(counts[1], 1, reason: 'завтра повтор ещё впереди');
  });
}

DateTime today_() => today();
