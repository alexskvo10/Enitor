import 'package:enitor/core/utils/date_utils.dart';
import 'package:flutter_test/flutter_test.dart';

/// Календарные сдвиги: та же полночь через границы месяцев и года
/// (переход на летнее время на ПК не воспроизвести — Dart берёт пояс из ОС).
void main() {
  test('addDays держит время на часах и переходит границы', () {
    expect(addDays(DateTime(2026, 12, 31), 1), DateTime(2027, 1, 1));
    expect(addDays(DateTime(2026, 3, 1), -1), DateTime(2026, 2, 28));
    expect(addDays(DateTime(2026, 3, 29, 4), 1), DateTime(2026, 3, 30, 4));
  });

  test('calendarDaysBetween не смотрит на время', () {
    expect(
        calendarDaysBetween(
            DateTime(2026, 3, 28, 23), DateTime(2026, 3, 30, 1)),
        2);
    expect(
        calendarDaysBetween(DateTime(2026, 1, 1), DateTime(2025, 12, 31)), -1);
  });
}
