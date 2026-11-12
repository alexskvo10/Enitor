import 'package:enitor/data/models/recurrence_rule.dart';
import 'package:enitor/data/repositories/backlog_repository.dart';
import 'package:enitor/data/repositories/recurrence_repository.dart';
import 'package:enitor/data/repositories/schedule_repository.dart';
import 'package:enitor/data/repositories/task_repository.dart';
import 'package:enitor/data/sources/local/local_storage.dart';
import 'package:enitor/features/integrations/ics/ics_export.dart';
import 'package:enitor/features/integrations/ics/ics_parser.dart';
import 'package:enitor/features/integrations/ics/ics_writer.dart';
import 'package:enitor/features/integrations/import/formats/google_tasks.dart';
import 'package:enitor/features/integrations/import/formats/ticktick.dart';
import 'package:enitor/features/integrations/import/formats/todoist.dart';
import 'package:enitor/features/integrations/import/import_plan.dart';
import 'package:enitor/features/integrations/import/imported_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

// Сквозные этапов 5 и 7: файл → план → импорт → данные на нужных днях;
// повторный импорт — обновляет, а не дублирует.

final _now = DateTime(2026, 10, 25, 12);

/// Расписание «вуза»: пара по пн и ср через неделю с исключением, лекция
/// каждую неделю по пт до конца семестра, разовая консультация, событие на
/// весь день и «второй вторник месяца» (Enitor такое не умеет).
const _uni = '''BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VEVENT
UID:phys-1@uni
SUMMARY:Физика
LOCATION:Ауд. 214
DTSTART;TZID=Europe/Moscow:20261026T090000
DTEND;TZID=Europe/Moscow:20261026T103000
RRULE:FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,WE;UNTIL=20261231T235959Z
EXDATE;TZID=Europe/Moscow:20261109T090000
END:VEVENT
BEGIN:VEVENT
UID:hist-1@uni
SUMMARY:История
DTSTART;TZID=Europe/Moscow:20261030T120000
DTEND;TZID=Europe/Moscow:20261030T133000
RRULE:FREQ=WEEKLY;COUNT=3
END:VEVENT
BEGIN:VEVENT
UID:cons@uni
SUMMARY:Консультация
DTSTART;TZID=Europe/Moscow:20261028T150000
END:VEVENT
BEGIN:VEVENT
UID:holiday@uni
SUMMARY:День здоровья
DTSTART;VALUE=DATE:20261104
END:VEVENT
BEGIN:VEVENT
UID:council@uni
SUMMARY:Учёный совет
DTSTART;TZID=Europe/Moscow:20261110T160000
RRULE:FREQ=MONTHLY;BYDAY=2TU
END:VEVENT
END:VCALENDAR
''';

void main() {
  late ProviderContainer container;
  late tz.Location moscow;

  setUpAll(() {
    tzdata.initializeTimeZones();
    moscow = tz.getLocation('Europe/Moscow');
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    container = ProviderContainer(
      overrides: [
        localStorageProvider.overrideWithValue(
          LocalStorage(await SharedPreferences.getInstance()),
        ),
      ],
    );
  });
  tearDown(() => container.dispose());

  ScheduleRepository schedule() => container.read(scheduleRepositoryProvider);

  Future<List<PlanEntry>> importIcs(String text) async {
    final plan = planIcsImport(
      parseIcs(text, local: moscow),
      schedule: schedule(),
      now: _now,
    );
    for (final e in plan) {
      await e.apply?.call();
    }
    return plan;
  }

  List<String> titlesOn(DateTime day) =>
      schedule().forDay(day).map((i) => i.title).toList();

  test('расписание вуза: пункты в нужные дни на трёх неделях', () async {
    final plan = await importIcs(_uni);
    final byTitle = {for (final e in plan) e.title: e};
    expect(byTitle['Физика']!.action, PlanAction.create);
    expect(byTitle['День здоровья']!.skip, PlanSkip.allDay);
    expect(byTitle['Учёный совет']!.skip, PlanSkip.unsupportedRepeat);

    // Неделя 1 (26.10): физика пн и ср, история пт, консультация ср.
    expect(titlesOn(DateTime(2026, 10, 26)), ['Физика']);
    expect(titlesOn(DateTime(2026, 10, 28)), containsAll(['Физика', 'Консультация']));
    expect(titlesOn(DateTime(2026, 10, 30)), ['История']);
    // Неделя 2 (2.11): «через неделю» — физики нет.
    expect(titlesOn(DateTime(2026, 11, 2)), isEmpty);
    expect(titlesOn(DateTime(2026, 11, 6)), ['История']);
    // Неделя 3 (9.11): пн — исключение, ср — есть; история — третья и последняя.
    expect(titlesOn(DateTime(2026, 11, 9)), isEmpty);
    expect(titlesOn(DateTime(2026, 11, 11)), ['Физика']);
    expect(titlesOn(DateTime(2026, 11, 13)), ['История']);
    expect(titlesOn(DateTime(2026, 11, 20)), isEmpty);

    final phys = schedule().all.firstWhere((i) => i.title == 'Физика');
    expect(phys.location, 'Ауд. 214');
    expect(phys.startMinutes, 9 * 60);
    expect(phys.endMinutes, 10 * 60 + 30);
    expect(phys.weekInterval, 2);
    expect(phys.weekdays, [1, 3]);
  });

  test('повторный импорт изменённого файла — обновлено, не задублировано',
      () async {
    await importIcs(_uni);
    final count = schedule().all.length;
    final again = await importIcs(_uni);
    expect(again.where((e) => e.action != PlanAction.skip), isEmpty);
    expect(
      again.where((e) => e.skip == PlanSkip.unchanged).length,
      count,
    );
    final changed = _uni.replaceFirst('Ауд. 214', 'Ауд. 301');
    final plan = await importIcs(changed);
    expect(
      plan.singleWhere((e) => e.title == 'Физика').action,
      PlanAction.update,
    );
    expect(schedule().all.length, count);
    expect(
      schedule().all.firstWhere((i) => i.title == 'Физика').location,
      'Ауд. 301',
    );
  });

  test('прошедшие события пропускаются', () async {
    final plan = await importIcs('''BEGIN:VCALENDAR
BEGIN:VEVENT
UID:old
SUMMARY:Старое
DTSTART:20250101T100000
END:VEVENT
END:VCALENDAR''');
    expect(plan.single.skip, PlanSkip.past);
    expect(schedule().all, isEmpty);
  });

  test('экспорт → наш импорт даёт те же пункты', () async {
    await importIcs(_uni);
    final before = {
      for (final i in schedule().all)
        i.title: (i.startMinutes, i.endMinutes, '${i.weekdays}', i.weekInterval),
    };
    final text = writeIcs(
      buildIcsExport(
        schedule: schedule().all,
        rules: const [],
        tasks: const [],
        now: _now,
      ),
      zone: moscow,
      now: _now,
    );
    SharedPreferences.setMockInitialValues({});
    final fresh = ProviderContainer(
      overrides: [
        localStorageProvider.overrideWithValue(
          LocalStorage(await SharedPreferences.getInstance()),
        ),
      ],
    );
    addTearDown(fresh.dispose);
    final plan = planIcsImport(
      parseIcs(text, local: moscow),
      schedule: fresh.read(scheduleRepositoryProvider),
      now: _now,
    );
    for (final e in plan) {
      await e.apply?.call();
    }
    final after = {
      for (final i in fresh.read(scheduleRepositoryProvider).all)
        i.title: (i.startMinutes, i.endMinutes, '${i.weekdays}', i.weekInterval),
    };
    expect(after, before);
    final phys = fresh
        .read(scheduleRepositoryProvider)
        .all
        .firstWhere((i) => i.title == 'Физика');
    expect(phys.exceptDates, [DateTime(2026, 11, 9)]);
  });

  group('задачи из других приложений', () {
    Future<List<PlanEntry>> run(List<PlanEntry> plan) async {
      for (final e in plan) {
        await e.apply?.call();
      }
      return plan;
    }

    List<PlanEntry> plan(ImportResult result) => planTaskImport(
          result,
          tasks: container.read(taskRepositoryProvider),
          rules: container.read(recurrenceRepositoryProvider),
          backlog: container.read(backlogRepositoryProvider),
          now: _now,
        );

    test('Todoist: даты, повторы, задачи без даты — в бэклог; без дублей',
        () async {
      const csv = 'TYPE,CONTENT,DESCRIPTION,PRIORITY,INDENT,AUTHOR,'
          'RESPONSIBLE,DATE,DATE_LANG,TIMEZONE\n'
          'task,Отчёт,,1,1,,,2026-10-27,en,\n'
          'task,Вода,,4,1,,,every day,en,\n'
          'task,Когда-нибудь,,4,1,,,,en,\n';
      await run(plan(parseTodoistCsv(csv)));
      final tasks = container.read(taskRepositoryProvider);
      expect(
        tasks.tasksForDay(DateTime(2026, 10, 27)).map((t) => t.title),
        contains('Отчёт'),
      );
      expect(
        container.read(recurrenceRepositoryProvider).all.single.kind,
        RecurrenceKind.interval,
      );
      expect(
        container.read(backlogRepositoryProvider).all.single.title,
        'Когда-нибудь',
      );
      final again = await run(plan(parseTodoistCsv(csv)));
      expect(again.every((e) => e.skip == PlanSkip.alreadyImported), isTrue);
      expect(container.read(backlogRepositoryProvider).all.length, 1);
    });

    test('Google Задачи и TickTick разбираются в план', () async {
      const google = '{"kind":"tasks#taskLists","items":[{"kind":'
          '"tasks#taskList","id":"l1","title":"Личное","items":[{"kind":'
          '"tasks#task","id":"t1","title":"Купить хлеб","status":'
          '"needsAction","due":"2026-10-28T00:00:00.000Z"}]}]}';
      final g = await run(plan(parseGoogleTasksJson(google)));
      expect(g.single.action, PlanAction.create);
      expect(
        container
            .read(taskRepositoryProvider)
            .tasksForDay(DateTime(2026, 10, 28))
            .single
            .title,
        'Купить хлеб',
      );
      const tick = '"Date: 2026-10-25"\n"Version: 7.1"\n'
          '"Folder Name","List Name","Title","Kind","Tags","Content",'
          '"Is Check list","Start Date","Due Date","Reminder","Repeat",'
          '"Priority","Status","Created Time","Completed Time","Order",'
          '"Timezone","Is All Day","Is Floating","Column Name","Column Order",'
          '"View Mode","taskId","parentId"\n'
          '"","Inbox","Позвонить","TEXT","","","N","","2026-10-29T00:00:00+0000",'
          '"","","5","0","","","0","Europe/Moscow","true","false","","","list",'
          '"tt1",""\n';
      final t = await run(plan(parseTickTickCsv(tick)));
      expect(t.where((e) => e.action == PlanAction.create).length, 1);
    });
  });
}
