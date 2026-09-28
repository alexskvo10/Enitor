import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:enitor/data/models/recurrence_rule.dart';
import 'package:enitor/data/models/schedule_item.dart';
import 'package:enitor/data/repositories/schedule_repository.dart';
import 'package:enitor/data/sources/local/local_storage.dart';

ScheduleItem _item({
  int start = 600,
  int? end = 690,
  RecurrenceKind? repeat,
  List<int> weekdays = const [],
  int weekInterval = 1,
  List<int> monthDays = const [],
  int intervalDays = 1,
  DateTime? endDate,
  List<DateTime> except = const [],
}) =>
    ScheduleItem(
      id: 'x',
      title: 'Пара',
      date: DateTime(2026, 9, 28), // понедельник
      startMinutes: start,
      endMinutes: end,
      repeat: repeat ?? (weekdays.isEmpty ? null : RecurrenceKind.weekly),
      weekdays: weekdays,
      weekInterval: weekInterval,
      monthDays: monthDays,
      intervalDays: intervalDays,
      endDate: endDate,
      exceptDates: except,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

void main() {
  group('ScheduleItem.occursOn', () {
    test('разовый пункт — только в свой день', () {
      final i = _item();
      expect(i.occursOn(DateTime(2026, 9, 28, 15)), isTrue);
      expect(i.occursOn(DateTime(2026, 10, 5)), isFalse);
    });

    test('серия: дни недели, не раньше начала, не позже конца, без исключений',
        () {
      final i = _item(
        weekdays: [1, 3],
        endDate: DateTime(2026, 10, 7),
        except: [DateTime(2026, 9, 30)],
      );
      expect(i.occursOn(DateTime(2026, 9, 21)), isFalse); // до начала
      expect(i.occursOn(DateTime(2026, 9, 28)), isTrue); // пн
      expect(i.occursOn(DateTime(2026, 9, 29)), isFalse); // вт
      expect(i.occursOn(DateTime(2026, 9, 30)), isFalse); // исключение
      expect(i.occursOn(DateTime(2026, 10, 7)), isTrue); // последний день
      expect(i.occursOn(DateTime(2026, 10, 12)), isFalse); // после конца
    });

    test('через неделю: от недели начала, даже если начали не в понедельник',
        () {
      // Серия заведена в среду 30.09 на пн и ср через неделю.
      final i = _item(weekdays: [1, 3], weekInterval: 2)
          .copyWith(date: DateTime(2026, 9, 30));
      expect(i.occursOn(DateTime(2026, 9, 28)), isFalse); // до начала
      expect(i.occursOn(DateTime(2026, 9, 30)), isTrue); // та же неделя
      expect(i.occursOn(DateTime(2026, 10, 5)), isFalse); // следующая
      expect(i.occursOn(DateTime(2026, 10, 7)), isFalse);
      expect(i.occursOn(DateTime(2026, 10, 12)), isTrue); // через одну
      expect(i.occursOn(DateTime(2026, 10, 14)), isTrue);
    });

    test('по числам месяца: нет числа в месяце — пропуск', () {
      final i = _item(repeat: RecurrenceKind.monthly, monthDays: [28, 31]);
      expect(i.occursOn(DateTime(2026, 9, 28)), isTrue);
      expect(i.occursOn(DateTime(2026, 10, 31)), isTrue);
      expect(i.occursOn(DateTime(2026, 11, 30)), isFalse); // 31-го нет
      expect(i.occursOn(DateTime(2026, 10, 1)), isFalse);
    });

    test('каждые N дней не сбиваются на переходе на летнее время', () {
      final i = _item(repeat: RecurrenceKind.interval, intervalDays: 3)
          .copyWith(date: DateTime(2027, 3, 20));
      // Переход в Европе — 28.03.2027: 20 → 23 → 26 → 29.
      expect(i.occursOn(DateTime(2027, 3, 26)), isTrue);
      expect(i.occursOn(DateTime(2027, 3, 29)), isTrue);
      expect(i.occursOn(DateTime(2027, 3, 28)), isFalse);
    });
  });

  test('scheduleConflicts: пересечения и пункты без конца', () {
    ScheduleItem at(String id, int s, int? e) =>
        _item(start: s, end: e).copyWith(title: id);
    final items = [
      for (final (id, s, e) in [
        ('a', 600, 690), // 10:00–11:30
        ('b', 660, 720), // 11:00–12:00 — накладка с a
        ('c', 720, 780), // 12:00–13:00 — встык с b, не накладка
        ('d', 900, null), // 15:00 без конца
        ('e', 900, 960), // 15:00–16:00 — накладка с d
        ('f', 1000, null),
      ])
        ScheduleItem.fromJson(at(id, s, e).toJson()..['id'] = id),
    ];
    expect(scheduleConflicts(items), {'a', 'b', 'd', 'e'});
  });

  test('busyMinutes: пункт без конца времени не занимает', () {
    expect(busyMinutes([_item(start: 600, end: null)], 0, 1440), 0);
  });

  test('busyMinutes: пересечения не считаются дважды, края обрезаются', () {
    final items = [
      _item(start: 600, end: 690), // 10:00–11:30
      _item(start: 660, end: 720), // 11:00–12:00, пересекается
      _item(start: 900, end: 960), // 15:00–16:00
    ];
    expect(busyMinutes(items, 0, 1440), 120 + 60);
    expect(busyMinutes(items, 630, 1380), 90 + 60); // с 10:30
    expect(busyMinutes(items, 960, 1380), 0);
    expect(busyMinutes(const [], 0, 1440), 0);
  });

  test('scheduleBusyAhead: считается от «сейчас» до 23:00, прошлые дни — 0',
      () {
    final items = [
      _item(start: 600, end: 690), // 10:00–11:30
      _item(start: 1350, end: 1410), // 22:30–23:30, за 23:00 не считается
    ];
    final day = DateTime(2026, 9, 28);
    // Утро этого дня — всё впереди.
    expect(scheduleBusyAhead(items, day, DateTime(2026, 9, 28, 8)), 90 + 30);
    // Посреди пары — только остаток.
    expect(
      scheduleBusyAhead(items, day, DateTime(2026, 9, 28, 11)),
      30 + 30,
    );
    // Будущий день — весь, прошедший — ничего.
    expect(scheduleBusyAhead(items, day, DateTime(2026, 9, 27, 20)), 120);
    expect(scheduleBusyAhead(items, day, DateTime(2026, 9, 29, 9)), 0);
    // После 23:00 — ничего.
    expect(scheduleBusyAhead(items, day, DateTime(2026, 9, 28, 23, 10)), 0);
  });

  test('toJson/fromJson — туда и обратно без потерь', () {
    final i = _item(
      weekdays: [2, 4],
      endDate: DateTime(2026, 12, 31),
      except: [DateTime(2026, 10, 1)],
    ).copyWith(
      reminderMinutes: 10,
      note: 'Взять тетрадь',
      location: 'ауд. 301',
      colorIndex: 2,
      weekInterval: 2,
    );
    final back = ScheduleItem.fromJson(i.toJson());
    expect(back.toJson(), i.toJson());
  });

  test('fromJson: старые пункты без поля repeat читаются как раньше', () {
    final old = _item(weekdays: [1]).toJson()..remove('repeat');
    expect(ScheduleItem.fromJson(old).repeat, RecurrenceKind.weekly);
    final once = _item().toJson()..remove('repeat');
    expect(ScheduleItem.fromJson(once).isSeries, isFalse);
  });

  group('ScheduleRepository', () {
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

    test('пункт переживает перезапуск, день серии удаляется отдельно',
        () async {
      final repo = container.read(scheduleRepositoryProvider);
      final item = await repo.create(
        title: 'Английский',
        date: DateTime(2026, 9, 28),
        startMinutes: 600,
        endMinutes: 690,
        weekdays: [1],
      );
      await repo.deleteOccurrence(item, DateTime(2026, 10, 5));

      // Новый репозиторий поверх того же хранилища — как после перезапуска.
      final reloaded = ScheduleRepository(container.read(localStorageProvider));
      expect(
        reloaded.forDay(DateTime(2026, 9, 28)).single.title,
        'Английский',
      );
      expect(reloaded.forDay(DateTime(2026, 10, 5)), isEmpty);
      expect(reloaded.forDay(DateTime(2026, 10, 12)), hasLength(1));
    });
  });
}
