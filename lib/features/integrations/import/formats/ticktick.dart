import 'package:timezone/timezone.dart' as tz;

import '../../../../data/models/recurrence_rule.dart';
import '../../../../data/models/task.dart';
import '../csv.dart';
import '../imported_task.dart';

final _dateOnly = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');
final _offsetNoColon = RegExp(r'([+-]\d{2})(\d{2})$');
const _rruleDays = {
  'MO': 1,
  'TU': 2,
  'WE': 3,
  'TH': 4,
  'FR': 5,
  'SA': 6,
  'SU': 7,
};
const _rruleKeys = {'FREQ', 'INTERVAL', 'BYDAY', 'BYMONTHDAY'};

/// Разбор CSV-бэкапа TickTick. Перед заголовком идут строки метаданных,
/// поэтому заголовок ищем по колонкам Title и taskId. Срок (Due Date) — UTC с
/// смещением: переводим в зону из колонки Timezone, без имени зоны — в локальное
/// время. Для Is All Day время не берём.
ImportResult parseTickTickCsv(String text) {
  final rows = parseCsv(text);
  final headerAt = rows.indexWhere(_isHeader);
  if (headerAt < 0) {
    return importFileError(
      rows.isEmpty ? 'пустой файл' : 'не похоже на CSV TickTick',
    );
  }
  final header = rows[headerAt].map((c) => c.trim()).toList();
  int at(String name) => header.indexOf(name);
  final iList = at('List Name');
  final iTitle = at('Title');
  final iKind = at('Kind');
  final iTags = at('Tags');
  final iContent = at('Content');
  final iChecklist = at('Is Check list');
  final iDue = at('Due Date');
  final iAllDay = at('Is All Day');
  final iRepeat = at('Repeat');
  final iPriority = at('Priority');
  final iStatus = at('Status');
  final iCompleted = at('Completed Time');
  final iTimezone = at('Timezone');
  final iTaskId = at('taskId');
  final iParentId = at('parentId');

  final warnings = <ImportWarning>[];
  final drafts = <ImportDraft>[];
  for (var i = headerAt + 1; i < rows.length; i++) {
    final row = rows[i];
    if (row.every((c) => c.trim().isEmpty)) {
      continue;
    }
    String cell(int idx) => idx >= 0 && idx < row.length ? row[idx].trim() : '';
    final where = 'строка ${i + 1}';

    final title = cell(iTitle);
    if (title.isEmpty) {
      warnings.add(ImportWarning('', ImportSkipReason.noTitle, where));
      continue;
    }
    final id = cell(iTaskId);
    if (id.isEmpty) {
      warnings.add(
        ImportWarning(
          title,
          ImportSkipReason.unsupportedRow,
          '$where: нет taskId',
        ),
      );
      continue;
    }

    final content = cell(iContent);
    final checklist =
        cell(iKind).toUpperCase() == 'CHECKLIST' || _truthy(cell(iChecklist));

    final due = _parseDue(
      cell(iDue),
      allDay: _truthy(cell(iAllDay)),
      zone: cell(iTimezone),
    );
    if (due.bad) {
      warnings.add(
        ImportWarning(
          title,
          ImportSkipReason.unsupportedRow,
          '$where: срок ${cell(iDue)}',
        ),
      );
    }

    final repeatRaw = cell(iRepeat);
    final repeat = repeatRaw.isEmpty ? null : _parseRrule(repeatRaw);
    if (repeatRaw.isNotEmpty && repeat == null) {
      warnings.add(
        ImportWarning(
          title,
          ImportSkipReason.unsupportedRepeat,
          repeatRaw,
        ),
      );
    }

    final status = int.tryParse(cell(iStatus)) ?? 0;
    final completed = status == 1 || status == 2;
    final listName = cell(iList);
    final parentId = cell(iParentId);

    drafts.add(
      ImportDraft(
        source: ImportSource.tickTick,
        sourceId: id,
        title: title,
        parentId: parentId.isEmpty ? null : parentId,
        description: checklist || content.isEmpty ? null : content,
        date: due.date,
        startMinutes: due.startMinutes,
        completed: completed,
        completedAt: completed ? _parseStamp(cell(iCompleted)) : null,
        priority: _tickPriority(cell(iPriority)),
        tags: _split(cell(iTags)),
        repeat: repeat,
        list: listName.isEmpty ? null : listName,
      )..subtasks.addAll(checklist ? _checklistItems(content) : const []),
    );
  }

  final roots = linkSubtasks(drafts, warnings);
  return ImportResult(
    tasks: [for (final d in roots) d.toTask()],
    warnings: warnings,
  );
}

bool _isHeader(List<String> row) {
  final cells = row.map((c) => c.trim()).toSet();
  return cells.contains('Title') && cells.contains('taskId');
}

bool _truthy(String v) => {'y', 'yes', 'true', '1'}.contains(v.toLowerCase());

List<String> _split(String raw) => [
      for (final part in raw.split(','))
        if (part.trim().isNotEmpty) part.trim(),
    ];

/// Пункты чек-листа: строки с маркерами ▫ (не отмечен) и ▪ (отмечен).
/// Отметку не сохраняем: в модели подзадача — только название.
List<String> _checklistItems(String content) {
  final items = <String>[];
  for (final line in content.split(RegExp(r'\r?\n'))) {
    final item = line.trim().replaceFirst(RegExp(r'^[▫▪]\s*'), '').trim();
    if (item.isNotEmpty) {
      items.add(item);
    }
  }
  return items;
}

TaskPriority _tickPriority(String raw) {
  final p = int.tryParse(raw);
  if (p == 5) {
    return TaskPriority.high;
  }
  if (p == 3) {
    return TaskPriority.medium;
  }
  if (p == 1) {
    return TaskPriority.low;
  }
  return TaskPriority.none;
}

/// Время в формате 2026-11-02T15:00:00+0000 (смещение без двоеточия тоже).
DateTime? _parseStamp(String raw) {
  final normalized = raw.trim().replaceFirstMapped(
        _offsetNoColon,
        (m) => '${m[1]}:${m[2]}',
      );
  return DateTime.tryParse(normalized)?.toUtc();
}

/// Переводит момент в зону; без имени или при неизвестной зоне — локальное время.
DateTime _toZone(DateTime utc, String zone) {
  if (zone.isEmpty) {
    return utc.toLocal();
  }
  try {
    return tz.TZDateTime.from(utc, tz.getLocation(zone));
  } on Exception {
    return utc.toLocal();
  }
}

({DateTime? date, int? startMinutes, bool bad}) _parseDue(
  String raw, {
  required bool allDay,
  required String zone,
}) {
  if (raw.isEmpty) {
    return (date: null, startMinutes: null, bad: false);
  }
  final onlyDate = _dateOnly.firstMatch(raw);
  if (onlyDate != null) {
    final d = validDate(
      int.parse(onlyDate[1]!),
      int.parse(onlyDate[2]!),
      int.parse(onlyDate[3]!),
    );
    return (date: d, startMinutes: null, bad: d == null);
  }
  final instant = _parseStamp(raw);
  if (instant == null) {
    return (date: null, startMinutes: null, bad: true);
  }
  final local = _toZone(instant, zone);
  final date = validDate(local.year, local.month, local.day);
  return (
    date: date,
    startMinutes: allDay ? null : local.hour * 60 + local.minute,
    bad: date == null,
  );
}

/// Repeat: RRULE:FREQ=DAILY;INTERVAL=N | DAILY;BYDAY=MO,WE (при INTERVAL=1) |
/// WEEKLY;BYDAY=MO,WE | MONTHLY;BYMONTHDAY=N.
/// Остальное (ключи вне списка, интервалы больше 1 там, где они не переводятся,
/// BYMONTHDAY у DAILY/WEEKLY, BYDAY у MONTHLY) — null.
ImportedRepeat? _parseRrule(String raw) {
  var body = raw.trim().toUpperCase();
  if (body.startsWith('RRULE:')) {
    body = body.substring(6);
  }
  final parts = <String, String>{};
  for (final pair in body.split(';')) {
    final eq = pair.indexOf('=');
    if (eq <= 0) {
      return null;
    }
    parts[pair.substring(0, eq)] = pair.substring(eq + 1);
  }
  if (parts.keys.any((k) => !_rruleKeys.contains(k))) {
    return null;
  }
  final interval = int.tryParse(parts['INTERVAL'] ?? '1') ?? 0;
  if (interval < 1) {
    return null;
  }
  final freq = parts['FREQ'];
  final byDay = parts['BYDAY'];
  final byMonthDay = parts['BYMONTHDAY'];
  if (freq == 'DAILY') {
    if (byMonthDay != null) {
      return null;
    }
    if (byDay == null) {
      return ImportedRepeat(
        kind: RecurrenceKind.interval,
        intervalDays: interval,
      );
    }
    // «Каждый будний день» — DAILY;BYDAY=MO,TU,... при INTERVAL=1.
    return interval == 1 ? _weekdaysRepeat(byDay) : null;
  }
  if (interval != 1) {
    return null;
  }
  if (freq == 'WEEKLY') {
    if (byMonthDay != null || byDay == null) {
      return null;
    }
    return _weekdaysRepeat(byDay);
  }
  if (freq == 'MONTHLY') {
    if (byDay != null) {
      return null;
    }
    final day = int.tryParse(byMonthDay ?? '');
    if (day == null || day < 1 || day > 31) {
      return null;
    }
    return ImportedRepeat(kind: RecurrenceKind.monthly, monthDays: [day]);
  }
  return null;
}

/// Дни из BYDAY (MO,WE,...) в повтор по неделе; неизвестный код — null.
ImportedRepeat? _weekdaysRepeat(String byDay) {
  final days = <int>[];
  for (final code in byDay.split(',')) {
    final d = _rruleDays[code.trim()];
    if (d == null) {
      return null;
    }
    days.add(d);
  }
  return ImportedRepeat(kind: RecurrenceKind.weekly, weekdays: days);
}
