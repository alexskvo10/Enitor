import 'dart:convert';
import 'dart:math';

import 'package:timezone/timezone.dart' as tz;

/// Частота правила RRULE.
enum IcsFreq { daily, weekly, monthly, yearly }

/// Элемент BYDAY: день недели и необязательный ординал (2MO → 2, -1SU → -1).
class IcsByDay {
  const IcsByDay(this.weekday, [this.ordinal]);

  /// 1 = пн … 7 = вс, как в DateTime.
  final int weekday;
  final int? ordinal;
}

/// Правило повторения RRULE.
class IcsRule {
  IcsRule({
    required this.freq,
    this.interval = 1,
    this.byDay = const [],
    this.byMonthDay = const [],
    this.byMonth = const [],
    this.bySetPos = const [],
    this.until,
    this.count,
    required this.raw,
  });

  final IcsFreq freq;
  final int interval;
  final List<IcsByDay> byDay;
  final List<int> byMonthDay;
  final List<int> byMonth;
  final List<int> bySetPos;

  /// Локальное время устройства. Дата без времени в UNTIL — конец этого дня.
  final DateTime? until;
  final int? count;

  /// Исходная строка значения RRULE (без имени свойства).
  final String raw;
}

/// Событие VEVENT. Все даты — настенное время зоны [IcsCalendar]-разбора.
class IcsEvent {
  IcsEvent({
    required this.uid,
    required this.summary,
    this.description,
    this.location,
    required this.start,
    this.end,
    this.allDay = false,
    this.rule,
    this.exDates = const [],
  });

  final String uid;
  final String summary;
  final String? description;
  final String? location;
  final DateTime start;

  /// Конец эксклюзивный, как в файле. Для allDay без DTEND — start + 1 день.
  final DateTime? end;
  final bool allDay;
  final IcsRule? rule;
  final List<DateTime> exDates;
}

class IcsCalendar {
  const IcsCalendar({required this.events, required this.warnings});

  final List<IcsEvent> events;

  /// Пропущенные и подозрительные места на русском языке.
  final List<String> warnings;
}

/// Разбирает текст .ics. Даты переводятся в «настенное» время зоны [local]
/// (по умолчанию tz.local). База часовых поясов должна быть инициализирована.
/// [ru] — язык предупреждений: их показывают пользователю.
IcsCalendar parseIcs(String text, {tz.Location? local, bool ru = true}) {
  final c = _Ctx(local ?? tz.local, ru);
  final events = <IcsEvent>[];
  final stack = <String>[];
  List<_Prop>? eventProps;
  var sawCalendar = false;

  for (final line in _unfold(text)) {
    final prop = _parseLine(line);
    if (prop == null) {
      continue;
    }
    if (prop.name == 'BEGIN') {
      final comp = prop.value.trim().toUpperCase();
      stack.add(comp);
      if (comp == 'VCALENDAR') {
        sawCalendar = true;
      }
      // Только VEVENT прямо внутри VCALENDAR; VALARM и прочее игнорируем.
      if (comp == 'VEVENT' &&
          stack.length >= 2 &&
          stack[stack.length - 2] == 'VCALENDAR') {
        eventProps = [];
      }
      continue;
    }
    if (prop.name == 'END') {
      if (stack.isEmpty) {
        continue;
      }
      final comp = stack.removeLast();
      if (comp == 'VEVENT' && eventProps != null) {
        final ev = _buildEvent(eventProps, c);
        if (ev != null) {
          events.add(ev);
        }
        eventProps = null;
      }
      continue;
    }
    if (eventProps != null && stack.isNotEmpty && stack.last == 'VEVENT') {
      eventProps.add(prop);
    }
  }
  if (eventProps != null) {
    final ev = _buildEvent(eventProps, c);
    if (ev != null) {
      events.add(ev);
    }
  }

  if (!sawCalendar) {
    return IcsCalendar(
      events: const [],
      warnings: [
        ru
            ? 'Нет BEGIN:VCALENDAR: файл не разобран'
            : 'No BEGIN:VCALENDAR: the file was not read',
      ],
    );
  }
  for (final ev in events) {
    final days = c.overridden[ev.uid];
    if (ev.rule != null && days != null) ev.exDates.addAll(days);
  }
  return IcsCalendar(events: events, warnings: c.warnings);
}

/// Контекст одного разбора: локальная зона и накопленные предупреждения.
class _Ctx {
  _Ctx(this.local, this.ru);

  final tz.Location local;
  final bool ru;
  final List<String> warnings = [];

  void warn(String textRu, String textEn) => warnings.add(ru ? textRu : textEn);

  /// UID серии → дни, изменённые или отменённые отдельными VEVENT
  /// (RECURRENCE-ID): в серии они становятся исключениями.
  final overridden = <String, List<DateTime>>{};
  final Set<String> warnedZones = {};
}

/// Свойство: имя (в верхнем регистре), параметры и сырое значение.
class _Prop {
  const _Prop(this.name, this.params, this.value);

  final String name;
  final Map<String, String> params;
  final String value;
}

/// Время из файла до перевода в локальную зону.
class _Time {
  const _Time(this.wall, {this.zone, this.utc = false, this.dateOnly = false});

  /// Компоненты времени; UTC-обёртка нужна только как контейнер полей.
  final DateTime wall;

  /// null — плавающее время (или UTC, см. [utc]).
  final tz.Location? zone;
  final bool utc;
  final bool dateOnly;

  DateTime toLocal(tz.Location local) {
    final w = wall;
    if (dateOnly || (!utc && zone == null)) {
      return DateTime(w.year, w.month, w.day, w.hour, w.minute, w.second);
    }
    final src = utc
        ? w
        : tz.TZDateTime(
            zone!,
            w.year,
            w.month,
            w.day,
            w.hour,
            w.minute,
            w.second,
          );
    final t = tz.TZDateTime.from(src, local);
    return DateTime(t.year, t.month, t.day, t.hour, t.minute, t.second);
  }

  _Time plus(Duration d) => _Time(
    wall.add(d),
    zone: zone,
    utc: utc,
    dateOnly: dateOnly,
  );
}

const _dayCodes = ['MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU'];

const _freqs = {
  'DAILY': IcsFreq.daily,
  'WEEKLY': IcsFreq.weekly,
  'MONTHLY': IcsFreq.monthly,
  'YEARLY': IcsFreq.yearly,
};

/// Имена зон из Outlook/Windows → IANA.
const _windowsZones = {
  'Russian Standard Time': 'Europe/Moscow',
  'W. Europe Standard Time': 'Europe/Berlin',
  'Eastern Standard Time': 'America/New_York',
  'Pacific Standard Time': 'America/Los_Angeles',
  'GMT Standard Time': 'Europe/London',
  'Central European Standard Time': 'Europe/Warsaw',
  'FLE Standard Time': 'Europe/Kiev',
  'Ekaterinburg Standard Time': 'Asia/Yekaterinburg',
  'China Standard Time': 'Asia/Shanghai',
  'Tokyo Standard Time': 'Asia/Tokyo',
  'UTC': 'UTC',
};

final _dateTimeRe = RegExp(
  r'^(\d{4})(\d{2})(\d{2})(?:T(\d{2})(\d{2})(\d{2})?(Z)?)?$',
);
final _durationRe = RegExp(
  r'^([+-])?P(?:(\d+)W)?(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?$',
);
final _byDayRe = RegExp(r'^([+-]?\d{1,2})?(MO|TU|WE|TH|FR|SA|SU)$');

/// Развёртка: строки, начинающиеся с пробела или таба, продолжают предыдущую.
/// Текст уже декодирован в String, поэтому перенос посреди символа невозможен.
List<String> _unfold(String text) {
  final out = <String>[];
  for (final raw in const LineSplitter().convert(text)) {
    if (raw.isNotEmpty && (raw[0] == ' ' || raw[0] == '\t') && out.isNotEmpty) {
      out[out.length - 1] += raw.substring(1);
    } else if (raw.trim().isNotEmpty) {
      out.add(raw);
    }
  }
  return out;
}

_Prop? _parseLine(String line) {
  final colon = _indexOutsideQuotes(line, ':');
  if (colon < 0) {
    return null;
  }
  final head = _splitOutsideQuotes(line.substring(0, colon), ';');
  final name = head.first.trim().toUpperCase();
  if (name.isEmpty) {
    return null;
  }
  final params = <String, String>{};
  for (final p in head.skip(1)) {
    final i = p.indexOf('=');
    if (i <= 0) {
      continue;
    }
    var v = p.substring(i + 1);
    if (v.length >= 2 && v.startsWith('"') && v.endsWith('"')) {
      v = v.substring(1, v.length - 1);
    }
    params[p.substring(0, i).trim().toUpperCase()] = v;
  }
  return _Prop(name, params, line.substring(colon + 1));
}

int _indexOutsideQuotes(String s, String ch) {
  var quoted = false;
  for (var i = 0; i < s.length; i++) {
    final c = s[i];
    if (c == '"') {
      quoted = !quoted;
    } else if (!quoted && c == ch) {
      return i;
    }
  }
  return -1;
}

List<String> _splitOutsideQuotes(String s, String sep) {
  final parts = <String>[];
  var quoted = false;
  var start = 0;
  for (var i = 0; i < s.length; i++) {
    final c = s[i];
    if (c == '"') {
      quoted = !quoted;
    } else if (!quoted && c == sep) {
      parts.add(s.substring(start, i));
      start = i + 1;
    }
  }
  parts.add(s.substring(start));
  return parts;
}

/// Экранирование текста: \n, \N, \, \; и \\.
String _unescape(String s) {
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    final c = s[i];
    if (c == '\\' && i + 1 < s.length) {
      i++;
      final n = s[i];
      b.write(n == 'n' || n == 'N' ? '\n' : n);
    } else {
      b.write(c);
    }
  }
  return b.toString();
}

_Prop? _first(List<_Prop> props, String name) {
  for (final p in props) {
    if (p.name == name) {
      return p;
    }
  }
  return null;
}

String? _text(List<_Prop> props, String name) {
  final p = _first(props, name);
  return p == null ? null : _unescape(p.value);
}

tz.Location? _zoneByName(String name) {
  final id = _windowsZones[name] ?? name;
  try {
    return tz.getLocation(id);
  } on tz.LocationNotFoundException {
    return null;
  }
}

bool _isValid(int y, int mo, int d, int h, int mi, int s) {
  if (mo < 1 || mo > 12 || h > 23 || mi > 59 || s > 59) {
    return false;
  }
  return DateTime.utc(y, mo, d).day == d;
}

/// Разбор значения даты/времени. Без зоны и без Z — плавающее время.
_Time? _parseTime(String raw, {tz.Location? zone, bool utc = false}) {
  final m = _dateTimeRe.firstMatch(raw.trim());
  if (m == null) {
    return null;
  }
  final y = int.parse(m[1]!);
  final mo = int.parse(m[2]!);
  final d = int.parse(m[3]!);
  final dateOnly = m[4] == null;
  final h = dateOnly ? 0 : int.parse(m[4]!);
  final mi = dateOnly ? 0 : int.parse(m[5]!);
  final s = dateOnly || m[6] == null ? 0 : int.parse(m[6]!);
  if (!_isValid(y, mo, d, h, mi, s)) {
    return null;
  }
  final isUtc = utc || m[7] != null;
  return _Time(
    DateTime.utc(y, mo, d, h, mi, s),
    zone: isUtc ? null : zone,
    utc: isUtc,
    dateOnly: dateOnly,
  );
}

/// Значение с необязательным TZID. Неизвестная зона — считаем локальной.
_Time? _timeFromValue(String value, String? tzid, _Ctx c) {
  if (tzid == null || value.trim().endsWith('Z')) {
    return _parseTime(value);
  }
  final zone = _zoneByName(tzid);
  if (zone == null && c.warnedZones.add(tzid)) {
    c.warn(
      'Неизвестная зона "$tzid": время считано как локальное',
      'Unknown time zone "$tzid": times read as local',
    );
  }
  return _parseTime(value, zone: zone);
}

/// Длительность DURATION: недели, дни и часы/минуты/секунды.
Duration? _parseDuration(String raw) {
  final m = _durationRe.firstMatch(raw.trim());
  if (m == null) {
    return null;
  }
  if (m.groups([2, 3, 4, 5, 6]).every((g) => g == null)) {
    return null;
  }
  // Огромные числа не влезают в int: такая длительность — не разобрана.
  int? n(String? s) => s == null ? 0 : int.tryParse(s);
  final parts = [
    for (final i in [2, 3, 4, 5, 6]) n(m[i]),
  ];
  if (parts.any((v) => v == null || v > 1000000)) {
    return null;
  }
  final [w, days, h, mi, sec] = parts.cast<int>();
  final d = Duration(days: w * 7 + days, hours: h, minutes: mi, seconds: sec);
  return m[1] == '-' ? Duration.zero - d : d;
}

List<int> _ints(String? s) {
  if (s == null) {
    return const [];
  }
  final out = <int>[];
  for (final v in s.split(',')) {
    final n = int.tryParse(v.trim());
    if (n != null) {
      out.add(n);
    }
  }
  return out;
}

IcsRule? _parseRule(String raw, _Time start, _Ctx c) {
  final parts = <String, String>{};
  for (final p in raw.split(';')) {
    final i = p.indexOf('=');
    if (i <= 0) {
      continue;
    }
    parts[p.substring(0, i).trim().toUpperCase()] = p.substring(i + 1).trim();
  }
  final freq = _freqs[parts['FREQ']];
  if (freq == null) {
    c.warn(
      'RRULE без допустимого FREQ пропущен: $raw',
      'RRULE without a valid FREQ skipped: $raw',
    );
    return null;
  }

  final byDay = <IcsByDay>[];
  for (final v in (parts['BYDAY'] ?? '').split(',')) {
    if (v.isEmpty) {
      continue;
    }
    final m = _byDayRe.firstMatch(v.trim().toUpperCase());
    if (m == null) {
      c.warn('BYDAY "$v" не разобран', 'Could not read BYDAY "$v"');
      continue;
    }
    final ord = m[1] == null ? null : int.parse(m[1]!);
    byDay.add(IcsByDay(_dayCodes.indexOf(m[2]!) + 1, ord));
  }

  DateTime? until;
  final u = parts['UNTIL'];
  if (u != null) {
    final t = _parseTime(u, zone: start.zone, utc: start.utc);
    if (t == null) {
      c.warn('UNTIL "$u" не разобран', 'Could not read UNTIL "$u"');
    } else if (t.dateOnly) {
      // Дата без времени — конец этого дня там, где смотрят календарь: в UTC
      // западнее Гринвича серия теряла бы последний вечер.
      final w = t.wall;
      until = DateTime(w.year, w.month, w.day, 23, 59, 59);
    } else {
      until = t.toLocal(c.local);
    }
  }

  var count = int.tryParse(parts['COUNT'] ?? '');
  if (count != null && count < 1) {
    // COUNT=0 стандарт не допускает; без этого серия стала бы бесконечной.
    c.warn(
      'COUNT "${parts['COUNT']}" неверный: только первое событие',
      'Invalid COUNT "${parts['COUNT']}": only the first event is kept',
    );
    count = 1;
  }

  return IcsRule(
    freq: freq,
    // INTERVAL=0 и ниже стандарт не допускает: считаем за 1.
    interval: max(1, int.tryParse(parts['INTERVAL'] ?? '') ?? 1),
    byDay: byDay,
    byMonthDay: _ints(parts['BYMONTHDAY']),
    byMonth: _ints(parts['BYMONTH']),
    bySetPos: _ints(parts['BYSETPOS']),
    until: until,
    count: count,
    raw: raw,
  );
}

/// Детерминированный хэш FNV-1a 64 для UID без поля UID.
String _fnvHex(String s) {
  var h = -0x340D631B7BDDDCDB; // смещение FNV-1a 64 (знаковое представление)
  for (final b in utf8.encode(s)) {
    h = (h ^ b) * 0x100000001b3;
  }
  final hi = (h >> 32) & 0xFFFFFFFF;
  final lo = h & 0xFFFFFFFF;
  return '${hi.toRadixString(16).padLeft(8, '0')}'
      '${lo.toRadixString(16).padLeft(8, '0')}';
}

IcsEvent? _buildEvent(List<_Prop> props, _Ctx c) {
  final uidRaw = _text(props, 'UID')?.trim();
  // Изменённый или отменённый день серии (так выгружает Google): тот же UID,
  // что у серии. В серии этот день — исключение, изменённый — отдельное
  // разовое событие со своим id, иначе он затёр бы серию.
  final ridProp = _first(props, 'RECURRENCE-ID');
  final rid = ridProp == null || uidRaw == null || uidRaw.isEmpty
      ? null
      : _timeFromValue(ridProp.value, ridProp.params['TZID'], c);
  if (rid != null) {
    (c.overridden[uidRaw!] ??= []).add(rid.toLocal(c.local));
  }
  final status = _text(props, 'STATUS');
  if (status?.trim().toUpperCase() == 'CANCELLED') {
    return null;
  }
  final summary = _text(props, 'SUMMARY') ?? '';

  final startProp = _first(props, 'DTSTART');
  if (startProp == null) {
    c.warn(
      'VEVENT "$summary" без DTSTART пропущен',
      'Event "$summary" skipped: no DTSTART',
    );
    return null;
  }
  final start = _timeFromValue(
    startProp.value,
    startProp.params['TZID'],
    c,
  );
  if (start == null) {
    c.warn(
      'Событие "$summary" пропущено: неверная дата "${startProp.value}"',
      'Event "$summary" skipped: invalid date "${startProp.value}"',
    );
    return null;
  }

  _Time? end;
  final endProp = _first(props, 'DTEND');
  if (endProp != null) {
    end = _timeFromValue(endProp.value, endProp.params['TZID'], c);
    if (end == null) {
      c.warn(
        'Событие "$summary" пропущено: неверная дата DTEND "${endProp.value}"',
        'Event "$summary" skipped: invalid DTEND "${endProp.value}"',
      );
      return null;
    }
  } else {
    final durProp = _first(props, 'DURATION');
    if (durProp != null) {
      final dur = _parseDuration(durProp.value);
      if (dur == null) {
        c.warn(
          'Событие "$summary": DURATION "${durProp.value}" не разобран',
          'Event "$summary": could not read DURATION "${durProp.value}"',
        );
      } else {
        end = start.plus(dur);
      }
    }
  }
  if (end == null && start.dateOnly) {
    end = start.plus(const Duration(days: 1));
  }

  final ruleProp = rid != null ? null : _first(props, 'RRULE');
  final rule = ruleProp == null ? null : _parseRule(ruleProp.value, start, c);

  final exDates = <DateTime>[];
  for (final p in props) {
    if (p.name != 'EXDATE') {
      continue;
    }
    for (final v in p.value.split(',')) {
      final t = _timeFromValue(v.trim(), p.params['TZID'], c);
      if (t == null) {
        c.warn('EXDATE "$v" не разобран', 'Could not read EXDATE "$v"');
        continue;
      }
      exDates.add(t.toLocal(c.local));
    }
  }

  final startLocal = start.toLocal(c.local);
  final uid = uidRaw == null || uidRaw.isEmpty
      // Из строки файла, а не из местного времени: при смене пояса id тот же.
      ? _fnvHex('$summary|${startProp.params['TZID'] ?? ''}|'
          '${startProp.value.trim()}')
      : rid != null
          ? '$uidRaw#${ridProp!.value.trim()}'
          : uidRaw;

  return IcsEvent(
    uid: uid,
    summary: summary,
    description: _text(props, 'DESCRIPTION'),
    location: _text(props, 'LOCATION'),
    start: startLocal,
    end: end?.toLocal(c.local),
    allDay: start.dateOnly,
    rule: rule,
    exDates: exDates,
  );
}
