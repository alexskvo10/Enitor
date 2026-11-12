import 'dart:convert';

import '../imported_task.dart';

final _dueDate = RegExp(r'^(\d{4})-(\d{2})-(\d{2})');

/// Разбор Tasks.json из Google Takeout: корень — объект {"items": [списки]}
/// (или сам массив списков), у списка "items" — задачи. Срок (due) приходит
/// только датой; дату из UTC-строки берём как есть. Подзадача — задача с "parent".
ImportResult parseGoogleTasksJson(String text) {
  if (text.trim().isEmpty) {
    return importFileError('пустой файл');
  }
  final decoded = _tryDecode(text);
  if (decoded == null) {
    return importFileError('не JSON');
  }
  final lists = decoded is Map<String, dynamic> ? decoded['items'] : decoded;
  if (lists is! List) {
    return importFileError('не похоже на Tasks.json Google');
  }

  final warnings = <ImportWarning>[];
  final tasks = <ImportedTask>[];
  for (final entry in lists) {
    if (entry is! Map<String, dynamic>) {
      warnings.add(
        const ImportWarning(
          '',
          ImportSkipReason.unsupportedRow,
          'список не объект',
        ),
      );
      continue;
    }
    final items = entry['items'];
    if (items is! List) {
      continue;
    }
    final drafts = _parseItems(items, _str(entry['title']), warnings);
    tasks.addAll([for (final d in linkSubtasks(drafts, warnings)) d.toTask()]);
  }
  return ImportResult(tasks: tasks, warnings: warnings);
}

List<ImportDraft> _parseItems(
  List<dynamic> items,
  String? list,
  List<ImportWarning> warnings,
) {
  final drafts = <ImportDraft>[];
  for (final raw in items) {
    if (raw is! Map<String, dynamic>) {
      warnings.add(
        const ImportWarning(
          '',
          ImportSkipReason.unsupportedRow,
          'задача не объект',
        ),
      );
      continue;
    }
    if (raw['deleted'] == true) {
      continue;
    }
    final id = _str(raw['id']);
    final title = _str(raw['title']);
    if (id == null) {
      warnings.add(
        ImportWarning(
          title ?? '',
          ImportSkipReason.unsupportedRow,
          'нет id',
        ),
      );
      continue;
    }
    if (title == null) {
      warnings.add(ImportWarning('', ImportSkipReason.noTitle, 'id $id'));
      continue;
    }
    final dueRaw = _str(raw['due']);
    final due = dueRaw == null ? null : _parseDue(dueRaw);
    if (dueRaw != null && due == null) {
      warnings.add(
        ImportWarning(
          title,
          ImportSkipReason.unsupportedRow,
          'срок: $dueRaw',
        ),
      );
    }
    final completed = raw['status'] == 'completed';
    drafts.add(
      ImportDraft(
        source: ImportSource.googleTasks,
        sourceId: id,
        title: title,
        parentId: _str(raw['parent']),
        description: _str(raw['notes']),
        date: due,
        completed: completed,
        completedAt: completed
            ? DateTime.tryParse(_str(raw['completed']) ?? '')?.toLocal()
            : null,
        list: list,
      ),
    );
  }
  return drafts;
}

DateTime? _parseDue(String raw) {
  final m = _dueDate.firstMatch(raw);
  if (m == null) {
    return null;
  }
  return validDate(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
}

Object? _tryDecode(String text) {
  try {
    return jsonDecode(text);
  } on FormatException {
    return null;
  }
}

String? _str(Object? v) {
  if (v is! String) {
    return null;
  }
  final t = v.trim();
  return t.isEmpty ? null : t;
}
