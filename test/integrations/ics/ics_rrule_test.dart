import 'package:enitor/features/integrations/ics/ics_parser.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

void main() {
  tzdata.initializeTimeZones();

  final moscow = tz.getLocation('Europe/Moscow');

  group('RRULE и EXDATE', () {
    test('все поля RRULE разобраны', () {
      const value =
          'FREQ=MONTHLY;INTERVAL=2;BYDAY=2TU,-1SU,MO;BYMONTHDAY=1,15,-1;'
          'BYMONTH=1,3,11;BYSETPOS=-1;UNTIL=20261231T235959Z;COUNT=10';
      final cal = parseIcs(
        'BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nUID:r\r\n'
        'DTSTART;TZID=Europe/Moscow:20261103T090000\r\n'
        'RRULE:$value\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n',
        local: moscow,
      );
      final rule = cal.events.single.rule!;

      expect(cal.warnings, isEmpty);
      expect(rule.freq, IcsFreq.monthly);
      expect(rule.interval, 2);
      expect(rule.byDay.map((d) => d.weekday), [2, 7, 1]);
      expect(rule.byDay.map((d) => d.ordinal), [2, -1, null]);
      expect(rule.byMonthDay, [1, 15, -1]);
      expect(rule.byMonth, [1, 3, 11]);
      expect(rule.bySetPos, [-1]);
      // 31.12.2026 23:59:59 UTC — это 01.01.2027 02:59:59 по Москве.
      expect(rule.until, DateTime(2027, 1, 1, 2, 59, 59));
      expect(rule.count, 10);
      expect(rule.raw, value);
    });

    test('INTERVAL по умолчанию 1, без лишних полей пустые списки', () {
      final cal = parseIcs(
        'BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nUID:d\r\n'
        'DTSTART:20261103T090000\r\nRRULE:FREQ=DAILY\r\nEND:VEVENT\r\n'
        'END:VCALENDAR\r\n',
        local: moscow,
      );
      final rule = cal.events.single.rule!;
      expect(rule.interval, 1);
      expect(rule.byDay, isEmpty);
      expect(rule.until, isNull);
      expect(rule.count, isNull);
    });

    test('UNTIL датой: конец этого дня', () {
      final cal = parseIcs(
        'BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nUID:u\r\n'
        'DTSTART;TZID=Europe/Moscow:20261001T090000\r\n'
        'RRULE:FREQ=DAILY;UNTIL=20261031\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n',
        local: moscow,
      );
      expect(
        cal.events.single.rule!.until,
        DateTime(2026, 10, 31, 23, 59, 59),
      );
    });

    test('UNTIL без Z у плавающего DTSTART — в той же плавающей зоне', () {
      final cal = parseIcs(
        'BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nUID:f\r\n'
        'DTSTART:20261001T090000\r\n'
        'RRULE:FREQ=DAILY;UNTIL=20261031T120000\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n',
        local: moscow,
      );
      expect(cal.events.single.rule!.until, DateTime(2026, 10, 31, 12));
    });

    test('несколько EXDATE: строки, запятые, TZID в кавычках, VALUE=DATE, Z', () {
      final cal = parseIcs(
        'BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nUID:ex\r\n'
        'DTSTART;TZID=Europe/Moscow:20261102T090000\r\n'
        'RRULE:FREQ=WEEKLY;BYDAY=MO\r\n'
        'EXDATE;TZID=Europe/Moscow:20261109T090000,20261116T090000\r\n'
        'EXDATE;TZID="Europe/Moscow":20261123T090000\r\n'
        'EXDATE;VALUE=DATE:20261130\r\n'
        'EXDATE:20261207T090000Z\r\n'
        'END:VEVENT\r\nEND:VCALENDAR\r\n',
        local: moscow,
      );
      final e = cal.events.single;
      expect(cal.warnings, isEmpty);
      expect(e.exDates, [
        DateTime(2026, 11, 9, 9),
        DateTime(2026, 11, 16, 9),
        DateTime(2026, 11, 23, 9),
        DateTime(2026, 11, 30),
        DateTime(2026, 12, 7, 12),
      ]);
    });

    test('битый EXDATE пропускается, остальные остаются', () {
      final cal = parseIcs(
        'BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nUID:bx\r\n'
        'DTSTART;TZID=Europe/Moscow:20261102T090000\r\n'
        'RRULE:FREQ=WEEKLY\r\n'
        'EXDATE;TZID=Europe/Moscow:20261109T090000,2026ZZZZ\r\n'
        'END:VEVENT\r\nEND:VCALENDAR\r\n',
        local: moscow,
      );
      expect(cal.events.single.exDates, [DateTime(2026, 11, 9, 9)]);
      expect(cal.warnings.single, contains('2026ZZZZ'));
    });
  });

  test('INTERVAL=0 — как 1, без деления на ноль', () {
    final cal = parseIcs(
      'BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nUID:z\r\n'
      'DTSTART:20261103T090000\r\nRRULE:FREQ=WEEKLY;INTERVAL=0;BYDAY=TU\r\n'
      'END:VEVENT\r\nEND:VCALENDAR\r\n',
      local: moscow,
    );
    expect(cal.events.single.rule!.interval, 1);
  });

  test('изменённый и отменённый дни серии (RECURRENCE-ID) не затирают серию',
      () {
    final cal = parseIcs(
      'BEGIN:VCALENDAR\r\n'
      'BEGIN:VEVENT\r\nUID:s\r\nSUMMARY:Планёрка\r\n'
      'DTSTART;TZID=Europe/Moscow:20261102T100000\r\n'
      'RRULE:FREQ=WEEKLY;BYDAY=MO\r\nEND:VEVENT\r\n'
      'BEGIN:VEVENT\r\nUID:s\r\nSUMMARY:Планёрка (перенесена)\r\n'
      'RECURRENCE-ID;TZID=Europe/Moscow:20261109T100000\r\n'
      'DTSTART;TZID=Europe/Moscow:20261110T120000\r\nEND:VEVENT\r\n'
      'BEGIN:VEVENT\r\nUID:s\r\nSTATUS:CANCELLED\r\n'
      'RECURRENCE-ID;TZID=Europe/Moscow:20261116T100000\r\n'
      'DTSTART;TZID=Europe/Moscow:20261116T100000\r\nEND:VEVENT\r\n'
      'END:VCALENDAR\r\n',
      local: moscow,
    );
    expect(cal.events, hasLength(2));
    final series = cal.events.firstWhere((e) => e.uid == 's');
    expect(series.rule, isNotNull);
    expect(series.exDates, [
      DateTime(2026, 11, 9, 10),
      DateTime(2026, 11, 16, 10),
    ]);
    final moved = cal.events.firstWhere((e) => e.uid != 's');
    expect(moved.summary, 'Планёрка (перенесена)');
    expect(moved.rule, isNull);
    expect(moved.start, DateTime(2026, 11, 10, 12));
  });
}
