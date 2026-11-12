import 'package:timezone/timezone.dart' as tz;

import 'ics_parser.dart';

/// Событие для записи в .ics. Даты — настенное время зоны [writeIcs].
class IcsOutEvent {
  const IcsOutEvent({
    required this.uid,
    required this.summary,
    this.description,
    this.location,
    required this.start,
    this.end,
    this.rule,
    this.exDates = const [],
  });

  final String uid;
  final String summary;
  final String? description;
  final String? location;
  final DateTime start;
  final DateTime? end;
  final IcsRule? rule;
  final List<DateTime> exDates;
}

/// Пишет календарь .ics: CRLF, перенос строк по 75 октетов, VTIMEZONE зоны
/// [zone] по переходам года [now].
String writeIcs(
  List<IcsOutEvent> events, {
  required tz.Location zone,
  required DateTime now,
  String prodId = '-//Enitor//Enitor//EN',
}) {
  final stamp = _utcStamp(now);
  final lines = <String>[
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:$prodId',
    'CALSCALE:GREGORIAN',
    ..._vtimezone(zone, now),
  ];
  for (final e in events) {
    lines.add('BEGIN:VEVENT');
    lines.add('UID:${_escape(e.uid)}');
    lines.add('DTSTAMP:$stamp');
    lines.add('DTSTART;TZID=${zone.name}:${_wall(e.start)}');
    if (e.end != null) {
      lines.add('DTEND;TZID=${zone.name}:${_wall(e.end!)}');
    }
    if (e.rule != null) {
      lines.add('RRULE:${_rule(e.rule!, zone)}');
    }
    if (e.exDates.isNotEmpty) {
      final dates = e.exDates.map(_wall).join(',');
      lines.add('EXDATE;TZID=${zone.name}:$dates');
    }
    lines.add('SUMMARY:${_escape(e.summary)}');
    if (e.description != null) {
      lines.add('DESCRIPTION:${_escape(e.description!)}');
    }
    if (e.location != null) {
      lines.add('LOCATION:${_escape(e.location!)}');
    }
    lines.add('END:VEVENT');
  }
  lines.add('END:VCALENDAR');
  return lines.map(_fold).join();
}

const _dayCodes = ['MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU'];

String _p(int n, int width) => n.toString().padLeft(width, '0');

/// Настенное время без зоны: 20261103T090000.
String _wall(DateTime d) =>
    '${_p(d.year, 4)}${_p(d.month, 2)}${_p(d.day, 2)}'
    'T${_p(d.hour, 2)}${_p(d.minute, 2)}${_p(d.second, 2)}';

/// UTC с суффиксом Z.
String _utcStamp(DateTime d) => '${_wall(d.toUtc())}Z';

/// Смещение в формате +0300 из миллисекунд.
String _offset(int ms) {
  final s = ms ~/ 1000;
  final a = s.abs();
  final sign = s < 0 ? '-' : '+';
  return '$sign${_p(a ~/ 3600, 2)}${_p((a % 3600) ~/ 60, 2)}';
}

/// Экранирование текста значения: \ ; , и перевод строки.
String _escape(String s) => s
    .replaceAll('\\', '\\\\')
    .replaceAll(';', '\\;')
    .replaceAll(',', '\\,')
    .replaceAll(RegExp('\r\n|\r|\n'), '\\n');

/// Складывает строку по 75 октетам UTF-8, не разрывая символ.
String _fold(String line) {
  final chunks = <String>[];
  var buf = StringBuffer();
  var used = 0;
  var limit = 75;
  for (final r in line.runes) {
    final n = r < 0x80 ? 1 : (r < 0x800 ? 2 : (r < 0x10000 ? 3 : 4));
    if (used + n > limit) {
      chunks.add(buf.toString());
      buf = StringBuffer();
      used = 0;
      limit = 74; // первый пробел продолжения занимает октет
    }
    buf.writeCharCode(r);
    used += n;
  }
  chunks.add(buf.toString());
  return '${chunks.join('\r\n ')}\r\n';
}

/// Правило RRULE. UNTIL пишется в UTC через зону [zone].
String _rule(IcsRule r, tz.Location zone) {
  final parts = ['FREQ=${r.freq.name.toUpperCase()}'];
  if (r.interval != 1) {
    parts.add('INTERVAL=${r.interval}');
  }
  if (r.byDay.isNotEmpty) {
    final days = r.byDay.map((b) {
      final code = _dayCodes[b.weekday - 1];
      return b.ordinal == null ? code : '${b.ordinal}$code';
    });
    parts.add('BYDAY=${days.join(',')}');
  }
  if (r.byMonthDay.isNotEmpty) {
    parts.add('BYMONTHDAY=${r.byMonthDay.join(',')}');
  }
  if (r.byMonth.isNotEmpty) {
    parts.add('BYMONTH=${r.byMonth.join(',')}');
  }
  if (r.bySetPos.isNotEmpty) {
    parts.add('BYSETPOS=${r.bySetPos.join(',')}');
  }
  final u = r.until;
  if (u != null) {
    final utc = tz.TZDateTime(
      zone,
      u.year,
      u.month,
      u.day,
      u.hour,
      u.minute,
      u.second,
    );
    parts.add('UNTIL=${_utcStamp(utc)}');
  }
  if (r.count != null) {
    parts.add('COUNT=${r.count}');
  }
  return parts.join(';');
}

/// VTIMEZONE: компоненты по переходам года [now]; без переходов — один STANDARD.
List<String> _vtimezone(tz.Location zone, DateTime now) {
  final from = DateTime.utc(now.year).millisecondsSinceEpoch;
  final to = DateTime.utc(now.year + 1).millisecondsSinceEpoch;
  final lines = ['BEGIN:VTIMEZONE', 'TZID:${zone.name}'];
  var prev = zone.timeZone(from);
  var found = false;
  for (var i = 0; i < zone.transitionAt.length; i++) {
    final at = zone.transitionAt[i];
    if (at < from || at >= to) {
      continue;
    }
    final next = zone.zones[zone.transitionZone[i]];
    if (next.offset != prev.offset || next.isDst != prev.isDst) {
      lines.addAll(_component(at, prev, next));
      found = true;
    }
    prev = next;
  }
  if (!found) {
    final cur = zone.timeZone(now.millisecondsSinceEpoch);
    lines.addAll([
      'BEGIN:STANDARD',
      'DTSTART:19700101T000000',
      'TZOFFSETFROM:${_offset(cur.offset)}',
      'TZOFFSETTO:${_offset(cur.offset)}',
      'TZNAME:${cur.abbreviation}',
      'END:STANDARD',
    ]);
  }
  lines.add('END:VTIMEZONE');
  return lines;
}

/// Один переход: DTSTART в локальном времени до перехода, правило по году.
List<String> _component(int atMs, tz.TimeZone from, tz.TimeZone to) {
  final w = DateTime.fromMillisecondsSinceEpoch(atMs + from.offset, isUtc: true);
  final daysInMonth = DateTime.utc(w.year, w.month + 1, 0).day;
  // Ординал недели в месяце; -1 — последняя такая неделя.
  final ord = w.day + 7 > daysInMonth ? -1 : (w.day - 1) ~/ 7 + 1;
  final name = to.isDst ? 'DAYLIGHT' : 'STANDARD';
  return [
    'BEGIN:$name',
    'DTSTART:${_wall(w)}',
    'TZOFFSETFROM:${_offset(from.offset)}',
    'TZOFFSETTO:${_offset(to.offset)}',
    'TZNAME:${to.abbreviation}',
    'RRULE:FREQ=YEARLY;BYMONTH=${w.month};BYDAY=$ord${_dayCodes[w.weekday - 1]}',
    'END:$name',
  ];
}
