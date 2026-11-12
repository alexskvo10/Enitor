import 'dart:convert';

import 'package:enitor/features/integrations/import/formats/google_tasks.dart';
import 'package:enitor/features/integrations/import/imported_task.dart';
import 'package:flutter_test/flutter_test.dart';

String _json(Object value) => jsonEncode(value);

void main() {
  test('список с задачами, подзадача и выполненная задача', () {
    final json = _json({
      'items': [
        {
          'title': 'Работа',
          'items': [
            {
              'id': 'a',
              'title': 'Отчёт',
              'due': '2026-11-02T00:00:00.000Z',
              'status': 'needsAction',
              'notes': 'черновик',
            },
            {
              'id': 'b',
              'title': 'Шаг',
              'parent': 'a',
              'status': 'needsAction',
            },
            {
              'id': 'c',
              'title': 'Удалённая',
              'deleted': true,
            },
            {
              'id': 'd',
              'title': 'Готово',
              'status': 'completed',
              'completed': '2026-10-20T10:00:00.000Z',
            },
          ],
        },
      ],
    });

    final result = parseGoogleTasksJson(json);

    expect(result.warnings, isEmpty);
    expect(result.tasks, hasLength(2));

    final report = result.tasks[0];
    expect(report.title, 'Отчёт');
    expect(report.list, 'Работа');
    expect(report.date, DateTime(2026, 11, 2));
    expect(report.description, 'черновик');
    expect(report.subtasks, ['Шаг']);

    final done = result.tasks[1];
    expect(done.completed, isTrue);
    expect(done.completedAt, isNotNull);
  });

  test('корень-массив списков тоже принимается', () {
    final json = _json([
      {
        'title': 'Дом',
        'items': [
          {'id': 'x', 'title': 'Пылесос'},
        ],
      },
    ]);

    final result = parseGoogleTasksJson(json);

    expect(result.tasks.single.title, 'Пылесос');
    expect(result.tasks.single.list, 'Дом');
  });

  test('битая дата срока даёт предупреждение, задача остаётся', () {
    final json = _json({
      'items': [
        {
          'title': 'Список',
          'items': [
            {
              'id': 'x',
              'title': 'Срок',
              'due': '2026-02-31T00:00:00.000Z',
            },
          ],
        },
      ],
    });

    final result = parseGoogleTasksJson(json);

    expect(result.tasks.single.date, isNull);
    expect(result.warnings.single.reason, ImportSkipReason.unsupportedRow);
  });

  test('не JSON и пустой файл не бросают исключение', () {
    expect(parseGoogleTasksJson('{плохо').tasks, isEmpty);
    expect(parseGoogleTasksJson('   ').tasks, isEmpty);
    expect(parseGoogleTasksJson('{"other": 1}').tasks, isEmpty);
  });
}
