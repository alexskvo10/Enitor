import '../../../core/utils/date_utils.dart';
import '../../../data/models/recurrence_rule.dart';
import '../../../data/models/schedule_item.dart';
import '../../../data/models/task.dart';
import 'ics_parser.dart';
import 'ics_writer.dart';

/// Сколько дней назад брать разовые задачи: календарю незачем вся история.
const _pastDays = 30;

/// Расписание и задачи со временем → события календаря. UID стабильные
/// (`<id>@enitor`): повторный экспорт в тот же календарь обновляет, а не
/// дублирует.
List<IcsOutEvent> buildIcsExport({
  required List<ScheduleItem> schedule,
  required List<RecurrenceRule> rules,
  required List<Task> tasks,
  required DateTime now,
}) {
  final from = dateOnly(now).subtract(const Duration(days: _pastDays));
  return [
    for (final i in schedule)
      IcsOutEvent(
        uid: '${i.id}@enitor',
        summary: i.title,
        description: i.note,
        location: i.location,
        start: _at(_firstDay(i.date, i.occursOn), i.startMinutes),
        end: i.endMinutes == null
            ? null
            : _at(_firstDay(i.date, i.occursOn), i.endMinutes!),
        rule: i.repeat == null
            ? null
            : _rule(
                i.repeat!,
                weekdays: i.weekdays,
                weekInterval: i.weekInterval,
                monthDays: i.monthDays,
                intervalDays: i.intervalDays,
                endDate: i.endDate,
              ),
        exDates: [for (final d in i.exceptDates) _at(d, i.startMinutes)],
      ),
    // Повторяющиеся задачи со временем — одним событием с правилом, а не
    // россыпью экземпляров (их приложение создаёт лениво).
    for (final r in rules)
      if (r.startMinutes != null)
        IcsOutEvent(
          uid: '${r.id}@enitor',
          summary: r.taskTitle,
          description: r.taskDescription,
          start: _at(_firstDay(r.startDate, r.occursOn), r.startMinutes!),
          end: r.endMinutes == null
              ? null
              : _at(_firstDay(r.startDate, r.occursOn), r.endMinutes!),
          rule: _rule(
            r.kind,
            weekdays: r.weekdays,
            monthDays: r.monthDays,
            intervalDays: r.intervalDays,
            endDate: r.endDate,
          ),
          exDates: [for (final d in r.exceptDates) _at(d, r.startMinutes!)],
        ),
    for (final t in tasks)
      if (t.startMinutes != null &&
          t.recurrenceRuleId == null &&
          !t.date.isBefore(from))
        IcsOutEvent(
          uid: '${t.id}@enitor',
          summary: t.title,
          description: t.description,
          start: _at(t.date, t.startMinutes!),
          end: t.endMinutes == null ? null : _at(t.date, t.endMinutes!),
        ),
  ];
}

/// Первый день, когда серия идёт. DTSTART календарь считает событием всегда,
/// даже если его день недели не входит в BYDAY, — начало с «чужого» дня дало
/// бы лишнее событие.
DateTime _firstDay(DateTime start, bool Function(DateTime) occurs) {
  for (var i = 0; i < 400; i++) {
    final d = DateTime(start.year, start.month, start.day + i);
    if (occurs(d)) return d;
  }
  return start;
}

DateTime _at(DateTime day, int minutes) =>
    DateTime(day.year, day.month, day.day, minutes ~/ 60, minutes % 60);

IcsRule _rule(
  RecurrenceKind kind, {
  List<int> weekdays = const [],
  int weekInterval = 1,
  List<int> monthDays = const [],
  int intervalDays = 1,
  DateTime? endDate,
}) {
  final until = endDate == null
      ? null
      : DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59);
  return switch (kind) {
    RecurrenceKind.weekly => IcsRule(
        freq: IcsFreq.weekly,
        interval: weekInterval,
        byDay: [for (final d in weekdays) IcsByDay(d)],
        until: until,
        raw: '',
      ),
    RecurrenceKind.monthly => IcsRule(
        freq: IcsFreq.monthly,
        byMonthDay: monthDays,
        until: until,
        raw: '',
      ),
    RecurrenceKind.interval => IcsRule(
        freq: IcsFreq.daily,
        interval: intervalDays,
        until: until,
        raw: '',
      ),
  };
}
