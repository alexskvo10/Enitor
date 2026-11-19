import 'dart:convert';

import '../../../../data/models/recurrence_rule.dart';
import '../../../../data/models/task.dart';
import '../csv.dart';
import '../imported_task.dart';

/// Разбор CSV-шаблона Todoist. TYPE: task / section / note / meta.
/// PRIORITY: 1 = p1 … 4 = p4. INDENT: 2 и больше — подзадача.
/// Повторы распознаются по DATE (английские и русские фразы).
/// [project] — имя файла: Todoist выгружает по проекту на файл, и без него
/// одинаковые задачи из двух проектов получили бы один id.
ImportResult parseTodoistCsv(String text, {String project = ''}) {
  final rows = parseCsv(text);
  if (rows.isEmpty || !_isHeader(rows.first)) {
    return importFileError(
      rows.isEmpty ? 'пустой файл' : 'не похоже на CSV Todoist',
    );
  }
  final header = rows.first.map(_norm).toList();
  final iType = header.indexOf('TYPE');
  final iContent = header.indexOf('CONTENT');
  final iDescription = header.indexOf('DESCRIPTION');
  final iPriority = header.indexOf('PRIORITY');
  final iIndent = header.indexOf('INDENT');
  final iDate = header.indexOf('DATE');

  final warnings = <ImportWarning>[];
  final drafts = <ImportDraft>[];
  final seen = <String, int>{};
  String? list;
  ImportDraft? top;
  var lastIsSubtask = false;

  for (var i = 1; i < rows.length; i++) {
    final row = rows[i];
    if (row.every((c) => c.trim().isEmpty)) {
      continue;
    }
    String cell(int idx) => idx >= 0 && idx < row.length ? row[idx].trim() : '';

    final type = cell(iType).toLowerCase();
    final content = cell(iContent);
    final where = 'строка ${i + 1}';

    if (type == 'meta') {
      continue;
    }
    if (type == 'section') {
      list = content.isEmpty ? null : content;
      top = null;
      lastIsSubtask = false;
      continue;
    }
    if (type == 'note') {
      if (content.isEmpty) {
        continue;
      }
      if (top == null) {
        warnings.add(
          ImportWarning(
            content,
            ImportSkipReason.unsupportedRow,
            '$where: заметка без задачи',
          ),
        );
      } else if (lastIsSubtask) {
        warnings.add(
          ImportWarning(
            content,
            ImportSkipReason.unsupportedRow,
            '$where: заметка к подзадаче не сохраняется',
          ),
        );
      } else {
        final current = top.description;
        top.description = current == null ? content : '$current\n$content';
      }
      continue;
    }
    if (type.isNotEmpty && type != 'task') {
      warnings.add(
        ImportWarning(
          content,
          ImportSkipReason.unsupportedRow,
          '$where: неизвестный TYPE "$type"',
        ),
      );
      continue;
    }
    if (content.isEmpty) {
      warnings.add(ImportWarning('', ImportSkipReason.noTitle, where));
      top = null;
      lastIsSubtask = false;
      continue;
    }

    final indent = int.tryParse(cell(iIndent)) ?? 1;
    if (indent > 1 && top != null) {
      top.subtasks.add(content);
      lastIsSubtask = true;
      continue;
    }
    if (indent > 1) {
      warnings.add(
        ImportWarning(
          content,
          ImportSkipReason.unsupportedRow,
          '$where: подзадача без родителя, импортирована отдельно',
        ),
      );
    }

    final dateRaw = cell(iDate);
    final when = _parseWhen(dateRaw);
    final problem = when.problem;
    if (problem != null) {
      warnings.add(ImportWarning(content, problem, '$where: $dateRaw'));
    }

    final key = project.isEmpty
        ? '${list ?? ''}\u0000$content'
        : '$project\u0000${list ?? ''}\u0000$content';
    final n = seen.update(key, (v) => v + 1, ifAbsent: () => 0);
    final description = cell(iDescription);
    final (title, labels) = _splitLabels(content);
    final draft = ImportDraft(
      source: ImportSource.todoist,
      sourceId: _fnv1a64('$key\u0000$n'),
      title: title,
      tags: labels,
      description: description.isEmpty ? null : description,
      date: when.date,
      startMinutes: when.startMinutes,
      priority: _priority(cell(iPriority)),
      repeat: when.repeat,
      list: list,
    );
    drafts.add(draft);
    top = draft;
    lastIsSubtask = false;
  }

  return ImportResult(
    tasks: [for (final d in drafts) d.toTask()],
    warnings: warnings,
  );
}

final _labelRe = RegExp(r'(^|\s)@([^\s@]+)');

/// Метки Todoist пишутся в самом названии: «Купить молоко @дом @магазин».
/// Название — без меток, метки — теги. Если кроме меток ничего нет, название
/// оставляем как было, чтобы задача не осталась безымянной.
(String, List<String>) _splitLabels(String content) {
  final labels = [for (final m in _labelRe.allMatches(content)) m[2]!];
  if (labels.isEmpty) return (content, const []);
  final title = content
      .replaceAllMapped(_labelRe, (m) => m[1]!)
      .replaceAll(RegExp(r'\s{2,}'), ' ')
      .trim();
  return (title.isEmpty ? content : title, labels.toSet().toList());
}

bool _isHeader(List<String> row) {
  final cells = row.map(_norm).toSet();
  return cells.contains('TYPE') && cells.contains('CONTENT');
}

String _norm(String s) => s.trim().toUpperCase();

TaskPriority _priority(String raw) {
  final p = int.tryParse(raw);
  if (p == 1) {
    return TaskPriority.high;
  }
  if (p == 2) {
    return TaskPriority.medium;
  }
  if (p == 3) {
    return TaskPriority.low;
  }
  return TaskPriority.none;
}

typedef _When = ({
  DateTime? date,
  int? startMinutes,
  ImportedRepeat? repeat,
  ImportSkipReason? problem,
});

final _dateTime = RegExp(
  r'^(\d{4})-(\d{2})-(\d{2})(?:[ t](\d{1,2}):(\d{2})(?::\d{2})?)?$',
);
final _recurringStart = RegExp(
  r'^(every|daily|weekly|monthly|кажд|ежедневно|еженедельно|ежемесячно)',
);
final _dailyPhrases = {'every day', 'daily', 'каждый день', 'ежедневно'};
final _everyDays = RegExp(r'^(?:every (\d+) days?|каждые (\d+) дн\S*)$');
final _monthDay = RegExp(
  r'^(?:every (\d{1,2})(?:st|nd|rd|th)|каждое (\d{1,2})-?е(?: число)?'
  r'|каждого (\d{1,2})-?го(?: числа)?)$',
);
final _everyWeekdays = RegExp(r'^(?:every|каждый|каждую|каждое) (.+)$');
final _weekdaySeparator = RegExp(r',|\s+and\s+|\s+и\s+');

const _weekdayNames = {
  'monday': 1,
  'mon': 1,
  'понедельник': 1,
  'пн': 1,
  'tuesday': 2,
  'tue': 2,
  'вторник': 2,
  'вт': 2,
  'wednesday': 3,
  'wed': 3,
  'среда': 3,
  'среду': 3,
  'ср': 3,
  'thursday': 4,
  'thu': 4,
  'четверг': 4,
  'чт': 4,
  'friday': 5,
  'fri': 5,
  'пятница': 5,
  'пятницу': 5,
  'пт': 5,
  'saturday': 6,
  'sat': 6,
  'суббота': 6,
  'субботу': 6,
  'сб': 6,
  'sunday': 7,
  'sun': 7,
  'воскресенье': 7,
  'вс': 7,
};

/// Разбирает DATE: дата, дата со временем или повтор.
_When _parseWhen(String raw) {
  final t = raw.trim().toLowerCase();
  if (t.isEmpty) {
    return (date: null, startMinutes: null, repeat: null, problem: null);
  }
  if (_recurringStart.hasMatch(t)) {
    final repeat = _parseRepeat(t);
    return (
      date: null,
      startMinutes: null,
      repeat: repeat,
      problem: repeat == null ? ImportSkipReason.unsupportedRepeat : null,
    );
  }
  final m = _dateTime.firstMatch(t);
  if (m == null) {
    return (
      date: null,
      startMinutes: null,
      repeat: null,
      problem: ImportSkipReason.unsupportedRow,
    );
  }
  final date = validDate(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
  if (date == null) {
    return (
      date: null,
      startMinutes: null,
      repeat: null,
      problem: ImportSkipReason.unsupportedRow,
    );
  }
  if (m[4] == null) {
    return (date: date, startMinutes: null, repeat: null, problem: null);
  }
  final hour = int.parse(m[4]!);
  final minute = int.parse(m[5]!);
  if (hour > 23 || minute > 59) {
    return (
      date: date,
      startMinutes: null,
      repeat: null,
      problem: ImportSkipReason.unsupportedRow,
    );
  }
  return (
    date: date,
    startMinutes: hour * 60 + minute,
    repeat: null,
    problem: null,
  );
}

/// Повтор из фразы. null — фраза не поддерживается (в том числе «каждую
/// неделю» и «каждый месяц» без дня: из экспорта не понять, какой день).
ImportedRepeat? _parseRepeat(String t) {
  if (_dailyPhrases.contains(t)) {
    return const ImportedRepeat(kind: RecurrenceKind.interval);
  }
  final days = _everyDays.firstMatch(t);
  if (days != null) {
    final n = int.parse(days[1] ?? days[2]!);
    if (n < 1) {
      return null;
    }
    return ImportedRepeat(kind: RecurrenceKind.interval, intervalDays: n);
  }
  final monthDay = _monthDay.firstMatch(t);
  if (monthDay != null) {
    final day = int.parse((monthDay[1] ?? monthDay[2] ?? monthDay[3])!);
    if (day < 1 || day > 31) {
      return null;
    }
    return ImportedRepeat(kind: RecurrenceKind.monthly, monthDays: [day]);
  }
  final body = _everyWeekdays.firstMatch(t);
  if (body != null) {
    final weekdays = <int>[];
    for (final part in body[1]!.split(_weekdaySeparator)) {
      final wd = _weekdayNames[part.trim()];
      if (wd == null) {
        return null;
      }
      if (!weekdays.contains(wd)) {
        weekdays.add(wd);
      }
    }
    return ImportedRepeat(kind: RecurrenceKind.weekly, weekdays: weekdays);
  }
  return null;
}

const _fnvPrimeHex = '100000001b3';
const _fnvOffsetHex = 'cbf29ce484222325';

/// FNV-1a 64 бита в hex: стабильный sourceId для строк без id.
String _fnv1a64(String s) {
  final mask = (BigInt.one << 64) - BigInt.one;
  final prime = BigInt.parse(_fnvPrimeHex, radix: 16);
  var hash = BigInt.parse(_fnvOffsetHex, radix: 16);
  for (final b in utf8.encode(s)) {
    hash = ((hash ^ BigInt.from(b)) * prime) & mask;
  }
  return hash.toRadixString(16).padLeft(16, '0');
}
