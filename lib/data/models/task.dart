/// Приоритет задачи. Влияет на сортировку (среди задач без времени)
/// и на иконку в плитке. Порядок значений = возрастание важности.
enum TaskPriority { none, low, medium, high }

/// Подзадача (пункт чек-листа внутри задачи).
class SubTask {
  const SubTask({required this.id, required this.title, this.done = false});

  final String id;
  final String title;
  final bool done;

  SubTask copyWith({String? title, bool? done}) => SubTask(
        id: id,
        title: title ?? this.title,
        done: done ?? this.done,
      );

  Map<String, dynamic> toJson() => {'id': id, 'title': title, 'done': done};

  factory SubTask.fromJson(Map<String, dynamic> j) => SubTask(
        id: j['id'] as String,
        title: j['title'] as String,
        done: j['done'] as bool? ?? false,
      );
}

class Task {
  Task({
    required this.id,
    required this.title,
    required this.date,
    required this.createdAt,
    required this.updatedAt,
    this.description,
    this.completedAt,
    this.order = 0,
    this.recurrenceRuleId,
    this.startMinutes,
    this.endMinutes,
    this.estimatedMinutes,
    this.actualMinutes,
    this.targetCount,
    this.progressCount = 0,
    this.goalId,
    this.isTransferred = false,
    this.transferredFromId,
    this.transferDeclined = false,
    this.quality,
    this.subtasks = const [],
    this.priority = TaskPriority.none,
    this.tags = const [],
  });

  final String id;
  final String title;
  final String? description;
  final DateTime date;
  final DateTime? completedAt;
  final int order;
  final String? recurrenceRuleId;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Время начала — минуты с полуночи (0–1439). Например, 10:30 → 630.
  final int? startMinutes;

  /// Время окончания — минуты с полуночи.
  final int? endMinutes;

  /// Оценка длительности в минутах.
  final int? estimatedMinutes;

  /// Фактическая длительность в минутах (заполняется после выполнения).
  final int? actualMinutes;

  /// Целевое число для задачи-счётчика (например, 5 стаканов воды).
  /// null — обычная задача с галочкой.
  final int? targetCount;

  /// Текущее значение счётчика (0..targetCount).
  final int progressCount;

  /// Привязка к цели-квоте (id цели). null — не привязана.
  final String? goalId;

  /// true — оригинал задачи, которую перенесли на другой день.
  /// Остаётся в прошлом дне с особым маркером.
  final bool isTransferred;

  /// Задача является копией, перенесённой из другого дня.
  /// Значение — id оригинальной задачи.
  final String? transferredFromId;

  /// Пользователь явно отказался переносить эту задачу (баннер/догоняющий
  /// список) — больше не предлагать перенос повторно.
  final bool transferDeclined;

  /// Субъективная оценка качества выполнения (1..10), рефлексия. null — не оценено.
  final int? quality;

  /// Подзадачи (чек-лист). Пусто — обычная задача. Работают как счётчик:
  /// все выполнены → задача выполнена; частично → дробный вклад в продуктивность.
  final List<SubTask> subtasks;

  /// Приоритет (нет/низкий/средний/высокий).
  final TaskPriority priority;

  /// Теги для группировки и статистики («работа», «спорт»). Без «#» в данных.
  final List<String> tags;

  bool get isCompleted => completedAt != null;

  /// Задача-чек-лист (есть подзадачи).
  bool get isChecklist => subtasks.isNotEmpty;

  /// Сколько подзадач выполнено.
  int get subtasksDone => subtasks.where((s) => s.done).length;

  /// Доля выполнения для статистики: чек-лист/счётчик — дробь, обычная — 0/1.
  double get completionFraction {
    if (isChecklist) return subtasksDone / subtasks.length;
    if (isCounter) return counterProgress ?? 0.0;
    return isCompleted ? 1.0 : 0.0;
  }

  /// Значение для кольца прогресса (0..1) у чек-листа/счётчика; null — обычная.
  double? get progressRingValue {
    if (isChecklist) return subtasksDone / subtasks.length;
    if (isCounter) return counterProgress;
    return null;
  }

  /// Вклад задачи в прогресс привязанной цели: счётчик → текущее значение
  /// (даже частичное), обычная → 1 при выполнении.
  int get goalContribution =>
      isCounter ? progressCount : (isCompleted ? 1 : 0);

  /// Задача-счётчик (с прогрессом к числу), а не обычная галочка.
  bool get isCounter => targetCount != null && targetCount! > 1;

  /// Прогресс счётчика 0..1 (или null для обычной задачи).
  double? get counterProgress =>
      isCounter ? (progressCount / targetCount!).clamp(0.0, 1.0) : null;

  /// Подпись времени с локализованными словами: «10:00—12:30», «с 16:45»,
  /// «до 18:15» или null. Слова «с»/«до» ([fromWord]/[toWord]) передаются из
  /// l10n — модель не знает про UI/BuildContext; двусторонний диапазон слов
  /// не требует.
  String? timeLabelWith({required String fromWord, required String toWord}) {
    if (startMinutes == null && endMinutes == null) return null;
    final s = startMinutes != null ? _fmt(startMinutes!) : null;
    final e = endMinutes != null ? _fmt(endMinutes!) : null;
    if (s != null && e != null) return '$s—$e';
    if (s != null) return '$fromWord $s';
    return '$toWord $e';
  }

  static String _fmt(int m) =>
      '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';

  Task copyWith({
    String? title,
    String? description,
    DateTime? date,
    DateTime? completedAt,
    bool clearCompleted = false,
    int? order,
    DateTime? updatedAt,
    int? startMinutes,
    bool clearStartMinutes = false,
    int? endMinutes,
    bool clearEndMinutes = false,
    int? estimatedMinutes,
    bool clearEstimatedMinutes = false,
    int? actualMinutes,
    bool clearActualMinutes = false,
    int? targetCount,
    bool clearTargetCount = false,
    int? progressCount,
    String? goalId,
    bool clearGoalId = false,
    bool? isTransferred,
    bool? transferDeclined,
    int? quality,
    bool clearQuality = false,
    List<SubTask>? subtasks,
    TaskPriority? priority,
    List<String>? tags,
  }) =>
      Task(
        id: id,
        title: title ?? this.title,
        description: description ?? this.description,
        date: date ?? this.date,
        completedAt: clearCompleted ? null : (completedAt ?? this.completedAt),
        order: order ?? this.order,
        recurrenceRuleId: recurrenceRuleId,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        startMinutes:
            clearStartMinutes ? null : (startMinutes ?? this.startMinutes),
        endMinutes: clearEndMinutes ? null : (endMinutes ?? this.endMinutes),
        estimatedMinutes: clearEstimatedMinutes
            ? null
            : (estimatedMinutes ?? this.estimatedMinutes),
        actualMinutes:
            clearActualMinutes ? null : (actualMinutes ?? this.actualMinutes),
        targetCount:
            clearTargetCount ? null : (targetCount ?? this.targetCount),
        progressCount: progressCount ?? this.progressCount,
        goalId: clearGoalId ? null : (goalId ?? this.goalId),
        isTransferred: isTransferred ?? this.isTransferred,
        transferredFromId: transferredFromId ?? this.transferredFromId,
        transferDeclined: transferDeclined ?? this.transferDeclined,
        quality: clearQuality ? null : (quality ?? this.quality),
        subtasks: subtasks ?? this.subtasks,
        priority: priority ?? this.priority,
        tags: tags ?? this.tags,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'date': date.toIso8601String(),
        'completedAt': completedAt?.toIso8601String(),
        'order': order,
        'recurrenceRuleId': recurrenceRuleId,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'startMinutes': startMinutes,
        'endMinutes': endMinutes,
        'estimatedMinutes': estimatedMinutes,
        'actualMinutes': actualMinutes,
        'targetCount': targetCount,
        'progressCount': progressCount,
        'goalId': goalId,
        'isTransferred': isTransferred,
        'transferredFromId': transferredFromId,
        'transferDeclined': transferDeclined,
        'quality': quality,
        'subtasks': subtasks.map((s) => s.toJson()).toList(),
        'priority': priority.index,
        'tags': tags,
      };

  factory Task.fromJson(Map<String, dynamic> j) => Task(
        id: j['id'] as String,
        title: j['title'] as String,
        description: j['description'] as String?,
        date: DateTime.parse(j['date'] as String),
        completedAt: j['completedAt'] == null
            ? null
            : DateTime.parse(j['completedAt'] as String),
        order: j['order'] as int? ?? 0,
        recurrenceRuleId: j['recurrenceRuleId'] as String?,
        createdAt: DateTime.parse(j['createdAt'] as String),
        updatedAt: DateTime.parse(j['updatedAt'] as String),
        startMinutes: j['startMinutes'] as int?,
        endMinutes: j['endMinutes'] as int?,
        estimatedMinutes: j['estimatedMinutes'] as int?,
        actualMinutes: j['actualMinutes'] as int?,
        targetCount: j['targetCount'] as int?,
        progressCount: j['progressCount'] as int? ?? 0,
        goalId: j['goalId'] as String?,
        isTransferred: j['isTransferred'] as bool? ?? false,
        transferredFromId: j['transferredFromId'] as String?,
        transferDeclined: j['transferDeclined'] as bool? ?? false,
        quality: j['quality'] as int?,
        subtasks: (j['subtasks'] as List?)
                ?.map((e) => SubTask.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        priority: TaskPriority.values[(j['priority'] as int? ?? 0)
            .clamp(0, TaskPriority.values.length - 1)],
        tags: (j['tags'] as List?)?.map((e) => e as String).toList() ??
            const [],
      );
}
