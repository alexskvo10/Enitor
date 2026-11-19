import 'package:enitor/data/models/recurrence_rule.dart';
import 'package:enitor/data/models/task.dart';
import 'package:enitor/features/integrations/import/formats/todoist.dart';
import 'package:enitor/features/integrations/import/imported_task.dart';
import 'package:flutter_test/flutter_test.dart';

const _header =
    'TYPE,CONTENT,DESCRIPTION,PRIORITY,INDENT,AUTHOR,RESPONSIBLE,DATE,DATE_LANG,TIMEZONE';

void main() {
  test('задача, заметка, раздел, подзадача и повтор', () {
    final csv = [
      _header,
      'meta,Todoist,,,,,,,,',
      'section,Работа,,,,,,,,',
      'task,Купить молоко,,1,1,,,2026-11-02,,',
      'note,Не забыть,,,,,,,,',
      'task,Отчёт,,4,1,,,every day,,',
      'task,Шаг,,,2,,,,,',
    ].join('\n');

    final result = parseTodoistCsv(csv);

    expect(result.warnings, isEmpty);
    expect(result.tasks, hasLength(2));

    final milk = result.tasks[0];
    expect(milk.title, 'Купить молоко');
    expect(milk.list, 'Работа');
    expect(milk.date, DateTime(2026, 11, 2));
    expect(milk.priority, TaskPriority.high);
    expect(milk.description, 'Не забыть');

    final report = result.tasks[1];
    expect(report.priority, TaskPriority.none);
    expect(report.repeat?.kind, RecurrenceKind.interval);
    expect(report.repeat?.intervalDays, 1);
    expect(report.subtasks, ['Шаг']);
  });

  test('повтор по дням недели распознаётся по-русски', () {
    final csv = [
      _header,
      'task,Зал,,,1,,,каждый понедельник и среда,,',
    ].join('\n');

    final task = parseTodoistCsv(csv).tasks.single;

    expect(task.repeat?.kind, RecurrenceKind.weekly);
    expect(task.repeat?.weekdays, [1, 3]);
  });

  test('дата со временем переводится в минуты с полуночи', () {
    final csv = [
      _header,
      'task,Звонок,,,1,,,2026-11-02 15:30,,',
    ].join('\n');

    final task = parseTodoistCsv(csv).tasks.single;

    expect(task.date, DateTime(2026, 11, 2));
    expect(task.startMinutes, 15 * 60 + 30);
  });

  test('несуществующая дата даёт предупреждение, задача остаётся', () {
    final csv = [
      _header,
      'task,Дата,,,1,,,2026-02-31,,',
    ].join('\n');

    final result = parseTodoistCsv(csv);

    expect(result.tasks.single.date, isNull);
    expect(result.warnings.single.reason, ImportSkipReason.unsupportedRow);
  });

  test('неизвестный TYPE пропускается с предупреждением', () {
    final csv = [
      _header,
      'filter,Фильтр,,,1,,,,,',
      'task,Задача,,,1,,,,,',
    ].join('\n');

    final result = parseTodoistCsv(csv);

    expect(result.tasks.map((t) => t.title), ['Задача']);
    expect(result.warnings, hasLength(1));
  });

  test('файл без заголовка Todoist не разбирается', () {
    final result = parseTodoistCsv('a,b\n1,2');

    expect(result.tasks, isEmpty);
    expect(result.warnings, hasLength(1));
  });

  test('одинаковые задачи в одном файле получают разные sourceId', () {
    final csv = [
      _header,
      'section,Работа,,,,,,,,',
      'task,Купить молоко,,4,1,,,,,',
      'task,Купить молоко,,4,1,,,,,',
      'section,Дом,,,,,,,,',
      'task,Купить молоко,,4,1,,,,,',
    ].join('\n');

    final ids = parseTodoistCsv(csv).tasks.map((t) => t.sourceId).toList();

    expect(ids.toSet(), hasLength(3));
  });

  test('одинаковые задачи из файлов двух проектов — разные sourceId', () {
    final csv = [_header, 'task,Купить молоко,,4,1,,,,,'].join('\n');
    String id(String project) =>
        parseTodoistCsv(csv, project: project).tasks.single.sourceId;

    expect(id('Работа.csv'), isNot(id('Дом.csv')));
    expect(id('Работа.csv'), id('Работа.csv'));
  });

  test('метки @label из названия становятся тегами', () {
    final r = parseTodoistCsv(
      'TYPE,CONTENT,DESCRIPTION,PRIORITY,INDENT,AUTHOR,RESPONSIBLE,DATE,'
      'DATE_LANG,TIMEZONE\n'
      'task,Купить молоко @дом @магазин,,4,1,,,,,\n'
      'task,@только_метка,,4,1,,,,,\n'
      'task,почта me@example.com,,4,1,,,,,\n',
    );
    expect(r.tasks[0].title, 'Купить молоко');
    expect(r.tasks[0].tags, ['дом', 'магазин']);
    expect(r.tasks[1].title, '@только_метка');
    expect(r.tasks[2].title, 'почта me@example.com');
    expect(r.tasks[2].tags, isEmpty);
  });
}
