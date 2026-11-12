import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../../data/models/backlog_item.dart';
import '../../../data/models/day_stats.dart';
import '../../../data/models/day_template.dart';
import '../../../data/models/goal.dart';
import '../../../data/models/recurrence_rule.dart';
import '../../../data/models/schedule_item.dart';
import '../../../data/models/task.dart';

// Чистый Dart: файл подключает и приложение, и `enitor-server`.

/// Что синхронизуется. [name] — имя в протоколе (совпадает с разделами
/// полного экспорта), [storageKey] — ключ в хранилище приложения.
class SyncCollection {
  const SyncCollection(
    this.name,
    this.storageKey, {
    this.idField = 'id',
    this.isMap = false,
    required this.validate,
  });

  final String name;
  final String storageKey;

  /// Поле с id записи у списков. У [isMap] id — ключ карты.
  final String idField;

  /// Хранится картой «ключ → число» (оценки), а не списком записей. Запись
  /// такой коллекции в протоколе — `{"value": число}`.
  final bool isMap;

  /// Бросает, если запись не разберёт приложение. Чужая запись, которую
  /// нельзя разобрать, уронила бы репозиторий при перечитывании.
  final void Function(Map<String, dynamic> data) validate;
}

void _rating(Map<String, dynamic> d) {
  final v = d['value'];
  if (v is! num || v < 1 || v > 10) {
    throw const FormatException('value must be a number 1..10');
  }
}

const kSyncCollections = <SyncCollection>[
  SyncCollection('tasks', 'tasks', validate: Task.fromJson),
  SyncCollection('goals', 'goals', validate: Goal.fromJson),
  SyncCollection('schedule', 'schedule_items', validate: ScheduleItem.fromJson),
  SyncCollection('recurrence', 'recurrence_rules',
      validate: RecurrenceRule.fromJson,),
  SyncCollection('templates', 'day_templates', validate: DayTemplate.fromJson),
  SyncCollection('taskBacklog', 'task_backlog', validate: BacklogItem.fromJson),
  SyncCollection('goalBacklog', 'goal_backlog',
      validate: GoalBacklogItem.fromJson,),
  // Статистика дня считается из задач, но после переноса «история
  // неизменна» — пересчёт на другом устройстве дал бы другое число.
  SyncCollection('dayStats', 'day_stats',
      idField: 'date', validate: DayStats.fromJson,),
  SyncCollection('dayRatings', 'day_ratings', isMap: true, validate: _rating),
  SyncCollection('periodRatings', 'period_ratings',
      isMap: true, validate: _rating,),
];

SyncCollection? syncCollection(String name) =>
    kSyncCollections.where((c) => c.name == name).firstOrNull;

/// Проверка записи без исключения наружу: текст ошибки или null.
String? validateRecord(SyncCollection c, Object? data) {
  if (data is! Map<String, dynamic>) return 'data must be an object';
  try {
    c.validate(data);
    return null;
  } catch (e) {
    return '$e';
  }
}

/// Хэш записи. Ключи сортируются: порядок полей у разных версий приложения и
/// после круга через сервер может отличаться, а сама запись — нет.
String recordHash(Object? data) =>
    sha1.convert(utf8.encode(jsonEncode(_canonical(data)))).toString();

Object? _canonical(Object? v) {
  if (v is Map) {
    final keys = v.keys.map((k) => '$k').toList()..sort();
    return {for (final k in keys) k: _canonical(v[k])};
  }
  if (v is List) return [for (final e in v) _canonical(e)];
  return v;
}
