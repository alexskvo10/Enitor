import '../../../data/models/recurrence_rule.dart';
import '../../../data/models/task.dart';

/// Откуда импортирована задача.
enum ImportSource { todoist, googleTasks, tickTick }

/// Повторение из экспорта. [weekdays]: 1 = пн … 7 = вс.
class ImportedRepeat {
  const ImportedRepeat({
    required this.kind,
    this.weekdays = const [],
    this.monthDays = const [],
    this.intervalDays = 1,
  });

  final RecurrenceKind kind;
  final List<int> weekdays;
  final List<int> monthDays;
  final int intervalDays;
}

enum ImportSkipReason {
  /// Пока не используем, оставлено на будущее.
  completedLongAgo,
  unsupportedRepeat,
  noTitle,
  unsupportedRow,
}

class ImportWarning {
  const ImportWarning(this.title, this.reason, [this.detail]);

  final String title;
  final ImportSkipReason reason;
  final String? detail;
}

/// Задача из внешнего экспорта в общей модели.
class ImportedTask {
  const ImportedTask({
    required this.source,
    required this.sourceId,
    required this.title,
    this.description,
    this.date,
    this.startMinutes,
    this.completed = false,
    this.completedAt,
    this.priority = TaskPriority.none,
    this.tags = const [],
    this.subtasks = const [],
    this.repeat,
    this.list,
  });

  /// Стабильный id внутри источника: повторный импорт не создаёт дублей.
  final ImportSource source;
  final String sourceId;
  final String title;
  final String? description;

  /// Только дата, без времени.
  final DateTime? date;

  /// Минуты с полуночи.
  final int? startMinutes;
  final bool completed;
  final DateTime? completedAt;
  final TaskPriority priority;
  final List<String> tags;

  /// Названия подзадач.
  final List<String> subtasks;
  final ImportedRepeat? repeat;

  /// Проект или список.
  final String? list;
}

class ImportResult {
  const ImportResult({required this.tasks, required this.warnings});

  final List<ImportedTask> tasks;
  final List<ImportWarning> warnings;
}

/// Черновик задачи при разборе: собирается по строкам, потом [toTask].
class ImportDraft {
  ImportDraft({
    required this.source,
    required this.sourceId,
    required this.title,
    this.parentId,
    this.description,
    this.date,
    this.startMinutes,
    this.completed = false,
    this.completedAt,
    this.priority = TaskPriority.none,
    this.tags = const [],
    this.repeat,
    this.list,
  });

  final ImportSource source;
  final String sourceId;
  final String title;

  /// id родителя из экспорта; null — задача верхнего уровня.
  final String? parentId;

  /// Меняется, когда к задаче добавляют заметки.
  String? description;
  final DateTime? date;
  final int? startMinutes;
  final bool completed;
  final DateTime? completedAt;
  final TaskPriority priority;
  final List<String> tags;
  final ImportedRepeat? repeat;
  final String? list;
  final List<String> subtasks = [];

  ImportedTask toTask() => ImportedTask(
        source: source,
        sourceId: sourceId,
        title: title,
        description: description,
        date: date,
        startMinutes: startMinutes,
        completed: completed,
        completedAt: completedAt,
        priority: priority,
        tags: tags,
        subtasks: subtasks,
        repeat: repeat,
        list: list,
      );
}

/// Результат для файла, который не удалось разобрать: пусто и одно предупреждение.
ImportResult importFileError(String detail) => ImportResult(
      tasks: const [],
      warnings: [ImportWarning('', ImportSkipReason.unsupportedRow, detail)],
    );

/// Дата без времени; null, если такого дня нет (например, 31 февраля).
DateTime? validDate(int year, int month, int day) {
  final d = DateTime(year, month, day);
  if (d.year != year || d.month != month || d.day != day) {
    return null;
  }
  return d;
}

/// Привязывает черновики с [ImportDraft.parentId] к родителю: их название
/// уходит в подзадачи родителя. Если родителя нет или он сам вложен, черновик
/// остаётся задачей верхнего уровня с предупреждением. Возвращает задачи
/// верхнего уровня в исходном порядке.
List<ImportDraft> linkSubtasks(
  List<ImportDraft> drafts,
  List<ImportWarning> warnings,
) {
  final byId = {for (final d in drafts) d.sourceId: d};
  final roots = <ImportDraft>[];
  for (final d in drafts) {
    final parentId = d.parentId;
    if (parentId == null) {
      roots.add(d);
      continue;
    }
    final parent = byId[parentId];
    if (parent == null) {
      warnings.add(
        ImportWarning(
          d.title,
          ImportSkipReason.unsupportedRow,
          'родитель не найден, задача импортирована отдельно',
        ),
      );
      roots.add(d);
    } else if (parent.parentId != null) {
      warnings.add(
        ImportWarning(
          d.title,
          ImportSkipReason.unsupportedRow,
          'вложенность глубже одного уровня, задача импортирована отдельно',
        ),
      );
      roots.add(d);
    } else {
      parent.subtasks.add(d.title);
    }
  }
  return roots;
}
