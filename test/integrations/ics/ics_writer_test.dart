import 'dart:convert';

import 'package:enitor/features/integrations/ics/ics_parser.dart';
import 'package:enitor/features/integrations/ics/ics_writer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

void main() {
  tzdata.initializeTimeZones();

  final moscow = tz.getLocation('Europe/Moscow');
  final newYork = tz.getLocation('America/New_York');
  final now = DateTime.utc(2026, 10, 25);

  group('запись: фолдинг и экранирование', () {
    test('строки CRLF, каждая физическая строка не длиннее 75 октетов', () {
      final text = writeIcs(
        [
          IcsOutEvent(
            uid: 'long',
            summary: 'Очень длинное название события ' * 6,
            start: DateTime(2026, 11, 3, 9),
            end: DateTime(2026, 11, 3, 10),
          ),
        ],
        zone: moscow,
        now: now,
      );
      expect(text.endsWith('\r\n'), isTrue);
      expect(text.replaceAll('\r\n', '').contains('\n'), isFalse);
      final physical = text.split('\r\n');
      for (final line in physical) {
        if (line.isEmpty) {
          continue;
        }
        expect(utf8.encode(line).length, lessThanOrEqualTo(75), reason: line);
      }
      expect(physical.where((l) => l.startsWith(' ')), isNotEmpty);
    });

    test('символ из нескольких октетов не разрывается при фолдинге', () {
      final summary = '🎓' * 30;
      final text = writeIcs(
        [
          IcsOutEvent(
            uid: 'emoji',
            summary: summary,
            start: DateTime(2026, 11, 3, 9),
          ),
        ],
        zone: moscow,
        now: now,
      );
      final cal = parseIcs(text, local: moscow);
      expect(cal.events.single.summary, summary);
    });

    test('экранирование и обратное чтение: запятая, ;, \\, перенос', () {
      const summary = 'Пять, шесть; семь\\ восемь\nдевять';
      final text = writeIcs(
        [
          IcsOutEvent(
            uid: 'esc',
            summary: summary,
            description: 'Описание, с; \\ и\nпереносом',
            location: 'Ауд. 5, корпус 2',
            start: DateTime(2026, 11, 3, 9),
          ),
        ],
        zone: moscow,
        now: now,
      );
      expect(
        text.contains('SUMMARY:Пять\\, шесть\\; семь\\\\ восемь\\nдевять'),
        isTrue,
      );
      final e = parseIcs(text, local: moscow).events.single;
      expect(e.summary, summary);
      expect(e.description, 'Описание, с; \\ и\nпереносом');
      expect(e.location, 'Ауд. 5, корпус 2');
    });

    test('UID с запятой экранируется и возвращается без изменений', () {
      final text = writeIcs(
        [
          IcsOutEvent(
            uid: 'a,b;c',
            summary: 'uid',
            start: DateTime(2026, 11, 3, 9),
          ),
        ],
        zone: moscow,
        now: now,
      );
      expect(text.contains('UID:a\\,b\\;c\r\n'), isTrue);
      expect(parseIcs(text, local: moscow).events.single.uid, 'a,b;c');
    });
  });

  group('запись: VTIMEZONE, RRULE и обратное чтение', () {
    test('Москва без переходов: один STANDARD с +0300', () {
      final text = writeIcs(
        [IcsOutEvent(uid: 'm', summary: 'm', start: DateTime(2026, 11, 3, 9))],
        zone: moscow,
        now: now,
      );
      expect(text, contains('TZID:Europe/Moscow'));
      expect(text, contains('BEGIN:STANDARD'));
      expect(text, isNot(contains('BEGIN:DAYLIGHT')));
      expect(text, contains('TZOFFSETTO:+0300'));
    });

    test('Нью-Йорк 2026: DAYLIGHT и STANDARD с правилами 2SU и 1SU', () {
      final text = writeIcs(
        [IcsOutEvent(uid: 'ny', summary: 'ny', start: DateTime(2026, 6, 1, 9))],
        zone: newYork,
        now: now,
      );
      expect(text, contains('BEGIN:DAYLIGHT'));
      expect(text, contains('TZOFFSETFROM:-0500'));
      expect(text, contains('TZOFFSETTO:-0400'));
      expect(text, contains('RRULE:FREQ=YEARLY;BYMONTH=3;BYDAY=2SU'));
      expect(text, contains('RRULE:FREQ=YEARLY;BYMONTH=11;BYDAY=1SU'));
    });

    test('событие прошлых лет: переходы тех лет разовые, без правила', () {
      final text = writeIcs(
        [IcsOutEvent(uid: 'old', summary: 'old', start: DateTime(2010, 7, 1, 9))],
        zone: moscow,
        now: now,
      );
      // Летом 2010 в Москве было +0400 (летнее время отменили в 2011).
      expect(text, contains('BEGIN:DAYLIGHT'));
      expect(text, contains('TZOFFSETTO:+0400'));
      expect(text, isNot(contains('RRULE:FREQ=YEARLY')));
      // Последнее смещение — нынешнее.
      final offsets = RegExp(r'TZOFFSETTO:([+-]\d{4})')
          .allMatches(text)
          .map((m) => m[1])
          .toList();
      expect(offsets.last, '+0300');
    });

    test('туда-обратно: повторение, EXDATE, UNTIL в UTC', () {
      final until = DateTime(2026, 12, 31, 23, 59, 59);
      final text = writeIcs(
        [
          IcsOutEvent(
            uid: 'rr',
            summary: 'Семинар',
            start: DateTime(2026, 11, 3, 9),
            end: DateTime(2026, 11, 3, 10, 30),
            rule: IcsRule(
              freq: IcsFreq.weekly,
              byDay: const [IcsByDay(DateTime.tuesday)],
              until: until,
              raw: '',
            ),
            exDates: [DateTime(2026, 11, 10, 9)],
          ),
        ],
        zone: newYork,
        now: now,
      );
      // 23:59:59 в Нью-Йорке (EST, -5) — 04:59:59 UTC следующего дня.
      expect(text, contains('UNTIL=20270101T045959Z'));
      expect(text, contains('EXDATE;TZID=America/New_York:20261110T090000'));

      final cal = parseIcs(text, local: newYork);
      expect(cal.warnings, isEmpty);
      final e = cal.events.single;
      expect(e.summary, 'Семинар');
      expect(e.start, DateTime(2026, 11, 3, 9));
      expect(e.end, DateTime(2026, 11, 3, 10, 30));
      expect(e.rule, isNotNull);
      expect(e.rule!.freq, IcsFreq.weekly);
      expect(e.rule!.byDay.single.weekday, DateTime.tuesday);
      expect(e.rule!.until, until);
      expect(e.exDates.single, DateTime(2026, 11, 10, 9));
    });
  });
}
