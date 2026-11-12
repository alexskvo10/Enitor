import 'dart:io';

import 'package:enitor/features/integrations/ics/ics_parser.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

String _fixture(String name) =>
    File('test/integrations/ics/fixtures/$name').readAsStringSync();

IcsEvent _byUid(IcsCalendar cal, String uid) =>
    cal.events.firstWhere((e) => e.uid == uid);

void main() {
  tzdata.initializeTimeZones();

  final moscow = tz.getLocation('Europe/Moscow');

  group('образцы экспорта', () {
    test('Google Calendar: события, все-день, UTC, UNTIL, отмена', () {
      final cal = parseIcs(_fixture('google.ics'), local: moscow);

      expect(cal.warnings, isEmpty);
      expect(cal.events.map((e) => e.uid), [
        '4f2c1a9e-01@google.com',
        'birthday-anya@google.com',
        'utc-call@google.com',
        'gym-weekly@google.com',
      ]);

      final meeting = _byUid(cal, '4f2c1a9e-01@google.com');
      expect(meeting.summary, 'Встреча с командой');
      expect(meeting.location, 'Офис, 3 этаж');
      expect(meeting.start, DateTime(2026, 11, 3, 10));
      expect(meeting.end, DateTime(2026, 11, 3, 11, 30));
      expect(meeting.allDay, isFalse);
      expect(
        meeting.description,
        'Повестка: квартальные цели, бюджет и найм на второе полугодие\n'
        'Ссылка: https://meet.example.com/abc-defg-hij\n'
        'Вложение: план.pdf',
      );

      final birthday = _byUid(cal, 'birthday-anya@google.com');
      expect(birthday.allDay, isTrue);
      expect(birthday.start, DateTime(2026, 11, 8));
      expect(birthday.end, DateTime(2026, 11, 9));
      expect(birthday.rule?.freq, IcsFreq.yearly);

      final call = _byUid(cal, 'utc-call@google.com');
      expect(call.start, DateTime(2026, 10, 26, 15));
      expect(call.end, DateTime(2026, 10, 26, 16));

      final gym = _byUid(cal, 'gym-weekly@google.com');
      expect(gym.rule?.freq, IcsFreq.weekly);
      expect(gym.rule?.byDay.map((d) => d.weekday), [DateTime.monday]);
      expect(gym.rule?.until, DateTime(2026, 12, 31, 3));
    });

    test('Outlook: Windows-имена зон, VALARM не портит событие, неизвестная зона', () {
      final cal = parseIcs(_fixture('outlook.ics'), local: moscow);

      expect(cal.events.length, 4);
      expect(cal.warnings.length, 1);
      expect(cal.warnings.single, contains('Mars/Olympus'));

      final review = _byUid(cal, '040000008200E00074C5B7101A82E008');
      expect(review.summary, 'Ревью релиза');
      expect(review.location, 'Переговорная 2');
      expect(review.start, DateTime(2026, 11, 5, 14));
      expect(review.end, DateTime(2026, 11, 5, 15, 30));
      expect(review.description, 'Пункты:\n- API\n- миграции, тесты');

      // Берлин в ноябре: CET (+1), то есть 14:00 Берлина — 16:00 Москвы.
      final berlin = _byUid(cal, '040000008200E00074C5B7101A82E009');
      expect(berlin.start, DateTime(2026, 11, 5, 16));
      expect(berlin.end, DateTime(2026, 11, 5, 17, 30));

      // Нью-Йорк после перевода на зимнее время: EST (-5), 09:00 — 17:00 Москвы.
      final ny = _byUid(cal, '040000008200E00074C5B7101A82E010');
      expect(ny.start, DateTime(2026, 11, 4, 17));
      expect(ny.end, DateTime(2026, 11, 4, 18));
      expect(ny.rule?.byDay.single.weekday, DateTime.wednesday);
      expect(ny.rule?.count, 3);

      // Неизвестная зона: время считается локальным, как записано.
      final mars = _byUid(cal, '040000008200E00074C5B7101A82E011');
      expect(mars.start, DateTime(2026, 11, 10, 10));
    });

    test('Apple Calendar: X-свойства, экранирование, VALARM внутри события', () {
      final cal = parseIcs(_fixture('apple.ics'), local: moscow);

      expect(cal.warnings, isEmpty);
      expect(cal.events.length, 2);

      final lecture = _byUid(cal, '8C1F-2233@apple');
      expect(lecture.summary, 'Лекция, часть 1');
      expect(lecture.location, 'Аудитория 402');
      expect(lecture.description, 'Тема: линейная алгебра\nСтраница 12; 13');
      expect(lecture.start, DateTime(2026, 11, 10, 9, 30));
      expect(lecture.end, DateTime(2026, 11, 10, 11));

      final seminar = _byUid(cal, '8C1F-2244@apple');
      expect(seminar.description, isNull);
      expect(seminar.start, DateTime(2026, 10, 26, 18));
      expect(seminar.rule?.byDay.single.weekday, DateTime.tuesday);
      expect(seminar.rule?.byDay.single.ordinal, isNull);
    });

    test('расписание вуза A: MO/WE, UNTIL в UTC, EXDATE в нескольких строках', () {
      final cal = parseIcs(_fixture('university_a.ics'), local: moscow);

      expect(cal.warnings, isEmpty);
      expect(cal.events.length, 2);

      final math = _byUid(cal, 'math-analysis-2026@uni.example');
      expect(math.summary, 'Математический анализ, лекция');
      expect(math.location, 'Корпус А, ауд. 301');
      expect(math.start, DateTime(2026, 9, 7, 9));
      expect(math.end, DateTime(2026, 9, 7, 10, 30));
      expect(math.rule?.freq, IcsFreq.weekly);
      expect(math.rule?.byDay.map((d) => d.weekday), [1, 3]);
      // 20261218T235959Z — это 19.12.2026 02:59:59 по Москве.
      expect(math.rule?.until, DateTime(2026, 12, 19, 2, 59, 59));
      expect(math.exDates, [
        DateTime(2026, 10, 26, 9),
        DateTime(2026, 11, 4, 9),
        DateTime(2026, 11, 11, 9),
      ]);

      final pe = _byUid(cal, 'pe-2026@uni.example');
      expect(pe.rule?.byDay.single.weekday, DateTime.friday);
      expect(pe.rule?.until, isNull);
    });

    test('расписание вуза B: INTERVAL=2, COUNT, порядковый BYDAY', () {
      final cal = parseIcs(_fixture('university_b.ics'), local: moscow);

      expect(cal.warnings, isEmpty);
      expect(cal.events.length, 3);

      final lab = _byUid(cal, 'programming-2026@uni.example');
      expect(lab.rule?.interval, 2);
      expect(lab.rule?.count, 6);
      expect(lab.rule?.byDay.single.weekday, DateTime.tuesday);
      expect(lab.exDates, [DateTime(2026, 10, 20, 11)]);
      expect(lab.end, DateTime(2026, 9, 8, 12, 30));

      final law = _byUid(cal, 'law-seminar-2026@uni.example');
      expect(law.rule?.freq, IcsFreq.monthly);
      expect(law.rule?.byDay.single.weekday, DateTime.wednesday);
      expect(law.rule?.byDay.single.ordinal, 2);

      final exam = _byUid(cal, 'exam-2026@uni.example');
      expect(exam.rule, isNull);
      expect(exam.start, DateTime(2026, 12, 21, 9));
    });
  });
}
