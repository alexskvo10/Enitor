import 'task.dart';

/// Один пункт шаблона дня — конфигурация задачи без статуса/даты.
class TemplateItem {
  const TemplateItem({
    required this.title,
    this.description,
    this.startMinutes,
    this.endMinutes,
    this.estimatedMinutes,
    this.targetCount,
    this.subtaskTitles = const [],
    this.priority = TaskPriority.none,
    this.tags = const [],
  });

  final String title;
  final String? description;
  final int? startMinutes;
  final int? endMinutes;
  final int? estimatedMinutes;
  final int? targetCount;
  final List<String> subtaskTitles;
  final TaskPriority priority;
  final List<String> tags;

  /// Снимок задачи как пункт шаблона (без выполнения/прогресса/серии).
  factory TemplateItem.fromTask(Task t) => TemplateItem(
        title: t.title,
        description: t.description,
        startMinutes: t.startMinutes,
        endMinutes: t.endMinutes,
        estimatedMinutes: t.estimatedMinutes,
        targetCount: t.targetCount,
        subtaskTitles: t.subtasks.map((s) => s.title).toList(),
        priority: t.priority,
        tags: t.tags,
      );

  Map<String, dynamic> toJson() => {
        'title': title,
        'description': description,
        'startMinutes': startMinutes,
        'endMinutes': endMinutes,
        'estimatedMinutes': estimatedMinutes,
        'targetCount': targetCount,
        'subtaskTitles': subtaskTitles,
        'priority': priority.index,
        'tags': tags,
      };

  factory TemplateItem.fromJson(Map<String, dynamic> j) => TemplateItem(
        title: j['title'] as String,
        description: j['description'] as String?,
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

/// Именованный шаблон дня — набор задач для применения одним нажатием.
class DayTemplate {
  const DayTemplate({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.items,
  });

  final String id;
  final String name;
  final DateTime createdAt;
  final List<TemplateItem> items;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'createdAt': createdAt.toIso8601String(),
        'items': items.map((i) => i.toJson()).toList(),
      };

  factory DayTemplate.fromJson(Map<String, dynamic> j) => DayTemplate(
        id: j['id'] as String,
        name: j['name'] as String,
        createdAt: DateTime.parse(j['createdAt'] as String),
        items: (j['items'] as List)
            .map((e) => TemplateItem.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
