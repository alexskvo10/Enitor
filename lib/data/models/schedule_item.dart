import 'dart:math';

import '../../core/utils/date_utils.dart';
import 'recurrence_rule.dart';

/// Пункт расписания — то, что просто происходит в своё время (пара, смена,
/// созвон): без галочки, статистики и переносов. Занятое время, а не дело.
///
/// Разовый пункт — [repeat] == null, живёт только в день [date]. Серия —
/// по [repeat] (дни недели, числа месяца или каждые N дней) начиная с [date]
/// и до [endDate] включительно; правила те же, что у повторяющихся задач.
class ScheduleItem {
  const ScheduleItem({
    required this.id,
    required this.title,
    required this.date,
    required this.startMinutes,
    required this.createdAt,
    required this.updatedAt,
    this.endMinutes,
    this.note,
    this.location,
    this.colorIndex,
    this.repeat,
    this.weekdays = const [],
    this.weekInterval = 1,
    this.monthDays = const [],
    this.intervalDays = 1,
    this.endDate,
    this.exceptDates = const [],
    this.reminderMinutes,
  });

  final String id;
  final String title;
  final DateTime date;

  /// Минуты с полуночи; конец (если есть) позже начала — через полночь нельзя.
  /// Без конца пункт — просто момент: время в бюджете дня он не занимает.
  final int startMinutes;
  final int? endMinutes;

  /// Заметка к пункту: что взять с собой, тема и т.п.
  final String? note;

  /// Место: аудитория, адрес. Видно в карточке и в напоминании.
  final String? location;

  /// Индекс цвета в палитре вкладки; null — без цвета.
  final int? colorIndex;

  final RecurrenceKind? repeat;
  final List<int> weekdays;

  /// Для weekly: 1 — каждую неделю, 2 — через неделю («числитель» и
  /// «знаменатель»); отсчёт — от недели [date].
  final int weekInterval;
  final List<int> monthDays;
  final int intervalDays;
  final DateTime? endDate;

  /// Дни серии, удалённые вручную («Только этот день»).
  final List<DateTime> exceptDates;

  /// За сколько минут до начала напомнить; 0 — в момент начала; null — нет.
  final int? reminderMinutes;

  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isSeries => repeat != null;
  int? get durationMinutes =>
      endMinutes == null ? null : endMinutes! - startMinutes;

  bool occursOn(DateTime day) {
    final d = dateOnly(day);
    final start = dateOnly(date);
    if (!isSeries) return d == start;
    if (d.isBefore(start)) return false;
    if (endDate != null && d.isAfter(dateOnly(endDate!))) return false;
    if (exceptDates.any((e) => dateOnly(e) == d)) return false;
    // Разница в днях — в UTC: сутки перехода на летнее время короче 24 ч,
    // и inDays по местному времени сбился бы на единицу.
    final days = _utc(d).difference(_utc(start)).inDays;
    return switch (repeat!) {
      RecurrenceKind.weekly => weekdays.contains(d.weekday) &&
          // Номер недели от понедельника недели начала серии. 0 и меньше
          // (кривой календарь, чужая версия) — каждую неделю, не деление на 0.
          ((days + start.weekday - 1) ~/ 7) % max(1, weekInterval) == 0,
      RecurrenceKind.monthly => monthDays.contains(d.day),
      RecurrenceKind.interval => intervalDays > 0 && days % intervalDays == 0,
    };
  }

  static DateTime _utc(DateTime d) => DateTime.utc(d.year, d.month, d.day);

  ScheduleItem copyWith({
    String? title,
    DateTime? date,
    int? startMinutes,
    int? endMinutes,
    bool clearEndMinutes = false,
    String? note,
    bool clearNote = false,
    String? location,
    bool clearLocation = false,
    int? colorIndex,
    bool clearColor = false,
    RecurrenceKind? repeat,
    bool clearRepeat = false,
    List<int>? weekdays,
    int? weekInterval,
    List<int>? monthDays,
    int? intervalDays,
    DateTime? endDate,
    bool clearEndDate = false,
    List<DateTime>? exceptDates,
    int? reminderMinutes,
    bool clearReminder = false,
    DateTime? updatedAt,
  }) =>
      ScheduleItem(
        id: id,
        title: title ?? this.title,
        date: date ?? this.date,
        startMinutes: startMinutes ?? this.startMinutes,
        endMinutes: clearEndMinutes ? null : (endMinutes ?? this.endMinutes),
        note: clearNote ? null : (note ?? this.note),
        location: clearLocation ? null : (location ?? this.location),
        colorIndex: clearColor ? null : (colorIndex ?? this.colorIndex),
        repeat: clearRepeat ? null : (repeat ?? this.repeat),
        weekdays: weekdays ?? this.weekdays,
        weekInterval: weekInterval ?? this.weekInterval,
        monthDays: monthDays ?? this.monthDays,
        intervalDays: intervalDays ?? this.intervalDays,
        endDate: clearEndDate ? null : (endDate ?? this.endDate),
        exceptDates: exceptDates ?? this.exceptDates,
        reminderMinutes:
            clearReminder ? null : (reminderMinutes ?? this.reminderMinutes),
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'date': date.toIso8601String(),
        'startMinutes': startMinutes,
        'endMinutes': endMinutes,
        'note': note,
        'location': location,
        'colorIndex': colorIndex,
        'repeat': repeat?.name,
        'weekdays': weekdays,
        'weekInterval': weekInterval,
        'monthDays': monthDays,
        'intervalDays': intervalDays,
        'endDate': endDate?.toIso8601String(),
        'exceptDates': exceptDates.map((d) => d.toIso8601String()).toList(),
        'reminderMinutes': reminderMinutes,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory ScheduleItem.fromJson(Map<String, dynamic> j) {
    final weekdays =
        (j['weekdays'] as List?)?.map((e) => e as int).toList() ?? const [];
    final repeat = j['repeat'] as String?;
    return ScheduleItem(
      id: j['id'] as String,
      title: j['title'] as String,
      date: DateTime.parse(j['date'] as String),
      startMinutes: j['startMinutes'] as int,
      endMinutes: j['endMinutes'] as int?,
      note: j['note'] as String?,
      location: j['location'] as String?,
      colorIndex: j['colorIndex'] as int?,
      // Первая версия знала только дни недели и поле repeat не писала.
      repeat: repeat != null
          ? RecurrenceKind.values.byName(repeat)
          : (weekdays.isEmpty ? null : RecurrenceKind.weekly),
      weekdays: weekdays,
      weekInterval: j['weekInterval'] as int? ?? 1,
      monthDays:
          (j['monthDays'] as List?)?.map((e) => e as int).toList() ?? const [],
      intervalDays: j['intervalDays'] as int? ?? 1,
      endDate: j['endDate'] == null
          ? null
          : DateTime.parse(j['endDate'] as String),
      exceptDates: (j['exceptDates'] as List?)
              ?.map((e) => DateTime.parse(e as String))
              .toList() ??
          const [],
      reminderMinutes: j['reminderMinutes'] as int?,
      createdAt: DateTime.parse(j['createdAt'] as String),
      updatedAt: DateTime.parse(j['updatedAt'] as String),
    );
  }
}

/// Пункты дня, отсортированные по началу.
List<ScheduleItem> scheduleForDay(Iterable<ScheduleItem> items, DateTime day) =>
    items.where((i) => i.occursOn(day)).toList()
      ..sort((a, b) => a.startMinutes.compareTo(b.startMinutes));

/// id пунктов дня, пересекающихся по времени с другими. Пункт без конца —
/// одна минута в момент начала.
Set<String> scheduleConflicts(List<ScheduleItem> dayItems) {
  int end(ScheduleItem i) => i.endMinutes ?? i.startMinutes + 1;
  final result = <String>{};
  for (var a = 0; a < dayItems.length; a++) {
    for (var b = a + 1; b < dayItems.length; b++) {
      final x = dayItems[a], y = dayItems[b];
      if (x.startMinutes < end(y) && y.startMinutes < end(x)) {
        result
          ..add(x.id)
          ..add(y.id);
      }
    }
  }
  return result;
}

/// Сколько минут промежутка [from, to) (минуты с полуночи) занято пунктами
/// дня. Пересечения пунктов не считаются дважды, пункты без конца — нисколько.
int busyMinutes(Iterable<ScheduleItem> dayItems, int from, int to) {
  final spans = [
    for (final i in dayItems)
      if (i.endMinutes case final end? when end > from && i.startMinutes < to)
        (i.startMinutes < from ? from : i.startMinutes, end > to ? to : end),
  ]..sort((a, b) => a.$1.compareTo(b.$1));
  var total = 0;
  var cursor = from;
  for (final (s, e) in spans) {
    final start = s > cursor ? s : cursor;
    if (e > start) {
      total += e - start;
      cursor = e;
    }
  }
  return total;
}

/// Сколько минут дня [date] занято расписанием с текущего момента (или с
/// полуночи, если день ещё впереди) до 23:00 — граница бюджета дня.
int scheduleBusyAhead(
  Iterable<ScheduleItem> dayItems,
  DateTime date,
  DateTime now,
) {
  final day = dateOnly(date);
  final today = dateOnly(now);
  if (day.isBefore(today)) return 0;
  final from = day == today ? now.hour * 60 + now.minute : 0;
  return busyMinutes(dayItems, from, 23 * 60);
}

/// Напоминания о пунктах на ближайшие [days] дней: (момент, пункт) по
/// времени, только ещё не наступившие и не больше [limit] — у Android общий
/// лимит запланированных будильников, поэтому окно скользящее и пересобирается
/// при каждом открытии приложения.
List<(DateTime, ScheduleItem)> scheduleReminders(
  Iterable<ScheduleItem> items,
  DateTime now, {
  int days = 7,
  int limit = 100,
}) {
  final result = <(DateTime, ScheduleItem)>[];
  for (var d = 0; d < days; d++) {
    final day = DateTime(now.year, now.month, now.day + d);
    for (final i in items) {
      final lead = i.reminderMinutes;
      if (lead == null || !i.occursOn(day)) continue;
      // Отрицательные минуты DateTime переносит на предыдущий день: за час
      // до пункта в 0:30 — это 23:30 накануне.
      final at =
          DateTime(day.year, day.month, day.day, 0, i.startMinutes - lead);
      if (at.isAfter(now)) result.add((at, i));
    }
  }
  result.sort((a, b) => a.$1.compareTo(b.$1));
  return result.take(limit).toList();
}
