import 'package:enitor/data/models/recurrence_rule.dart';
import 'package:enitor/data/models/schedule_template.dart';
import 'package:enitor/data/repositories/schedule_repository.dart';
import 'package:enitor/data/repositories/schedule_template_repository.dart';
import 'package:enitor/data/sources/local/local_storage.dart';
import 'package:enitor/features/templates/templates_sheet.dart';
import 'package:enitor/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Шаблоны расписания: сохранить день, применить на другой день.
void main() {
  final now = DateTime.now();
  final monday = DateTime(now.year, now.month, now.day + 8 - now.weekday);
  final nextMonday = DateTime(monday.year, monday.month, monday.day + 7);
  final tuesday = DateTime(monday.year, monday.month, monday.day + 1);

  Future<ProviderContainer> container() async {
    SharedPreferences.setMockInitialValues({});
    final storage = LocalStorage(await SharedPreferences.getInstance());
    final c = ProviderContainer(
      overrides: [localStorageProvider.overrideWithValue(storage)],
    );
    addTearDown(c.dispose);
    return c;
  }

  testWidgets('сохранить день шаблоном и применить на другой день',
      (tester) async {
    final c = await container();
    final schedule = c.read(scheduleRepositoryProvider);
    await schedule.create(
      title: 'Матанализ',
      date: monday,
      startMinutes: 9 * 60,
      endMinutes: 10 * 60 + 30,
      location: 'Ауд. 214',
      colorIndex: 2,
      reminderMinutes: 10,
      repeat: RecurrenceKind.weekly,
      weekdays: const [DateTime.monday],
    );
    await schedule.create(
      title: 'Английский',
      date: monday,
      startMinutes: 11 * 60,
    );

    Future<void> openSheet(DateTime day) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            key: ValueKey(day),
            locale: const Locale('ru'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Builder(
              builder: (ctx) => TextButton(
                onPressed: () => showScheduleTemplatesSheet(
                  ctx,
                  date: day,
                  isPast: false,
                  dayItems: schedule.forDay(day),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    await openSheet(monday);
    await tester.tap(find.textContaining('Сохранить этот день'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Учебный день');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    final tpl = c.read(scheduleTemplateRepositoryProvider);
    final saved = (await tpl.watchTemplates().first).single;
    expect(saved.name, 'Учебный день');
    expect(saved.items.map((i) => i.title), ['Матанализ', 'Английский']);
    expect(find.text('Учебный день'), findsOneWidget);
    expect(find.text('2 пункта'), findsOneWidget);

    // Применяем на вторник: пункты разовые, со временем, местом и цветом.
    await openSheet(tuesday);
    await tester.tap(find.text('Учебный день'));
    await tester.pumpAndSettle();
    final day = schedule.forDay(tuesday);
    expect(day.map((i) => i.title), ['Матанализ', 'Английский']);
    final math = day.first;
    expect(math.isSeries, isFalse);
    expect(math.endMinutes, 10 * 60 + 30);
    expect(math.location, 'Ауд. 214');
    expect(math.colorIndex, 2);
    expect(math.reminderMinutes, 10);
    // Шаблон не продлил серию на другие дни.
    expect(schedule.forDay(nextMonday).map((i) => i.title), ['Матанализ']);
  });

  test('повторное применение не дублирует пункты', () async {
    final c = await container();
    final schedule = c.read(scheduleRepositoryProvider);
    final tpl = c.read(scheduleTemplateRepositoryProvider);
    await schedule.create(title: 'Смена', date: monday, startMinutes: 480);
    await tpl.add(
      'Смена',
      schedule.forDay(monday).map(ScheduleTemplateItem.fromItem).toList(),
    );
    final items = (await tpl.watchTemplates().first).single.items;

    expect(await schedule.applyTemplate(items, tuesday), 1);
    expect(await schedule.applyTemplate(items, tuesday), 0);
    expect(schedule.forDay(tuesday), hasLength(1));
  });
}
