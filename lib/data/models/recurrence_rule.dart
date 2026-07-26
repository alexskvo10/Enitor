import 'task.dart' show TaskPriority;

/// Виды повторений:
/// - weekly: по дням недели ([weekdays] — список 1..7, понедельник = 1)
/// - monthly: по числам месяца ([monthDays] — список 1..31; если в месяце нет
///   такого числа, повторение для этого месяца пропускается)
/// - interval: каждые N дней начиная с [startDate] ([intervalDays] ≥ 1)
enum RecurrenceKind { weekly, monthly, interval }

class RecurrenceRule {
  const RecurrenceRule({
    required this.id,
    required this.taskTitle,
    required this.kind,
    required this.startDate,
    required this.createdAt,
    required this.updatedAt,
    this.taskDescription,
    this.weekdays = const [],
    this.monthDays = const [],
    this.intervalDays = 1,
    this.endDate,
    this.exceptDates = const [],
    this.startMinutes,
    this.endMinutes,
    this.estimatedMinutes,
    this.targetCount,
    this.subtaskTitles = const [],
    this.priority = TaskPriority.none,
    this.tags = const [],
  });

  final String id;
  final String taskTitle;
  final String? taskDescription;
  final RecurrenceKind kind;
  final List<int> weekdays;
  final List<int> monthDays;
  final int intervalDays;
  final DateTime startDate;
  final DateTime? endDate;

  /// Даты-исключения: конкретные дни, для которых экземпляр удалён вручную
  /// («Только этот день»). [occursOn] возвращает false для этих дат, поэтому
  /// [plannedForDay] не генерирует виртуальный незавершённый экземпляр.
  final List<DateTime> exceptDates;

  final DateTime createdAt;
  final DateTime updatedAt;

  /// Шаблон времени — копируется в каждый сгенерированный экземпляр задачи.
  final int? startMinutes;
  final int? endMinutes;
  final int? estimatedMinutes;

  /// Цель счётчика — копируется в каждый экземпляр (повторяющийся счётчик).
  final int? targetCount;

  /// Шаблон подзадач — копируется в каждый экземпляр свежим набором (все не
  /// выполнены). Пусто — обычная повторяющаяся задача.
  final List<String> subtaskTitles;

  /// Приоритет и теги — копируются в каждый экземпляр.
  final TaskPriority priority;
  final List<String> tags;

  /// Срабатывает ли правило в указанный день. Только дата (без времени).
  bool occursOn(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    final start = DateTime(startDate.year, startDate.month, startDate.day);
    if (d.isBefore(start)) return false;
    if (endDate != null) {
      final end = DateTime(endDate!.year, endDate!.month, endDate!.day);
      if (d.isAfter(end)) return false;
    }
    // Дата-исключение: экземпляр удалён вручную для этого конкретного дня.
    if (exceptDates.any((e) => DateTime(e.year, e.month, e.day) == d)) {
      return false;
    }
    switch (kind) {
      case RecurrenceKind.weekly:
        return weekdays.contains(d.weekday);
      case RecurrenceKind.monthly:
        return monthDays.contains(d.day);
      case RecurrenceKind.interval:
        final diff = d.difference(start).inDays;
        return intervalDays > 0 && diff % intervalDays == 0;
    }
  }

  RecurrenceRule copyWith({
    String? taskTitle,
    String? taskDescription,
    RecurrenceKind? kind,
    List<int>? weekdays,
    List<int>? monthDays,
    int? intervalDays,
    DateTime? startDate,
    DateTime? endDate,
    bool clearEndDate = false,
    List<DateTime>? exceptDates,
    DateTime? updatedAt,
    int? startMinutes,
    bool clearStartMinutes = false,
    int? endMinutes,
    bool clearEndMinutes = false,
    int? estimatedMinutes,
    bool clearEstimatedMinutes = false,
    int? targetCount,
    bool clearTargetCount = false,
    List<String>? subtaskTitles,
    TaskPriority? priority,
    List<String>? tags,
  }) =>
      RecurrenceRule(
        id: id,
        taskTitle: taskTitle ?? this.taskTitle,
        taskDescription: taskDescription ?? this.taskDescription,
        kind: kind ?? this.kind,
        weekdays: weekdays ?? this.weekdays,
        monthDays: monthDays ?? this.monthDays,
        intervalDays: intervalDays ?? this.intervalDays,
        startDate: startDate ?? this.startDate,
        endDate: clearEndDate ? null : (endDate ?? this.endDate),
        exceptDates: exceptDates ?? this.exceptDates,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        startMinutes:
            clearStartMinutes ? null : (startMinutes ?? this.startMinutes),
        endMinutes: clearEndMinutes ? null : (endMinutes ?? this.endMinutes),
        estimatedMinutes: clearEstimatedMinutes
            ? null
            : (estimatedMinutes ?? this.estimatedMinutes),
        targetCount:
            clearTargetCount ? null : (targetCount ?? this.targetCount),
        subtaskTitles: subtaskTitles ?? this.subtaskTitles,
        priority: priority ?? this.priority,
        tags: tags ?? this.tags,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'taskTitle': taskTitle,
        'taskDescription': taskDescription,
        'kind': kind.name,
        'weekdays': weekdays,
        'monthDays': monthDays,
        'intervalDays': intervalDays,
        'startDate': startDate.toIso8601String(),
        'endDate': endDate?.toIso8601String(),
        'exceptDates':
            exceptDates.map((d) => d.toIso8601String()).toList(),
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'startMinutes': startMinutes,
        'endMinutes': endMinutes,
        'estimatedMinutes': estimatedMinutes,
        'targetCount': targetCount,
        'subtaskTitles': subtaskTitles,
        'priority': priority.index,
        'tags': tags,
      };

  factory RecurrenceRule.fromJson(Map<String, dynamic> j) => RecurrenceRule(
        id: j['id'] as String,
        taskTitle: j['taskTitle'] as String,
        taskDescription: j['taskDescription'] as String?,
        kind: RecurrenceKind.values
            .firstWhere((e) => e.name == (j['kind'] as String)),
        weekdays:
            (j['weekdays'] as List?)?.map((e) => e as int).toList() ?? const [],
        monthDays: (j['monthDays'] as List?)?.map((e) => e as int).toList() ??
            const [],
        intervalDays: j['intervalDays'] as int? ?? 1,
        startDate: DateTime.parse(j['startDate'] as String),
        endDate: j['endDate'] == null
            ? null
            : DateTime.parse(j['endDate'] as String),
        // Старые правила без поля → пустой список (backward-compatible).
        exceptDates: (j['exceptDates'] as List?)
                ?.map((e) => DateTime.parse(e as String))
                .toList() ??
            const [],
        createdAt: DateTime.parse(j['createdAt'] as String),
        updatedAt: DateTime.parse(j['updatedAt'] as String),
        startMinutes: j['startMinutes'] as int?,
        endMinutes: j['endMinutes'] as int?,
        estimatedMinutes: j['estimatedMinutes'] as int?,
        targetCount: j['targetCount'] as int?,
        subtaskTitles:
            (j['subtaskTitles'] as List?)?.map((e) => e as String).toList() ??
                const [],
        priority: TaskPriority.values[(j['priority'] as int? ?? 0)
            .clamp(0, TaskPriority.values.length - 1)],
        tags: (j['tags'] as List?)?.map((e) => e as String).toList() ??
            const [],
      );
}
