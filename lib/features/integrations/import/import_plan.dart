import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../../core/utils/date_utils.dart';
import '../../../data/models/backlog_item.dart';
import '../../../data/models/recurrence_rule.dart';
import '../../../data/models/schedule_item.dart';
import '../../../data/models/task.dart';
import '../../../data/repositories/backlog_repository.dart';
import '../../../data/repositories/recurrence_repository.dart';
import '../../../data/repositories/schedule_repository.dart';
import '../../../data/repositories/task_repository.dart';
import '../../../data/sources/local/local_storage.dart';
import '../ics/ics_parser.dart';
import 'imported_task.dart';

enum PlanAction { create, update, skip }

/// Почему пункт не будет импортирован — по причине экран выбирает
/// человеческий текст.
enum PlanSkip {
  allDay,
  unsupportedRepeat,
  unchanged,
  alreadyImported,
  past,
  noTitle,
  completedWithoutDate,
  brokenRow,

  /// Пункт из календаря удалили в Enitor — обратно не возвращаем.
  removedHere,
}

/// Строка предпросмотра: как пункт будет выглядеть и что с ним случится.
class PlanEntry {
  const PlanEntry({
    required this.title,
    required this.action,
    this.date,
    this.startMinutes,
    this.endMinutes,
    this.repeats = false,
    this.skip,
    this.apply,
  });

  final String title;
  final PlanAction action;
  final DateTime? date;
  final int? startMinutes;
  final int? endMinutes;
  final bool repeats;

  /// Для пропуска — почему; для импортируемого — что не перенеслось.
  final PlanSkip? skip;

  /// Запись в данные; у пропущенных — null.
  final Future<void> Function()? apply;
}

/// Стабильный короткий id из внешнего: повторный импорт узнаёт своё.
String stableId(String prefix, String externalId) =>
    '$prefix-${sha1.convert(utf8.encode(externalId)).toString().substring(0, 20)}';

// ─── Календарь (.ics) → расписание ───────────────────────────────────────────

/// Переводит события календаря в пункты расписания. Что Enitor выразить не
/// может (весь день, «второй понедельник месяца», ежегодно) — пропускается с
/// причиной, а не искажается.
///
/// [seen] — какую версию каждого события календаря Enitor уже видел. С ним
/// пункт обновляется, только когда событие изменилось в самом календаре:
/// правки, сделанные в Enitor, остаются, а удалённое здесь не возвращается.
/// Без него (импорт файла впервые) — сравнение с тем, что лежит в расписании.
List<PlanEntry> planIcsImport(
  IcsCalendar cal, {
  required ScheduleRepository schedule,
  required DateTime now,
  IcsSeen? seen,
}) {
  final today = dateOnly(now);
  final out = <PlanEntry>[];
  for (final e in cal.events) {
    final title = e.summary.trim();
    PlanEntry skip(PlanSkip why) => PlanEntry(
          title: title.isEmpty ? e.uid : title,
          action: PlanAction.skip,
          date: dateOnly(e.start),
          skip: why,
        );
    if (title.isEmpty) {
      out.add(skip(PlanSkip.noTitle));
      continue;
    }
    if (e.allDay) {
      out.add(skip(PlanSkip.allDay));
      continue;
    }
    final item = _scheduleItemFrom(e, title, now);
    if (item == null) {
      out.add(skip(PlanSkip.unsupportedRepeat));
      continue;
    }
    final lastDay = item.isSeries ? item.endDate : item.date;
    if (lastDay != null && lastDay.isBefore(today)) {
      out.add(skip(PlanSkip.past));
      continue;
    }
    final existing = schedule.byId(item.id);
    final hash = icsItemHash(item);
    final known = seen?[item.id];
    if (seen != null && known != null && existing == null) {
      out.add(skip(PlanSkip.removedHere));
      continue;
    }
    if (seen != null && known == null && existing != null) {
      // Импортировали до того, как Enitor стал запоминать версии: считаем
      // лежащее в расписании своим (вдруг там правки), календарь — увиденным.
      seen.mark(item.id, hash);
    }
    final changed = existing == null ||
        (seen != null
            ? known != null && known != hash
            : !_sameContent(existing, item));
    // Календарь поменял событие — берём его версию, но то, что задают только
    // в Enitor (цвет, напоминание, удалённые дни серии), не теряем.
    final next = existing == null
        ? item
        : item.copyWith(
            colorIndex: existing.colorIndex,
            reminderMinutes: existing.reminderMinutes,
            exceptDates: {...item.exceptDates, ...existing.exceptDates}.toList()
              ..sort(),
          );
    out.add(
      PlanEntry(
        title: title,
        action: existing == null
            ? PlanAction.create
            : changed
                ? PlanAction.update
                : PlanAction.skip,
        skip: changed ? null : PlanSkip.unchanged,
        date: item.date,
        startMinutes: item.startMinutes,
        endMinutes: item.endMinutes,
        repeats: item.isSeries,
        apply: changed
            ? () async {
                await schedule.upsert(next);
                seen?.mark(item.id, hash);
                await seen?.save();
              }
            : null,
      ),
    );
  }
  return out;
}

ScheduleItem? _scheduleItemFrom(IcsEvent e, String title, DateTime now) {
  final start = e.start;
  final end = e.end;
  final startMin = start.hour * 60 + start.minute;
  // Конец — только в тот же день и позже начала: через полночь пункт
  // расписания не тянется.
  final endMin = end != null &&
          dateOnly(end) == dateOnly(start) &&
          end.hour * 60 + end.minute > startMin
      ? end.hour * 60 + end.minute
      : null;
  var item = ScheduleItem(
    id: stableId('ics', e.uid),
    title: title,
    date: dateOnly(start),
    startMinutes: startMin,
    endMinutes: endMin,
    location: _nonEmpty(e.location),
    note: _nonEmpty(e.description),
    exceptDates: [for (final d in e.exDates) dateOnly(d)],
    createdAt: now,
    updatedAt: now,
  );
  final r = e.rule;
  if (r == null) return item;
  if (r.byMonth.isNotEmpty || r.bySetPos.isNotEmpty) return null;
  if (r.byDay.any((d) => d.ordinal != null)) return null;
  switch (r.freq) {
    case IcsFreq.weekly:
      if (r.interval > 2) return null;
      item = item.copyWith(
        repeat: RecurrenceKind.weekly,
        weekdays: r.byDay.isEmpty
            ? [start.weekday]
            : ([for (final d in r.byDay) d.weekday]..sort()),
        weekInterval: r.interval,
      );
    case IcsFreq.daily:
      if (r.byDay.isEmpty) {
        item = item.copyWith(
          repeat: RecurrenceKind.interval,
          intervalDays: r.interval,
        );
      } else {
        // «Каждый будний день» приходит как DAILY;BYDAY=MO,…,FR.
        if (r.interval != 1) return null;
        item = item.copyWith(
          repeat: RecurrenceKind.weekly,
          weekdays: [for (final d in r.byDay) d.weekday]..sort(),
        );
      }
    case IcsFreq.monthly:
      if (r.byDay.isNotEmpty || r.interval != 1) return null;
      if (r.byMonthDay.any((d) => d < 1)) return null;
      item = item.copyWith(
        repeat: RecurrenceKind.monthly,
        monthDays: r.byMonthDay.isEmpty ? [start.day] : r.byMonthDay,
      );
    case IcsFreq.yearly:
      return null;
  }
  if (r.until != null) {
    item = item.copyWith(endDate: dateOnly(r.until!));
  } else if (r.count != null) {
    item = item.copyWith(endDate: _lastOfCount(item, r.count!));
  }
  return item;
}

/// COUNT → дата последнего вхождения: проходим дни правилом самого пункта
/// (исключения в счёт COUNT входят — как в RFC 5545).
DateTime? _lastOfCount(ScheduleItem item, int count) {
  final noExcept = item.copyWith(exceptDates: const []);
  var seen = 0;
  var day = item.date;
  for (var i = 0; i < 3660 && seen < count; i++) {
    if (noExcept.occursOn(day)) seen++;
    if (seen == count) return day;
    day = DateTime(day.year, day.month, day.day + 1);
  }
  return null;
}

/// Отпечаток события в том виде, в каком его отдал календарь.
String icsItemHash(ScheduleItem i) {
  final j = i.toJson()
    ..remove('createdAt')
    ..remove('updatedAt');
  return sha1.convert(utf8.encode(jsonEncode(j))).toString();
}

/// Какие версии событий календаря Enitor уже видел (ключ «устройство»).
class IcsSeen {
  IcsSeen(this._storage)
      : _map = {
          for (final e in (_storage.readMap(_key) ?? const {}).entries)
            if (e.value is String) e.key: e.value as String,
        };

  static const _key = 'device.ics.seen';
  final LocalStorage _storage;
  final Map<String, String> _map;

  String? operator [](String id) => _map[id];
  void mark(String id, String hash) => _map[id] = hash;
  Future<void> save() => _storage.writeMap(_key, _map);
}

bool _sameContent(ScheduleItem a, ScheduleItem b) =>
    a.title == b.title &&
    a.date == b.date &&
    a.startMinutes == b.startMinutes &&
    a.endMinutes == b.endMinutes &&
    a.location == b.location &&
    a.note == b.note &&
    a.repeat == b.repeat &&
    _sameList(a.weekdays, b.weekdays) &&
    a.weekInterval == b.weekInterval &&
    _sameList(a.monthDays, b.monthDays) &&
    a.intervalDays == b.intervalDays &&
    a.endDate == b.endDate &&
    _sameList(a.exceptDates, b.exceptDates);

bool _sameList<T>(List<T> a, List<T> b) =>
    a.length == b.length &&
    [for (var i = 0; i < a.length; i++) a[i] == b[i]].every((x) => x);

String? _nonEmpty(String? s) => s == null || s.trim().isEmpty ? null : s.trim();

// ─── Задачи из других приложений ────────────────────────────────────────────

/// Переводит разобранный экспорт в задачи Enitor. Задача без даты — в бэклог
/// (там живут задачи «без дня»); повторяющаяся — правило повторения; уже
/// импортированная прежде (тот же id) — пропускается.
List<PlanEntry> planTaskImport(
  ImportResult result, {
  required TaskRepository tasks,
  required RecurrenceRepository rules,
  required BacklogRepository backlog,
  required DateTime now,
}) {
  final today = effectiveDay(now);
  final out = <PlanEntry>[];
  // Непереводимый повтор — не пропуск: задача импортируется разовой, а
  // строка предпросмотра честно говорит, что повтор не перенёсся.
  final lostRepeat = {
    for (final w in result.warnings)
      if (w.reason == ImportSkipReason.unsupportedRepeat) w.title,
  };
  for (final t in result.tasks) {
    final caveat =
        lostRepeat.contains(t.title) ? PlanSkip.unsupportedRepeat : null;
    final id = stableId('imp-${t.source.name}', t.sourceId);
    // Задача могла уйти в бэклог (там она «b-<id>») и вернуться оттуда с
    // тем же «b-<id>» — это всё ещё она.
    final ids = {id, 'b-$id'};
    final known = ids.any((x) => tasks.taskById(x) != null) ||
        rules.byId(id) != null ||
        backlog.all.any((b) => ids.contains(b.id));
    PlanEntry skip(PlanSkip why) => PlanEntry(
          title: t.title,
          action: PlanAction.skip,
          date: t.date,
          skip: why,
        );
    if (known) {
      out.add(skip(PlanSkip.alreadyImported));
      continue;
    }
    final repeat = t.repeat;
    if (repeat != null && !t.completed) {
      out.add(
        PlanEntry(
          title: t.title,
          action: PlanAction.create,
          date: t.date ?? today,
          startMinutes: t.startMinutes,
          repeats: true,
          apply: () => tasks.createRecurrence(
            id: id,
            title: t.title,
            description: t.description,
            kind: repeat.kind,
            startDate: t.date ?? today,
            weekdays: repeat.weekdays,
            monthDays: repeat.monthDays,
            intervalDays: repeat.intervalDays,
            startMinutes: t.startMinutes,
            subtaskTitles: t.subtasks,
            priority: t.priority,
            tags: t.tags,
          ),
        ),
      );
      continue;
    }
    final date = t.date;
    if (date == null) {
      if (t.completed) {
        out.add(skip(PlanSkip.completedWithoutDate));
        continue;
      }
      out.add(
        PlanEntry(
          title: t.title,
          action: PlanAction.create,
          skip: caveat,
          apply: () => backlog.add(
            BacklogItem(
              id: id,
              title: t.title,
              description: t.description,
              originalDate: today,
              addedAt: now,
              startMinutes: t.startMinutes,
              subtaskTitles: t.subtasks,
              priority: t.priority,
              tags: t.tags,
            ),
          ),
        ),
      );
      continue;
    }
    final done = t.completed ? (t.completedAt ?? date) : null;
    out.add(
      PlanEntry(
        title: t.title,
        action: PlanAction.create,
        date: date,
        startMinutes: t.startMinutes,
        skip: caveat,
        apply: () => tasks.addTask(
          Task(
            id: id,
            title: t.title,
            description: t.description,
            date: dateOnly(date),
            createdAt: now,
            updatedAt: now,
            completedAt: done,
            startMinutes: t.startMinutes,
            priority: t.priority,
            tags: t.tags,
            subtasks: [
              for (var i = 0; i < t.subtasks.length; i++)
                SubTask(id: '$id-$i', title: t.subtasks[i], done: t.completed),
            ],
          ),
        ),
      ),
    );
  }
  for (final w in result.warnings) {
    if (w.reason == ImportSkipReason.unsupportedRepeat ||
        w.reason == ImportSkipReason.partlyLost ||
        w.reason == ImportSkipReason.unreadableFile) {
      continue;
    }
    out.add(
      PlanEntry(
        title: w.title,
        action: PlanAction.skip,
        skip: switch (w.reason) {
          ImportSkipReason.noTitle => PlanSkip.noTitle,
          _ => PlanSkip.brokenRow,
        },
      ),
    );
  }
  return out;
}
