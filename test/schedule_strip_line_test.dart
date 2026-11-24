import 'package:enitor/data/models/schedule_item.dart';
import 'package:enitor/features/today/today_screen.dart';
import 'package:enitor/l10n/app_localizations_ru.dart';
import 'package:flutter_test/flutter_test.dart';

ScheduleItem _item(String title, int start, [int? end]) => ScheduleItem(
      id: title,
      title: title,
      date: DateTime(2026, 11, 24),
      startMinutes: start,
      endMinutes: end,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

void main() {
  final l10n = AppLocalizationsRu();
  final day = DateTime(2026, 11, 24);
  final items = [
    _item('вдаь', 380, 600),
    _item('лаша', 540, 600),
    _item('уцка', 720, 780),
  ];

  test('сегодня: что идёт и что дальше', () {
    expect(
      scheduleStripLine(l10n, items, day, DateTime(2026, 11, 24, 9, 30)),
      'Расписание · 3 · сейчас: вдаь до 10:00 · дальше: уцка в 12:00',
    );
  });

  test('сегодня, всё прошло', () {
    expect(
      scheduleStripLine(l10n, items, day, DateTime(2026, 11, 24, 14)),
      'Расписание · 3 · всё прошло',
    );
  });

  test('другой день: от первого начала до последнего конца', () {
    expect(
      scheduleStripLine(l10n, items, day, DateTime(2026, 11, 23, 9)),
      'Расписание · 3 · 06:20–13:00',
    );
  });
}
