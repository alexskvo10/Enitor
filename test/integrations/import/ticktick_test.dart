import 'package:enitor/data/models/recurrence_rule.dart';
import 'package:enitor/data/models/task.dart';
import 'package:enitor/features/integrations/import/formats/ticktick.dart';
import 'package:enitor/features/integrations/import/imported_task.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tzdata;

const _header =
    'List Name,Title,Kind,Tags,Content,Is Check list,Due Date,Is All Day,'
    'Repeat,Priority,Status,Completed Time,Timezone,taskId,parentId';

void main() {
  setUpAll(tzdata.initializeTimeZones);

  test('строки метаданных до заголовка пропускаются, срок переводится в зону',
      () {
    final csv = [
      'Date: 2026-10-25',
      'Version: 6',
      _header,
      // Срок 12:00 UTC = 15:00 по Москве (UTC+3, без перехода на летнее время).
      'Входящие,Звонок,TEXT,"важное,срочное",Позвонить Ивану,,'
          '2026-11-02T12:00:00+0000,false,,5,0,,Europe/Moscow,t1,',
      'Входящие,Подзадача,TEXT,,,,,,,0,0,,,t3,t1',
    ].join('\n');

    final result = parseTickTickCsv(csv);

    expect(result.warnings, isEmpty);
    expect(result.tasks, hasLength(1));

    final call = result.tasks.single;
    expect(call.title, 'Звонок');
    expect(call.date, DateTime(2026, 11, 2));
    expect(call.startMinutes, 15 * 60);
    expect(call.priority, TaskPriority.high);
    expect(call.tags, ['важное', 'срочное']);
    expect(call.description, 'Позвонить Ивану');
    expect(call.subtasks, ['Подзадача']);
  });

  test('чек-лист превращается в подзадачи без описания', () {
    final csv = [
      _header,
      'Работа,Чек,CHECKLIST,,"▫ первый\n▪ второй",true,,,,0,0,,,t2,',
    ].join('\n');

    final task = parseTickTickCsv(csv).tasks.single;

    expect(task.description, isNull);
    expect(task.subtasks, ['первый', 'второй']);
  });

  test('RRULE WEEKLY переводится в повтор по дням недели', () {
    final csv = [
      _header,
      'Входящие,Полив,TEXT,,,,,,"RRULE:FREQ=WEEKLY;BYDAY=MO,WE",0,0,,,t4,',
    ].join('\n');

    final task = parseTickTickCsv(csv).tasks.single;

    expect(task.repeat?.kind, RecurrenceKind.weekly);
    expect(task.repeat?.weekdays, [1, 3]);
  });

  test('неподдерживаемый RRULE даёт предупреждение, задача остаётся', () {
    final csv = [
      _header,
      'Входящие,Редко,TEXT,,,,,,"RRULE:FREQ=WEEKLY;INTERVAL=2;BYDAY=MO",0,0,,,t5,',
    ].join('\n');

    final result = parseTickTickCsv(csv);

    expect(result.tasks.single.repeat, isNull);
    expect(result.warnings.single.reason, ImportSkipReason.unsupportedRepeat);
  });

  test('без заголовка TickTick файл не разбирается', () {
    final result = parseTickTickCsv('x,y\n1,2');

    expect(result.tasks, isEmpty);
    expect(result.warnings, hasLength(1));
  });
}
