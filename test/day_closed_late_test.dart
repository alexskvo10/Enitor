import 'package:enitor/data/models/task.dart';
import 'package:enitor/features/today/today_screen.dart';
import 'package:flutter_test/flutter_test.dart';

// Карточка бюджета дня желтеет и пишет «День закрыт после 23:00», только если
// день ДЕЙСТВИТЕЛЬНО закрыли поздно. Пока это считалось по текущему времени,
// закрытый в 17:00 день сам собой перекрашивался в 23:05 — и любой прошедший
// день навсегда оставался «закрытым поздно».

final _day = DateTime(2026, 8, 26);

Task _task({DateTime? completedAt, bool isTransferred = false}) {
  final created = DateTime(2026, 8, 26, 9);
  return Task(
    id: 'task-${completedAt?.toIso8601String() ?? 'open'}-$isTransferred',
    title: 'Задача',
    date: _day,
    createdAt: created,
    updatedAt: created,
    completedAt: completedAt,
    estimatedMinutes: 30,
    isTransferred: isTransferred,
  );
}

void main() {
  test('день, закрытый днём, не считается закрытым поздно', () {
    final tasks = [
      _task(completedAt: DateTime(2026, 8, 26, 12, 40)),
      _task(completedAt: DateTime(2026, 8, 26, 17)),
    ];

    expect(dayClosedLate(_day, tasks), isFalse);
  });

  test('последняя отметка после 23:05 — закрыт поздно', () {
    final tasks = [
      _task(completedAt: DateTime(2026, 8, 26, 17)),
      _task(completedAt: DateTime(2026, 8, 26, 23, 40)),
    ];

    expect(dayClosedLate(_day, tasks), isTrue);
  });

  test('пять минут запаса: 23:04 ещё вовремя, 23:06 уже нет', () {
    expect(
      dayClosedLate(_day, [_task(completedAt: DateTime(2026, 8, 26, 23, 4))]),
      isFalse,
    );
    expect(
      dayClosedLate(_day, [_task(completedAt: DateTime(2026, 8, 26, 23, 6))]),
      isTrue,
    );
  });

  test('дозакрытый на следующий день — поздно', () {
    // Отметка уехала за полночь: для этого дня это опоздание, даже если по
    // «дню приложения» (до 4:00) момент ещё относится к уходящим суткам.
    final tasks = [_task(completedAt: DateTime(2026, 8, 27, 1, 15))];

    expect(dayClosedLate(_day, tasks), isTrue);
  });

  test('без отметок о выполнении — не поздно', () {
    // Незакрытый день сюда не попадает: у карточки для него другая ветка.
    expect(dayClosedLate(_day, [_task()]), isFalse);
    expect(dayClosedLate(_day, const <Task>[]), isFalse);
  });
}
