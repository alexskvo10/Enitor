import 'dart:convert';

import '../../../data/sources/local/local_storage.dart';

/// Версия формата полного экспорта (formats.md, раздел 4).
const kExportFormatVersion = 1;

/// Что входит в экспорт: только данные человека. Производное (статистика
/// дней, снимки колец — пересчитываются), настройки оформления и всё
/// «устройство» (интеграции, очередь вебхуков, снимок виджета) не входят;
/// секретов в хранилище нет вовсе — они в защищённом хранилище системы.
const kExportSections = <String, String>{
  'tasks': 'tasks',
  'goals': 'goals',
  'schedule': 'schedule_items',
  'recurrence': 'recurrence_rules',
  'templates': 'day_templates',
  'scheduleTemplates': 'schedule_templates',
  'taskBacklog': 'task_backlog',
  'goalBacklog': 'goal_backlog',
};

/// Оценки дней и периодов хранятся словарём «дата → оценка 1..10».
const kExportMapSections = <String, String>{
  'dayRatings': 'day_ratings',
  'periodRatings': 'period_ratings',
};

/// Полный машиночитаемый экспорт. В отличие от бэкапа (точный слепок
/// хранилища для восстановления в Enitor), это описанный формат для других
/// программ: схемы — в docs/integrations/schema/.
String buildFullExport(
  LocalStorage storage, {
  required DateTime now,
  required String appVersion,
}) {
  return const JsonEncoder.withIndent('  ').convert({
    'format': 'enitor-export',
    'v': kExportFormatVersion,
    'exportedAt': now.toIso8601String(),
    'app': {'version': appVersion},
    'data': {
      for (final e in kExportSections.entries)
        e.key: storage.readList(e.value),
      for (final e in kExportMapSections.entries)
        e.key: storage.readMap(e.value) ?? const <String, Object?>{},
    },
  });
}
