import 'package:enitor/features/integrations/ics/ics_parser.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Календарь с одним событием и заданными свойствами времени.
String _event(String props) =>
    'BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nUID:tz\r\nSUMMARY:Время\r\n'
    '$props\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n';

void main() {
  tzdata.initializeTimeZones();

  final moscow = tz.getLocation('Europe/Moscow');

  group('часовые пояса', () {
    test('UTC при локальной Europe/Moscow: +3', () {
      final cal = parseIcs(
        _event('DTSTART:20261103T060000Z\r\nDTEND:20261103T070000Z'),
        local: moscow,
      );
      final e = cal.events.single;
      expect(e.start, DateTime(2026, 11, 3, 9));
      expect(e.end, DateTime(2026, 11, 3, 10));
    });

    test('UTC, а локальная зона — America/New_York', () {
      final cal = parseIcs(
        _event('DTSTART:20261103T060000Z'),
        local: tz.getLocation('America/New_York'),
      );
      // 06:00 UTC при EST (-5) — 01:00 того же дня.
      expect(cal.events.single.start, DateTime(2026, 11, 3, 1));
    });

    test('TZID America/New_York переводится в Москву', () {
      final cal = parseIcs(
        _event(
          'DTSTART;TZID=America/New_York:20261103T090000\r\n'
          'DTEND;TZID=America/New_York:20261103T100000',
        ),
        local: moscow,
      );
      final e = cal.events.single;
      // 09:00 EST = 14:00 UTC = 17:00 МСК.
      expect(e.start, DateTime(2026, 11, 3, 17));
      expect(e.end, DateTime(2026, 11, 3, 18));
    });

    test('смена летнего времени в Europe/Berlin, 29.03.2026', () {
      final before = parseIcs(
        _event('DTSTART;TZID=Europe/Berlin:20260328T090000'),
        local: moscow,
      );
      // 28.03 Берлин ещё CET (+1): 08:00 UTC = 11:00 МСК.
      expect(before.events.single.start, DateTime(2026, 3, 28, 11));

      final switchDay = parseIcs(
        _event('DTSTART;TZID=Europe/Berlin:20260329T090000'),
        local: moscow,
      );
      // 29.03 уже CEST (+2): 07:00 UTC = 10:00 МСК.
      expect(switchDay.events.single.start, DateTime(2026, 3, 29, 10));
    });

    test('плавающее время остаётся как записано, зона не важна', () {
      final cal = parseIcs(
        _event('DTSTART:20261103T090000\r\nDTEND:20261103T100000'),
        local: tz.getLocation('America/New_York'),
      );
      expect(cal.events.single.start, DateTime(2026, 11, 3, 9));
      expect(cal.events.single.end, DateTime(2026, 11, 3, 10));
    });

    test('весь день: DTSTART и DTEND как даты, конец эксклюзивный', () {
      final cal = parseIcs(
        _event('DTSTART;VALUE=DATE:20261103\r\nDTEND;VALUE=DATE:20261104'),
        local: moscow,
      );
      final e = cal.events.single;
      expect(e.allDay, isTrue);
      expect(e.start, DateTime(2026, 11, 3));
      expect(e.end, DateTime(2026, 11, 4));
    });

    test('весь день без DTEND и DURATION: один день', () {
      final cal = parseIcs(
        _event('DTSTART;VALUE=DATE:20261103'),
        local: moscow,
      );
      expect(cal.events.single.end, DateTime(2026, 11, 4));
    });

    test('DURATION с часами и минутами вместо DTEND', () {
      final cal = parseIcs(
        _event('DTSTART;TZID=Europe/Moscow:20261103T090000\r\nDURATION:PT1H30M'),
        local: moscow,
      );
      expect(cal.events.single.end, DateTime(2026, 11, 3, 10, 30));
    });

    test('DURATION в неделях и днях', () {
      final cal = parseIcs(
        _event('DTSTART;TZID=Europe/Moscow:20261103T090000\r\nDURATION:P1W2D'),
        local: moscow,
      );
      expect(cal.events.single.end, DateTime(2026, 11, 3 + 7 + 2, 9));
    });
  });
}
