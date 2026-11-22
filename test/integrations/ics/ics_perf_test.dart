import 'package:enitor/features/integrations/ics/ics_parser.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

String _pad(int n) => n.toString().padLeft(2, '0');

void main() {
  tzdata.initializeTimeZones();

  final moscow = tz.getLocation('Europe/Moscow');

  group('производительность', () {
    test('5000 событий разбираются за пару секунд даже при полном прогоне', () {
      final b = StringBuffer('BEGIN:VCALENDAR\r\n');
      for (var i = 0; i < 5000; i++) {
        final day = _pad(1 + i % 28);
        final hour = _pad(i % 24);
        b.write(
          'BEGIN:VEVENT\r\n'
          'UID:perf-$i@test\r\n'
          'DTSTART;TZID=Europe/Moscow:202611${day}T${hour}0000\r\n'
          'DURATION:PT1H\r\n'
          'SUMMARY:Событие $i, номер\\, $i\r\n'
          '${i.isEven ? 'RRULE:FREQ=WEEKLY;COUNT=4\r\n' : ''}'
          'END:VEVENT\r\n',
        );
      }
      b.write('END:VCALENDAR\r\n');
      final text = b.toString();

      final sw = Stopwatch()..start();
      final cal = parseIcs(text, local: moscow);
      sw.stop();

      expect(cal.events.length, 5000);
      expect(cal.warnings, isEmpty);
      // Отдельно — около 0,4 с; при полном прогоне тесты идут параллельно и
      // делят процессор, поэтому запас. Ловит замедление в разы, а не шум.
      expect(sw.elapsed, lessThan(const Duration(seconds: 3)));
    });
  });
}
