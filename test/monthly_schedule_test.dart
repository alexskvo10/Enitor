import 'package:flutter_test/flutter_test.dart';
import 'package:enitor/services/notification_service.dart';

// Напоминание о бэклоге целей приходит 1-го числа в 11:00. Месячного повтора
// у плагина нет, вхождения считаются руками — а значит переход через декабрь
// и короткий февраль надо проверять, иначе уведомление тихо не придёт.

void main() {
  List<DateTime> next(DateTime from, {int day = 1, int minutes = 11 * 60}) =>
      monthlyOccurrencesAfter(
        from,
        dayOfMonth: day,
        minutesOfDay: minutes,
        count: 4,
      );

  test('середина месяца — начинаем со следующего первого числа', () {
    expect(next(DateTime(2026, 3, 15, 9)), [
      DateTime(2026, 4, 1, 11),
      DateTime(2026, 5, 1, 11),
      DateTime(2026, 6, 1, 11),
      DateTime(2026, 7, 1, 11),
    ]);
  });

  test('первое число до назначенного часа — сегодняшнее вхождение считается',
      () {
    expect(next(DateTime(2026, 3, 1, 10, 59)).first, DateTime(2026, 3, 1, 11));
  });

  test('первое число после назначенного часа — уже пропущено', () {
    expect(next(DateTime(2026, 3, 1, 11, 1)).first, DateTime(2026, 4, 1, 11));
  });

  test('переход через декабрь — год увеличивается', () {
    expect(next(DateTime(2026, 11, 5, 8)), [
      DateTime(2026, 12, 1, 11),
      DateTime(2027, 1, 1, 11),
      DateTime(2027, 2, 1, 11),
      DateTime(2027, 3, 1, 11),
    ]);
  });

  test('31-е число зажимается по длине месяца, а не перетекает вперёд', () {
    final res = next(DateTime(2027, 1, 1), day: 31);
    expect(res[0], DateTime(2027, 1, 31, 11));
    expect(res[1], DateTime(2027, 2, 28, 11)); // не 3 марта
    expect(res[2], DateTime(2027, 3, 31, 11));
    expect(res[3], DateTime(2027, 4, 30, 11));
  });

  test('високосный февраль — 29-е', () {
    expect(next(DateTime(2028, 2, 1), day: 31)[0], DateTime(2028, 2, 29, 11));
  });

  test('всегда ровно count вхождений и все строго в будущем', () {
    final from = DateTime(2026, 12, 31, 23, 59);
    final res = next(from);
    expect(res.length, 4);
    expect(res.every((d) => d.isAfter(from)), isTrue);
  });
}
