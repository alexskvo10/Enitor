import 'package:flutter_test/flutter_test.dart';
import 'package:enitor/core/utils/date_utils.dart';
import 'package:enitor/data/models/goal.dart';
import 'package:enitor/features/retro/week_stats.dart';
import 'package:enitor/services/weekly_retro_controller.dart';

// Опорная неделя для всех проверок: пн 5 января 2026 — вс 11 января 2026.
// Следующая (текущая на момент разбора): пн 12 — вс 18 января.
final _reviewed = DateTime(2026, 1, 5);
final _current = DateTime(2026, 1, 12);

Goal _weekGoal({
  required String id,
  required DateTime weekStart,
  bool completed = false,
  bool isTransferred = false,
}) {
  final now = DateTime(2026, 1, 6, 12);
  return Goal(
    id: id,
    period: GoalPeriod.week,
    year: weekStart.year,
    weekStart: weekStart,
    title: id,
    createdAt: now,
    updatedAt: now,
    completed: completed,
    completedAt: completed ? now : null,
    isTransferred: isTransferred,
  );
}

void main() {
  group('retroReviewWeekStart — разбираем последнюю завершённую неделю', () {
    test('утро понедельника после 4:00 — прошлая неделя', () {
      expect(retroReviewWeekStart(DateTime(2026, 1, 12, 5)), _reviewed);
    });

    test('вечер понедельника — та же прошлая неделя', () {
      expect(retroReviewWeekStart(DateTime(2026, 1, 12, 19)), _reviewed);
    });

    test('среда — цель не сдвигается до конца недели', () {
      expect(retroReviewWeekStart(DateTime(2026, 1, 14, 9)), _reviewed);
    });

    test('воскресенье вечером — всё ещё прошлая, текущая не закрыта', () {
      expect(retroReviewWeekStart(DateTime(2026, 1, 18, 23)), _reviewed);
    });

    test('ночь понедельника до 4:00 — неделя ещё не закрыта, разбираем ту, '
        'что перед ней', () {
      // 02:00 понедельника по правилу дня приложения — это ещё воскресенье.
      expect(
        retroReviewWeekStart(DateTime(2026, 1, 12, 2)),
        _reviewed.subtract(const Duration(days: 7)),
      );
    });
  });

  group('retroDueAt — момент, с которого окно доступно', () {
    test('понедельник 19:00 по умолчанию', () {
      expect(
        retroDueAt(DateTime(2026, 1, 12, 20), weekday: 1, minutes: 19 * 60),
        DateTime(2026, 1, 12, 19),
      );
    });

    test('другой день недели сдвигает момент внутри текущей недели', () {
      expect(
        retroDueAt(DateTime(2026, 1, 12, 20), weekday: 4, minutes: 8 * 60 + 30),
        DateTime(2026, 1, 15, 8, 30),
      );
    });

    test('до назначенного момента окно ещё не доступно', () {
      final now = DateTime(2026, 1, 12, 10);
      expect(
        now.isBefore(retroDueAt(now, weekday: 1, minutes: 19 * 60)),
        isTrue,
      );
    });

    test('пропустили вечер — в среду окно всё ещё про ту же неделю', () {
      final now = DateTime(2026, 1, 14, 9);
      expect(retroReviewWeekStart(now), _reviewed);
      expect(
        now.isBefore(retroDueAt(now, weekday: 1, minutes: 19 * 60)),
        isFalse,
      );
    });

    test('новая неделя — цель сдвигается, старая больше не всплывает', () {
      final now = DateTime(2026, 1, 19, 10); // следующий понедельник, 10:00
      expect(retroReviewWeekStart(now), _current);
      // 10:00 ещё раньше 19:00 — ждём вечера, а не показываем сразу.
      expect(
        now.isBefore(retroDueAt(now, weekday: 1, minutes: 19 * 60)),
        isTrue,
      );
    });
  });

  group('computeWeekStats — цели именно на эту неделю', () {
    test('берутся только цели-недели с тем же понедельником', () {
      final goals = [
        _weekGoal(id: 'своя', weekStart: _reviewed),
        _weekGoal(id: 'чужая неделя', weekStart: _current),
        Goal(
          id: 'месячная',
          period: GoalPeriod.month,
          year: 2026,
          month: 1,
          title: 'месячная',
          createdAt: DateTime(2026, 1, 6),
          updatedAt: DateTime(2026, 1, 6),
        ),
      ];
      final s = computeWeekStats(_reviewed, const [], goals, const {});
      expect(s.weekGoals.map((g) => g.id), ['своя']);
    });

    test('достигнутые считаются, перенесённый оригинал — нет', () {
      final goals = [
        _weekGoal(id: 'сделана', weekStart: _reviewed, completed: true),
        _weekGoal(id: 'не сделана', weekStart: _reviewed),
        // Перенесена в следующую неделю: оригинал остаётся здесь и честно
        // считается недостигнутым, копия живёт уже в другой неделе.
        _weekGoal(id: 'перенесена', weekStart: _reviewed, isTransferred: true),
        _weekGoal(id: 'копия', weekStart: _current),
      ];
      final s = computeWeekStats(_reviewed, const [], goals, const {});
      expect(s.weekGoals.length, 3);
      expect(s.weekGoalsDone, 1);
    });

    test('неделя без данных, но с целями — не пустая', () {
      final s = computeWeekStats(
        _reviewed,
        const [],
        [_weekGoal(id: 'цель', weekStart: _reviewed)],
        const {},
      );
      expect(s.isEmpty, isFalse);
    });

    test('совсем без данных — пустая, окно показывать нечем', () {
      final s = computeWeekStats(_reviewed, const [], const [], const {});
      expect(s.isEmpty, isTrue);
    });
  });

  group('weekGoalsGraceEnd — цели недели ещё можно закрыть', () {
    test('давно прошедшая неделя — окно закрыто', () {
      expect(weekGoalsGraceEnd(_reviewed), isNull);
    });

    test('текущая неделя — окно открыто до вторника следующей', () {
      final thisWeek = startOfWeek(today());
      final end = weekGoalsGraceEnd(thisWeek);
      expect(end, isNotNull);
      // Воскресенье + graceDays(неделя) = 2 → вторник следующей недели.
      expect(end, thisWeek.add(const Duration(days: 8)));
      expect(end!.weekday, DateTime.tuesday);
    });

    test('прошлая неделя — окно живо ровно до вторника этой', () {
      final lastWeek = startOfWeek(today()).subtract(const Duration(days: 7));
      final graceEnd = lastWeek.add(const Duration(days: 8));
      // Разбор приходит в понедельник вечером — то есть ВНУТРИ окна.
      expect(graceEnd.isBefore(startOfWeek(today())), isFalse);
      expect(
        weekGoalsGraceEnd(lastWeek),
        today().isAfter(graceEnd) ? isNull : graceEnd,
      );
    });
  });
}
