import 'dart:convert';
import 'dart:io';

import 'package:enitor/data/models/backlog_item.dart';
import 'package:enitor/data/models/day_template.dart';
import 'package:enitor/data/models/goal.dart';
import 'package:enitor/data/models/recurrence_rule.dart';
import 'package:enitor/data/models/schedule_template.dart';
import 'package:enitor/data/models/task.dart';
import 'package:enitor/data/repositories/backlog_repository.dart';
import 'package:enitor/data/repositories/goal_repository.dart';
import 'package:enitor/data/repositories/rating_repository.dart';
import 'package:enitor/data/repositories/schedule_repository.dart';
import 'package:enitor/data/repositories/schedule_template_repository.dart';
import 'package:enitor/data/repositories/task_repository.dart';
import 'package:enitor/data/repositories/template_repository.dart';
import 'package:enitor/data/sources/local/local_storage.dart';
import 'package:enitor/features/integrations/export/full_export.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:json_schema/json_schema.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Полный экспорт через настоящие репозитории проходит export.schema.json, и
// каждое поле toJson() каждой модели описано в схеме (и наоборот).

final _now = DateTime(2026, 10, 25, 12);
final _day = DateTime(2026, 10, 25);

Map<String, dynamic> _readSchema() =>
    jsonDecode(File('docs/integrations/schema/export.schema.json').readAsStringSync())
        as Map<String, dynamic>;

List<String> _problems(JsonSchema schema, Object? instance) => [
      for (final e in schema.validate(instance).errors) e.toString(),
    ];

/// Данные во всех разделах экспорта. Возвращает toJson() образцов моделей.
/// Все ключи toJson() пишутся всегда (null, если пусто), поэтому набор ключей
/// образца не зависит от того, какие поля заполнены.
Future<Map<String, Map<String, dynamic>>> _seed(ProviderContainer c) async {
  final tasks = c.read(taskRepositoryProvider);
  final goals = c.read(goalRepositoryProvider);
  final schedule = c.read(scheduleRepositoryProvider);
  final ratings = c.read(ratingRepositoryProvider);

  await tasks.createAndAdd(title: 'Обычная', date: _day);
  final timed = await tasks.createAndAdd(
    title: 'Со временем',
    date: _day,
    description: 'Описание',
    startMinutes: 540,
    endMinutes: 630,
    estimatedMinutes: 90,
    priority: TaskPriority.high,
    tags: const ['work'],
  );
  await tasks.createAndAdd(title: 'Счётчик', date: _day, targetCount: 5);
  final checklist = await tasks.createAndAdd(
    title: 'Чек-лист',
    date: _day,
    subtaskTitles: const ['Шаг 1', 'Шаг 2'],
  );
  final rule = await tasks.createRecurrence(
    title: 'Повторяющаяся',
    kind: RecurrenceKind.weekly,
    startDate: _day,
    weekdays: const [1, 3],
    startMinutes: 480,
    endMinutes: 510,
    priority: TaskPriority.low,
    tags: const ['home'],
    subtaskTitles: const ['Пункт'],
  );
  await tasks.ensureRecurrencesForDay(_day);

  final goal = await goals.addGoal(
    title: 'Прочитать книги',
    period: GoalPeriod.year,
    year: 2026,
    description: 'Описание',
    targetCount: 12,
    priority: TaskPriority.medium,
    tags: const ['reading'],
  );
  await goals.setGoalProgress(goal, 3);

  final item = await schedule.create(
    title: 'Физика',
    date: _day,
    startMinutes: 540,
    endMinutes: 630,
    location: 'Аудитория 214',
    note: 'Тетрадь',
    colorIndex: 2,
    repeat: RecurrenceKind.weekly,
    weekdays: const [2],
    endDate: DateTime(2026, 12, 31),
    reminderMinutes: 15,
  );

  final templates = c.read(templateRepositoryProvider);
  await templates.add('Утро', [
    const TemplateItem(
      title: 'Зарядка',
      startMinutes: 420,
      endMinutes: 435,
      estimatedMinutes: 15,
      subtaskTitles: ['Растяжка'],
      priority: TaskPriority.low,
      tags: ['health'],
    ),
  ]);
  final template = (await templates.watchTemplates().first).single;

  final scheduleTemplates = c.read(scheduleTemplateRepositoryProvider);
  await scheduleTemplates.add('Учебный день', [
    ScheduleTemplateItem.fromItem(item),
  ]);
  final scheduleTemplate =
      (await scheduleTemplates.watchTemplates().first).single;

  final backlogItem = BacklogItem(
    id: 'backlog-1',
    title: 'Вернуться к задаче',
    originalDate: _day,
    addedAt: _now,
    description: 'Описание',
    startMinutes: 600,
    endMinutes: 630,
    estimatedMinutes: 30,
    targetCount: 3,
    progressCount: 1,
    subtaskTitles: const ['Пункт'],
    priority: TaskPriority.high,
    tags: const ['later'],
  );
  await c.read(backlogRepositoryProvider).add(backlogItem);

  final goalBacklogItem = GoalBacklogItem(
    id: 'goal-backlog-1',
    title: 'Цель месяца',
    period: GoalPeriod.month,
    originalRef: const GoalPeriodRef(period: GoalPeriod.month, year: 2026, month: 10),
    addedAt: _now,
    description: 'Описание',
    targetCount: 4,
    progressCount: 2,
    subtaskTitles: const ['Пункт'],
  );
  await c.read(goalBacklogRepositoryProvider).add(goalBacklogItem);

  await ratings.setDayRating(_day, 8);
  await ratings.setPeriodRating('y-2026', 7);

  return {
    'Task': timed.toJson(),
    'SubTask': checklist.subtasks.first.toJson(),
    'Goal': goal.toJson(),
    'ScheduleItem': item.toJson(),
    'RecurrenceRule': rule.toJson(),
    'DayTemplate': template.toJson(),
    'TemplateItem': template.items.first.toJson(),
    'ScheduleTemplate': scheduleTemplate.toJson(),
    'ScheduleTemplateItem': scheduleTemplate.items.first.toJson(),
    'BacklogItem': backlogItem.toJson(),
    'GoalBacklogItem': goalBacklogItem.toJson(),
    'GoalPeriodRef': goalBacklogItem.toJson()['originalRef'] as Map<String, dynamic>,
  };
}

void main() {
  late ProviderContainer container;
  late LocalStorage storage;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    storage = LocalStorage(await SharedPreferences.getInstance());
    container = ProviderContainer(
      overrides: [localStorageProvider.overrideWithValue(storage)],
    );
  });
  tearDown(() => container.dispose());

  test('полный экспорт проходит export.schema.json, во всех разделах есть данные',
      () async {
    await _seed(container);
    final text = buildFullExport(storage, now: _now, appVersion: '0.4.0');
    final decoded = jsonDecode(text) as Map<String, dynamic>;

    final problems = _problems(JsonSchema.create(_readSchema()), decoded);
    expect(problems, isEmpty, reason: problems.join('\n'));

    final data = decoded['data'] as Map<String, dynamic>;
    for (final section in [
      'tasks',
      'goals',
      'schedule',
      'recurrence',
      'templates',
      'scheduleTemplates',
      'taskBacklog',
      'goalBacklog',
      'dayRatings',
      'periodRatings',
    ]) {
      expect(data[section], isNotEmpty, reason: 'раздел "$section" пуст — тест ничего не проверил');
    }
  });

  test('каждое поле модели есть в export.schema.json, и наоборот', () async {
    final samples = await _seed(container);
    final defs = _readSchema()[r'$defs'] as Map<String, dynamic>;

    final missing = <String>[];
    final extra = <String>[];
    samples.forEach((model, json) {
      final props =
          (defs[model] as Map<String, dynamic>)['properties'] as Map<String, dynamic>;
      for (final key in json.keys) {
        if (!props.containsKey(key)) missing.add('$model.$key');
      }
      for (final key in props.keys) {
        if (!json.containsKey(key)) extra.add('$model.$key');
      }
    });

    expect(
      missing,
      isEmpty,
      reason: 'поля есть в toJson, но не в схеме: ${missing.join(', ')}',
    );
    expect(
      extra,
      isEmpty,
      reason: 'поля есть в схеме, но не в toJson: ${extra.join(', ')}',
    );
  });
}
