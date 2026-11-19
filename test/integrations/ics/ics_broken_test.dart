import 'package:enitor/features/integrations/ics/ics_parser.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

void main() {
  tzdata.initializeTimeZones();

  final moscow = tz.getLocation('Europe/Moscow');

  group('битые файлы', () {
    test('пустая строка: пустой список и предупреждение', () {
      late IcsCalendar cal;
      expect(() => cal = parseIcs('', local: moscow), returnsNormally);
      expect(cal.events, isEmpty);
      expect(cal.warnings, isNotEmpty);
    });

    test('мусор: пустой список и предупреждение', () {
      final cal = parseIcs('\u0000\u0001 %%% ###\nнет структуры\n', local: moscow);
      expect(cal.events, isEmpty);
      expect(cal.warnings, isNotEmpty);
    });

    test('VEVENT без DTSTART пропускается, остальные события целы', () {
      final cal = parseIcs(
        'BEGIN:VCALENDAR\r\n'
        'BEGIN:VEVENT\r\nUID:bad\r\nSUMMARY:Без даты\r\nEND:VEVENT\r\n'
        'BEGIN:VEVENT\r\nUID:good\r\nDTSTART:20261103T090000\r\nEND:VEVENT\r\n'
        'END:VCALENDAR\r\n',
        local: moscow,
      );
      expect(cal.events.map((e) => e.uid), ['good']);
      expect(cal.warnings.single, contains('без DTSTART'));
    });

    test('неверная дата (месяц 13) пропускается с предупреждением', () {
      final cal = parseIcs(
        'BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nUID:m13\r\n'
        'DTSTART:20261345T090000\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n',
        local: moscow,
      );
      expect(cal.events, isEmpty);
      expect(cal.warnings.single, contains('неверная дата'));
    });

    test('несуществующий день (30 февраля) и час 25 — не исключения', () {
      final cal = parseIcs(
        'BEGIN:VCALENDAR\r\n'
        'BEGIN:VEVENT\r\nUID:feb\r\nDTSTART:20260230T100000\r\nEND:VEVENT\r\n'
        'BEGIN:VEVENT\r\nUID:h25\r\nDTSTART:20261230T250000\r\nEND:VEVENT\r\n'
        'END:VCALENDAR\r\n',
        local: moscow,
      );
      expect(cal.events, isEmpty);
      expect(cal.warnings.length, 2);
    });

    test('неверный DTEND пропускает событие с предупреждением', () {
      final cal = parseIcs(
        'BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nUID:e\r\n'
        'DTSTART:20261103T090000\r\nDTEND:xxxx\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n',
        local: moscow,
      );
      expect(cal.events, isEmpty);
      expect(cal.warnings, isNotEmpty);
    });

    test('нет BEGIN:VCALENDAR: события не читаются, предупреждение', () {
      final cal = parseIcs(
        'BEGIN:VEVENT\r\nUID:x\r\nDTSTART:20261103T090000\r\nEND:VEVENT\r\n',
        local: moscow,
      );
      expect(cal.events, isEmpty);
      expect(cal.warnings.single, contains('BEGIN:VCALENDAR'));
    });

    test('незакрытый VCALENDAR: события всё равно читаются', () {
      final cal = parseIcs(
        'BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nUID:open\r\n'
        'DTSTART:20261103T090000\r\nEND:VEVENT\r\n',
        local: moscow,
      );
      expect(cal.events.single.uid, 'open');
    });

    test('CANCELLED пропускается без предупреждения', () {
      final cal = parseIcs(
        'BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nUID:c\r\n'
        'DTSTART:20261103T090000\r\nSTATUS:CANCELLED\r\nEND:VEVENT\r\n'
        'END:VCALENDAR\r\n',
        local: moscow,
      );
      expect(cal.events, isEmpty);
      expect(cal.warnings, isEmpty);
    });

    test('битый RRULE без FREQ: событие остаётся без правила', () {
      final cal = parseIcs(
        'BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nUID:r\r\n'
        'DTSTART:20261103T090000\r\nRRULE:INTERVAL=2\r\nEND:VEVENT\r\n'
        'END:VCALENDAR\r\n',
        local: moscow,
      );
      expect(cal.events.single.rule, isNull);
      expect(cal.warnings.single, contains('FREQ'));
    });

    test('событие без UID получает стабильный uid из summary и начала', () {
      const text =
          'BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nSUMMARY:Без UID\r\n'
          'DTSTART:20261103T090000\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n';
      final a = parseIcs(text, local: moscow).events.single.uid;
      final b = parseIcs(text, local: moscow).events.single.uid;
      expect(a, isNotEmpty);
      expect(a, b);
      expect(a, matches(RegExp(r'^[0-9a-f]{16}$')));
    });
  });

  group('мелочи разбора', () {
    String one(String body) => 'BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\n'
        '${body}END:VEVENT\r\nEND:VCALENDAR\r\n';

    test('огромная DURATION не роняет разбор', () {
      final cal = parseIcs(
        one('UID:d\r\nDTSTART:20261103T090000\r\n'
            'DURATION:PT99999999999999999999H\r\n'),
        local: moscow,
      );
      expect(cal.events.single.end, isNull);
      expect(cal.warnings.single, contains('DURATION'));
    });

    test('COUNT=0 — не бесконечная серия', () {
      final cal = parseIcs(
        one('UID:c\r\nDTSTART:20261103T090000\r\n'
            'RRULE:FREQ=DAILY;COUNT=0\r\n'),
        local: moscow,
      );
      expect(cal.events.single.rule?.count, 1);
      expect(cal.warnings, isNotEmpty);
    });

    test('UNTIL без времени — конец дня по местному времени', () {
      final ny = tz.getLocation('America/New_York');
      final cal = parseIcs(
        one('UID:u\r\nDTSTART:20261103T230000Z\r\n'
            'RRULE:FREQ=DAILY;UNTIL=20261110\r\n'),
        local: ny,
      );
      expect(cal.events.single.rule?.until, DateTime(2026, 11, 10, 23, 59, 59));
    });

    test('предупреждения по-английски для английского интерфейса', () {
      final cal = parseIcs(
        one('UID:e\r\nSUMMARY:x\r\n'),
        local: moscow,
        ru: false,
      );
      expect(cal.warnings.single, 'Event "x" skipped: no DTSTART');
    });

    test('событие без UID: id не зависит от пояса устройства', () {
      const text = 'BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\n'
          'SUMMARY:x\r\nDTSTART:20261103T090000Z\r\n'
          'END:VEVENT\r\nEND:VCALENDAR\r\n';
      final a = parseIcs(text, local: moscow).events.single.uid;
      final b = parseIcs(text, local: tz.getLocation('Asia/Tokyo'))
          .events
          .single
          .uid;
      expect(a, b);
    });
  });
}
