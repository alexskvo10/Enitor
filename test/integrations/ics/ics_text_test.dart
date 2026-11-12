import 'package:enitor/features/integrations/ics/ics_parser.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Оборачивает свойства в минимальный календарь.
String _cal(String body) =>
    'BEGIN:VCALENDAR\r\nVERSION:2.0\r\nBEGIN:VEVENT\r\n'
    '$body\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n';

void main() {
  tzdata.initializeTimeZones();

  final moscow = tz.getLocation('Europe/Moscow');

  group('развёртка, экранирование, юникод', () {
    test('продолжение строки пробелом или табом, CRLF', () {
      const text =
          'BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\n'
          'UID:u1\r\n'
          'DTSTART:20261103T090000\r\n'
          'SUMMARY:Очень длин\r\n'
          ' ное название\r\n'
          '\t продолжение\r\n'
          'END:VEVENT\r\nEND:VCALENDAR\r\n';
      final cal = parseIcs(text, local: moscow);
      expect(cal.events.single.summary, 'Очень длинное название продолжение');
    });

    test('LF вместо CRLF и пустые строки', () {
      const text =
          'BEGIN:VCALENDAR\n\nBEGIN:VEVENT\nUID:u2\n'
          'DTSTART:20261103T090000\nSUMMARY:Раз\n два\n\n'
          'END:VEVENT\nEND:VCALENDAR\n';
      final cal = parseIcs(text, local: moscow);
      expect(cal.events.single.summary, 'Раздва');
    });

    test('экранирование: запятая, точка с запятой, обратный слэш, перенос', () {
      final cal = parseIcs(
        _cal(
          r'UID:u3'
          '\r\n'
          r'DTSTART:20261103T090000'
          '\r\n'
          r'SUMMARY:Пять\, шесть\; семь\\ восемь\nдевять\Nдесять',
        ),
        local: moscow,
      );
      expect(
        cal.events.single.summary,
        'Пять, шесть; семь\\ восемь\nдевять\nдесять',
      );
    });

    test('кириллица и эмодзи в значениях и в развёрнутой строке', () {
      final cal = parseIcs(
        _cal(
          'UID:u4\r\nDTSTART:20261103T090000\r\n'
          'SUMMARY:🎓🎓 Экзамен\r\n'
          ' по истории 📚\r\n'
          'LOCATION:Ёлки-Палки\\, ауд. 5',
        ),
        local: moscow,
      );
      final e = cal.events.single;
      // RFC 5545: при развёртке снимается один пробел продолжения.
      expect(e.summary, '🎓🎓 Экзаменпо истории 📚');
      expect(e.location, 'Ёлки-Палки, ауд. 5');
    });

    test('строка, разрезанная внутри эмодзи, склеивается без порчи', () {
      // Перенос сделан между строками String, поэтому символ цел.
      final cal = parseIcs(
        _cal('UID:u5\r\nDTSTART:20261103T090000\r\nSUMMARY:🎓\r\n 🎓🎓'),
        local: moscow,
      );
      expect(cal.events.single.summary, '🎓🎓🎓');
    });

    test('параметры: кавычки, двоеточие и точка с запятой внутри кавычек', () {
      final cal = parseIcs(
        _cal(
          'UID:u6\r\n'
          'DTSTART;TZID="Europe/Moscow":20261103T090000\r\n'
          'SUMMARY:Тест: "кавычки"; точка\r\n'
          'LOCATION;X-NOTE="a:b;c":Зал',
        ),
        local: moscow,
      );
      final e = cal.events.single;
      expect(e.start, DateTime(2026, 11, 3, 9));
      expect(e.summary, 'Тест: "кавычки"; точка');
      expect(e.location, 'Зал');
    });

    test('VALARM внутри VEVENT не подменяет свойства события', () {
      final cal = parseIcs(
        'BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\n'
        'UID:u7\r\nDTSTART:20261103T090000\r\nSUMMARY:Событие\r\n'
        'BEGIN:VALARM\r\nDESCRIPTION:Напоминание\r\nSUMMARY:Чужое\r\n'
        'END:VALARM\r\nEND:VEVENT\r\n'
        'BEGIN:VTODO\r\nUID:todo\r\nSUMMARY:Задача\r\nEND:VTODO\r\n'
        'END:VCALENDAR\r\n',
        local: moscow,
      );
      expect(cal.events.length, 1);
      final e = cal.events.single;
      expect(e.summary, 'Событие');
      expect(e.description, isNull);
    });

    test('VEVENT вне VCALENDAR не попадает в список', () {
      final cal = parseIcs(
        'BEGIN:VCALENDAR\r\nBEGIN:VTIMEZONE\r\nTZID:X\r\n'
        'BEGIN:VEVENT\r\nUID:x\r\nDTSTART:20261103T090000\r\nEND:VEVENT\r\n'
        'END:VTIMEZONE\r\nEND:VCALENDAR\r\n',
        local: moscow,
      );
      expect(cal.events, isEmpty);
    });
  });
}
