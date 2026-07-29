import 'package:flutter_test/flutter_test.dart';
import 'package:enitor/data/models/task.dart';
import 'package:enitor/data/repositories/stats_repository.dart';

/// Задача на 29 июля с опциональным временем.
Task _task({
  int? start,
  int? end,
  DateTime? completedAt,
}) {
  final day = DateTime(2026, 7, 29);
  return Task(
    id: 't',
    title: 'task',
    date: day,
    order: 0,
    createdAt: day,
    updatedAt: day,
    startMinutes: start,
    endMinutes: end,
    completedAt: completedAt,
  );
}

void main() {
  group('taskIsOnTime — день приложения начинается в 4:00', () {
    test('невыполненная задача не считается своевременной', () {
      expect(StatsRepository.taskIsOnTime(_task()), isFalse);
    });

    test('задача без времени, закрытая днём, — вовремя', () {
      final t = _task(completedAt: DateTime(2026, 7, 29, 23, 0));
      expect(StatsRepository.taskIsOnTime(t), isTrue);
    });

    test('задача без времени, закрытая после полуночи, — с опозданием', () {
      // Неявный срок обычной задачи — конец календарного дня.
      final t = _task(completedAt: DateTime(2026, 7, 30, 1, 30));
      expect(StatsRepository.taskIsOnTime(t), isFalse);
    });

    test('задача со временем, закрытая до срока в ту же ночь, — вовремя', () {
      // Раньше падало: проверка календарной даты срабатывала до проверки
      // времени, и 01:30 всегда было опозданием.
      final t = _task(
        start: 22 * 60,
        end: 2 * 60, // 22:00 → 02:00, задача через полночь
        completedAt: DateTime(2026, 7, 30, 1, 30),
      );
      expect(StatsRepository.taskIsOnTime(t), isTrue);
    });

    test('задача через полночь, закрытая после своего конца, — с опозданием',
        () {
      final t = _task(
        start: 22 * 60,
        end: 1 * 60, // 22:00 → 01:00
        completedAt: DateTime(2026, 7, 30, 2, 0),
      );
      expect(StatsRepository.taskIsOnTime(t), isFalse);
    });

    test('дневная задача, закрытая после своего конца, — с опозданием', () {
      final t = _task(
        start: 10 * 60,
        end: 12 * 60,
        completedAt: DateTime(2026, 7, 29, 13, 0),
      );
      expect(StatsRepository.taskIsOnTime(t), isFalse);
    });

    test('дневная задача, закрытая в срок, — вовремя', () {
      final t = _task(
        start: 10 * 60,
        end: 12 * 60,
        completedAt: DateTime(2026, 7, 29, 11, 0),
      );
      expect(StatsRepository.taskIsOnTime(t), isTrue);
    });

    test('дневная задача, закрытая следующей ночью, — с опозданием', () {
      // 01:30 относится к тому же дню приложения, но 12:00 уже прошло.
      final t = _task(
        start: 10 * 60,
        end: 12 * 60,
        completedAt: DateTime(2026, 7, 30, 1, 30),
      );
      expect(StatsRepository.taskIsOnTime(t), isFalse);
    });

    test('закрытая после 4:00 следующего дня — с опозданием', () {
      // Здесь уже начался новый день приложения.
      final t = _task(completedAt: DateTime(2026, 7, 30, 4, 1));
      expect(StatsRepository.taskIsOnTime(t), isFalse);
    });

    test('закрытая заранее, в предыдущий день, — вовремя', () {
      final t = _task(completedAt: DateTime(2026, 7, 28, 12, 0));
      expect(StatsRepository.taskIsOnTime(t), isTrue);
    });
  });
}
