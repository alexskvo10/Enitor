import 'goal.dart';
import 'task.dart' show TaskPriority;

/// Задача в бэклоге невыполненных — «плавает» без привязки к дню.
/// Создаётся когда перенесённая копия задачи удаляется из дня назначения.
class BacklogItem {
  BacklogItem({
    required this.id,
    required this.title,
    required this.originalDate,
    required this.addedAt,
    this.description,
    this.startMinutes,
    this.endMinutes,
    this.estimatedMinutes,
    this.targetCount,
    this.progressCount = 0,
    this.subtaskTitles = const [],
    this.priority = TaskPriority.none,
    this.tags = const [],
  });

  final String id;
  final String title;
  final String? description;

  /// Дата, когда задача была изначально запланирована (до переноса).
  final DateTime originalDate;

  /// Когда попала в бэклог.
  final DateTime addedAt;

  final int? startMinutes;
  final int? endMinutes;
  final int? estimatedMinutes;
  final int? targetCount;
  final int progressCount;

  /// Названия подзадач (если задача была чек-листом). Восстанавливаются свежими.
  final List<String> subtaskTitles;

  final TaskPriority priority;
  final List<String> tags;

  bool get isCounter => targetCount != null && targetCount! > 1;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'originalDate': originalDate.toIso8601String(),
        'addedAt': addedAt.toIso8601String(),
        'startMinutes': startMinutes,
        'endMinutes': endMinutes,
        'estimatedMinutes': estimatedMinutes,
        'targetCount': targetCount,
        'progressCount': progressCount,
        'subtaskTitles': subtaskTitles,
        'priority': priority.index,
        'tags': tags,
      };

  factory BacklogItem.fromJson(Map<String, dynamic> j) => BacklogItem(
        id: j['id'] as String,
        title: j['title'] as String,
        description: j['description'] as String?,
        originalDate: DateTime.parse(j['originalDate'] as String),
        addedAt: DateTime.parse(j['addedAt'] as String),
        startMinutes: j['startMinutes'] as int?,
        endMinutes: j['endMinutes'] as int?,
        estimatedMinutes: j['estimatedMinutes'] as int?,
        targetCount: j['targetCount'] as int?,
        progressCount: j['progressCount'] as int? ?? 0,
        subtaskTitles:
            (j['subtaskTitles'] as List?)?.map((e) => e as String).toList() ??
                const [],
        priority: TaskPriority.values[(j['priority'] as int? ?? 0)
            .clamp(0, TaskPriority.values.length - 1)],
        tags: (j['tags'] as List?)?.map((e) => e as String).toList() ??
            const [],
      );
}

/// Цель в бэклоге недостигнутых.
/// Создаётся когда перенесённая копия цели удаляется из периода назначения.
class GoalBacklogItem {
  GoalBacklogItem({
    required this.id,
    required this.title,
    required this.period,
    required this.originalRef,
    required this.addedAt,
    this.description,
    this.targetCount,
    this.progressCount = 0,
    this.subtaskTitles = const [],
  });

  final String id;
  final String title;
  final String? description;
  final GoalPeriod period;

  /// Период, в котором цель была изначально создана.
  final GoalPeriodRef originalRef;

  final DateTime addedAt;
  final int? targetCount;
  final int progressCount;

  /// Названия подзадач (если цель была чек-листом). Восстанавливаются свежими.
  final List<String> subtaskTitles;

  bool get isCounter => targetCount != null && targetCount! > 1;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'period': period.name,
        'originalRef': _refToJson(originalRef),
        'addedAt': addedAt.toIso8601String(),
        'targetCount': targetCount,
        'progressCount': progressCount,
        'subtaskTitles': subtaskTitles,
      };

  factory GoalBacklogItem.fromJson(Map<String, dynamic> j) => GoalBacklogItem(
        id: j['id'] as String,
        title: j['title'] as String,
        description: j['description'] as String?,
        period: GoalPeriod.values.byName(j['period'] as String),
        originalRef: _refFromJson(j['originalRef'] as Map<String, dynamic>),
        addedAt: DateTime.parse(j['addedAt'] as String),
        targetCount: j['targetCount'] as int?,
        progressCount: j['progressCount'] as int? ?? 0,
        subtaskTitles:
            (j['subtaskTitles'] as List?)?.map((e) => e as String).toList() ??
                const [],
      );

  static Map<String, dynamic> _refToJson(GoalPeriodRef r) => {
        'period': r.period.name,
        'year': r.year,
        'month': r.month,
        'season': r.season,
        'weekStart': r.weekStart?.toIso8601String(),
      };

  static GoalPeriodRef _refFromJson(Map<String, dynamic> j) => GoalPeriodRef(
        period: GoalPeriod.values.byName(j['period'] as String),
        year: j['year'] as int,
        month: j['month'] as int?,
        season: j['season'] as int?,
        weekStart: j['weekStart'] == null
            ? null
            : DateTime.parse(j['weekStart'] as String),
      );
}
