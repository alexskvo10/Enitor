import 'schedule_item.dart';

/// Пункт шаблона расписания — пункт без даты и повтора: шаблон кладёт
/// разовые пункты на выбранный день.
class ScheduleTemplateItem {
  const ScheduleTemplateItem({
    required this.title,
    required this.startMinutes,
    this.endMinutes,
    this.note,
    this.location,
    this.colorIndex,
    this.reminderMinutes,
  });

  final String title;
  final int startMinutes;
  final int? endMinutes;
  final String? note;
  final String? location;
  final int? colorIndex;
  final int? reminderMinutes;

  /// Снимок пункта дня; день серии становится разовым пунктом.
  factory ScheduleTemplateItem.fromItem(ScheduleItem i) => ScheduleTemplateItem(
        title: i.title,
        startMinutes: i.startMinutes,
        endMinutes: i.endMinutes,
        note: i.note,
        location: i.location,
        colorIndex: i.colorIndex,
        reminderMinutes: i.reminderMinutes,
      );

  Map<String, dynamic> toJson() => {
        'title': title,
        'startMinutes': startMinutes,
        'endMinutes': endMinutes,
        'note': note,
        'location': location,
        'colorIndex': colorIndex,
        'reminderMinutes': reminderMinutes,
      };

  factory ScheduleTemplateItem.fromJson(Map<String, dynamic> j) =>
      ScheduleTemplateItem(
        title: j['title'] as String,
        startMinutes: j['startMinutes'] as int,
        endMinutes: j['endMinutes'] as int?,
        note: j['note'] as String?,
        location: j['location'] as String?,
        colorIndex: j['colorIndex'] as int?,
        reminderMinutes: j['reminderMinutes'] as int?,
      );
}

/// Именованный шаблон расписания дня: «Учебный день», «Смена».
class ScheduleTemplate {
  const ScheduleTemplate({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.items,
  });

  final String id;
  final String name;
  final DateTime createdAt;
  final List<ScheduleTemplateItem> items;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'createdAt': createdAt.toIso8601String(),
        'items': items.map((i) => i.toJson()).toList(),
      };

  factory ScheduleTemplate.fromJson(Map<String, dynamic> j) => ScheduleTemplate(
        id: j['id'] as String,
        name: j['name'] as String,
        createdAt: DateTime.parse(j['createdAt'] as String),
        items: (j['items'] as List)
            .map(
              (e) => ScheduleTemplateItem.fromJson(e as Map<String, dynamic>),
            )
            .toList(),
      );
}
