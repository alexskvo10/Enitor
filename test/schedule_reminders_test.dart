import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:enitor/data/models/goal.dart';
import 'package:enitor/data/models/recurrence_rule.dart';
import 'package:enitor/data/models/schedule_item.dart';
import 'package:enitor/data/models/task.dart';
import 'package:enitor/data/repositories/schedule_repository.dart';
import 'package:enitor/data/sources/local/local_storage.dart';
import 'package:enitor/services/notification_controller.dart';
import 'package:enitor/services/notification_prefs.dart';
import 'package:enitor/services/notification_service.dart';

ScheduleItem _item(
  String title, {
  required DateTime date,
  int start = 600,
  int? reminder = 10,
  List<int> weekdays = const [],
}) =>
    ScheduleItem(
      id: title,
      title: title,
      date: date,
      startMinutes: start,
      endMinutes: start + 30,
      repeat: weekdays.isEmpty ? null : RecurrenceKind.weekly,
      weekdays: weekdays,
      reminderMinutes: reminder,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

/// Запоминает, что контроллер отдал планировщику, ничего не планируя.
class _SpyService extends NotificationService {
  List<(DateTime, ScheduleItem)>? passed;

  @override
  Future<void> applySchedule({
    required NotificationPrefs prefs,
    required List<Task> tasks,
    required List<Goal> goals,
    required int pendingTransferCount,
    required Map<int, int> unfinishedByDay,
    required int taskBacklogCount,
    required int goalBacklogCount,
    List<(DateTime, ScheduleItem)> scheduleReminders = const [],
  }) async {
    passed = scheduleReminders;
  }
}

void main() {
  final mon = DateTime(2026, 9, 28);

  test('момент = начало минус «за сколько»; прошедшие и без напоминания — нет',
      () {
    final r = scheduleReminders(
      [
        _item('Пара', date: mon, start: 600, reminder: 10),
        _item('Сейчас', date: mon, start: 540, reminder: 0), // 9:00, прошло
        _item('Молча', date: mon, start: 900, reminder: null),
      ],
      DateTime(2026, 9, 28, 9, 30),
    );
    expect(r.map((e) => (e.$1, e.$2.title)), [
      (DateTime(2026, 9, 28, 9, 50), 'Пара'),
    ]);
  });

  test('напоминание за час до 0:30 уходит на 23:30 накануне', () {
    final r = scheduleReminders(
      [_item('Ночью', date: mon, start: 30, reminder: 60)],
      DateTime(2026, 9, 27, 12),
    );
    expect(r.single.$1, DateTime(2026, 9, 27, 23, 30));
  });

  test('серия — по дням окна недели, по времени и не больше лимита', () {
    final weekly = _item('Утро', date: mon, weekdays: [1, 2, 3, 4, 5, 6, 7]);
    final r = scheduleReminders([weekly], DateTime(2026, 9, 28, 8));
    expect(r, hasLength(7));
    expect(r.first.$1, DateTime(2026, 9, 28, 9, 50));
    expect(r.last.$1, DateTime(2026, 10, 4, 9, 50));

    final capped =
        scheduleReminders([weekly], DateTime(2026, 9, 28, 8), limit: 3);
    expect(capped, hasLength(3));
    expect(capped.last.$1, DateTime(2026, 9, 30, 9, 50));
  });

  test('контроллер передаёт напоминания расписания планировщику', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final spy = _SpyService();
    final container = ProviderContainer(
      overrides: [
        localStorageProvider.overrideWithValue(LocalStorage(prefs)),
        notificationServiceProvider.overrideWithValue(spy),
      ],
    );
    addTearDown(container.dispose);

    final tomorrow = DateTime.now().add(const Duration(days: 1));
    await container.read(scheduleRepositoryProvider).create(
          title: 'Английский',
          date: tomorrow,
          startMinutes: 600,
          endMinutes: 690,
          reminderMinutes: 15,
        );
    await container.read(notificationControllerProvider).reschedule();

    expect(spy.passed!.single.$2.title, 'Английский');
    expect(
      spy.passed!.single.$1,
      DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 9, 45),
    );
  });
}
