import 'dart:convert';

import 'package:enitor/features/integrations/core/integration_command.dart';
import 'package:flutter_test/flutter_test.dart';

// Таблица разбора: ссылки enitor://, JSON-команды. Каждый случай — вход и
// ожидание. В ожидании для успеха перечисляются только проверяемые поля
// команды (`warnings` по умолчанию должны быть пустыми). Для ошибки — `error`
// (код), `field` и `problem` (имя enum). Время фиксированное, без DateTime.now().

final _noon = DateTime(2026, 10, 25, 12);
final _night = DateTime(2026, 10, 25, 1, 30);

enum _Via { link, json }

final class _Case {
  _Case.link(this.name, this.input, this.expect, {DateTime? now})
      : via = _Via.link,
        now = now ?? _noon;

  _Case.json(this.name, this.input, this.expect, {DateTime? now})
      : via = _Via.json,
        now = now ?? _noon;

  final String name;
  final _Via via;
  final String input;
  final Map<String, Object?> expect;
  final DateTime now;
}

Map<String, Object?> _err(String code, [String? field, String? problem]) => {
      'error': code,
      'field': field,
      'problem': problem,
    };

String? _ymd(DateTime? d) => d == null ? null : formatYmd(d);

String? _hm(int? m) => m == null ? null : formatHm(m);

/// Все проверяемые поля команды в виде строк и простых значений.
Map<String, Object?> _describe(IntegrationCommand c) => {
      'name': c.name,
      'source': c.source,
      'warnings': c.warnings,
      'idempotencyKey': c.idempotencyKey,
      if (c is AddTask) ...{
        'title': c.title,
        'description': c.description,
        'date': _ymd(c.date),
        'start': _hm(c.startMinutes),
        'end': _hm(c.endMinutes),
        'priority': c.priority.name,
        'tags': c.tags,
      },
      if (c is AddScheduleItem) ...{
        'title': c.title,
        'date': _ymd(c.date),
        'start': _hm(c.startMinutes),
        'end': _hm(c.endMinutes),
        'location': c.location,
        'note': c.note,
      },
      if (c is CompleteTask) 'id': c.id,
      if (c is ListToday) 'date': _ymd(c.date),
      if (c is OpenScreen) 'target': c.target.name,
    };

ParseResult _run(_Case c) => switch (c.via) {
      _Via.link => parseLink(c.input, now: c.now),
      _Via.json => parseJsonCommand(
          c.input,
          source: CommandSource.tasker,
          now: c.now,
        ),
    };

void _check(_Case c) {
  final r = _run(c);
  if (c.expect.containsKey('error')) {
    expect(r.command, isNull, reason: 'команда не должна была разобраться');
    final e = r.error;
    expect(e, isNotNull, reason: 'ожидалась ошибка');
    expect(e!.code.wire, c.expect['error']);
    expect(e.field, c.expect['field']);
    expect(e.problem?.name, c.expect['problem']);
    return;
  }
  expect(r.error, isNull, reason: 'неожиданная ошибка: ${r.error}');
  final cmd = r.command;
  expect(cmd, isNotNull, reason: 'команда не разобрана');
  final actual = _describe(cmd!);
  final expected = {'warnings': const <String>[], ...c.expect};
  for (final e in expected.entries) {
    expect(actual[e.key], e.value, reason: 'поле ${e.key}');
  }
}

// Сборка ссылки с правильным кодированием (пробелы, эмодзи, длинные строки).
String _link(String host, Map<String, String> q) =>
    Uri(scheme: 'enitor', host: host, queryParameters: q).toString();

final cases = <_Case>[
  // ---- корректные ссылки ----
  _Case.link(
    'add: только title',
    'enitor://add?title=Buy%20milk',
    {
      'name': 'add_task',
      'title': 'Buy milk',
      'date': '2026-10-25',
      'priority': 'none',
      'tags': const <String>[],
    },
  ),
  _Case.link(
    'add: все поля',
    'enitor://add?v=1&title=Call%20mom&desc=Ask%20about%20trip'
        '&date=2026-11-02&start=18:00&end=18:30&priority=high&tags=family',
    {
      'name': 'add_task',
      'title': 'Call mom',
      'description': 'Ask about trip',
      'date': '2026-11-02',
      'start': '18:00',
      'end': '18:30',
      'priority': 'high',
      'tags': ['family'],
    },
  ),
  _Case.link(
    'schedule: все поля',
    'enitor://schedule?title=Physics&date=2026-11-03&start=09:00'
        '&end=10:30&location=Room%20214&note=Bring%20calc',
    {
      'name': 'add_schedule_item',
      'title': 'Physics',
      'date': '2026-11-03',
      'start': '09:00',
      'end': '10:30',
      'location': 'Room 214',
      'note': 'Bring calc',
    },
  ),
  _Case.link(
    'schedule: только обязательные поля',
    'enitor://schedule?title=Lunch&start=13:00',
    {
      'name': 'add_schedule_item',
      'title': 'Lunch',
      'date': '2026-10-25',
      'start': '13:00',
      'end': null,
      'location': null,
      'note': null,
    },
  ),
  _Case.link(
    'open: today',
    'enitor://open?screen=today',
    {'name': 'open', 'target': 'today'},
  ),
  _Case.link(
    'open: schedule',
    'enitor://open?screen=schedule',
    {'name': 'open', 'target': 'schedule'},
  ),
  _Case.link(
    'open: goals',
    'enitor://open?screen=goals',
    {'name': 'open', 'target': 'goals'},
  ),
  _Case.link(
    'open: settings',
    'enitor://open?screen=settings',
    {'name': 'open', 'target': 'settings'},
  ),
  _Case.link(
    'open: integrations',
    'enitor://open?screen=integrations',
    {'name': 'open', 'target': 'integrations'},
  ),
  _Case.link(
    'ссылка: схема в верхнем регистре и путь вместо host',
    'ENITOR://add?title=X',
    {'name': 'add_task', 'title': 'X'},
  ),
  _Case.link(
    'ссылка: действие в path (enitor:add)',
    'enitor:add?title=X',
    {'name': 'add_task', 'title': 'X'},
  ),

  // ---- корректные JSON ----
  _Case.json(
    'json add_task с idempotencyKey',
    '{"v":1,"command":"add_task","idempotencyKey":"tasker-1",'
        '"args":{"title":"Buy milk","date":"2026-11-02"}}',
    {
      'name': 'add_task',
      'idempotencyKey': 'tasker-1',
      'title': 'Buy milk',
      'date': '2026-11-02',
    },
  ),
  _Case.json(
    'json add_schedule_item с idempotencyKey',
    '{"command":"add_schedule_item","idempotencyKey":"k-2",'
        '"args":{"title":"Physics","date":"2026-11-03","start":"09:00"}}',
    {
      'name': 'add_schedule_item',
      'idempotencyKey': 'k-2',
      'title': 'Physics',
      'date': '2026-11-03',
      'start': '09:00',
    },
  ),
  _Case.json(
    'json complete_task с idempotencyKey',
    '{"command":"complete_task","idempotencyKey":"k-3",'
        '"args":{"id":"a1b2c3d4"}}',
    {'name': 'complete_task', 'idempotencyKey': 'k-3', 'id': 'a1b2c3d4'},
  ),
  _Case.json(
    'json list_today с idempotencyKey и датой',
    '{"command":"list_today","idempotencyKey":"k-4",'
        '"args":{"date":"2026-11-02"}}',
    {'name': 'list_today', 'idempotencyKey': 'k-4', 'date': '2026-11-02'},
  ),
  _Case.json(
    'json list_today без даты — null (сегодня по правилу приложения)',
    '{"command":"list_today"}',
    {'name': 'list_today', 'date': null},
  ),

  // ---- версия ----
  _Case.link(
    'v отсутствует — версия 1 по умолчанию',
    'enitor://add?title=X',
    {'name': 'add_task', 'title': 'X'},
  ),
  _Case.link(
    'v=2 — unsupported_version',
    'enitor://add?v=2&title=X',
    _err('unsupported_version'),
  ),
  _Case.link(
    'v=abc — bad_format по полю v',
    'enitor://add?v=abc&title=X',
    _err('invalid_args', 'v', 'badFormat'),
  ),
  _Case.link(
    'v=0 — out_of_range по полю v',
    'enitor://add?v=0&title=X',
    _err('invalid_args', 'v', 'outOfRange'),
  ),
  _Case.link(
    'v пустой — bad_format по полю v',
    'enitor://add?v=&title=X',
    _err('invalid_args', 'v', 'badFormat'),
  ),
  _Case.json(
    'json v=2 — unsupported_version',
    '{"v":2,"command":"list_today"}',
    _err('unsupported_version'),
  ),
  _Case.json(
    'json v строкой — bad_format по полю v',
    '{"v":"1","command":"list_today"}',
    _err('invalid_args', 'v', 'badFormat'),
  ),

  // ---- дата ----
  _Case.link(
    'дата отсутствует в 01:30 — это ещё вчера',
    'enitor://add?title=X',
    {'name': 'add_task', 'date': '2026-10-24'},
    now: _night,
  ),
  _Case.link(
    'дата отсутствует в 04:00 — уже сегодня',
    'enitor://add?title=X',
    {'name': 'add_task', 'date': '2026-10-25'},
    now: DateTime(2026, 10, 25, 4),
  ),
  _Case.link(
    'високосная 2028-02-29 принимается',
    'enitor://add?title=X&date=2028-02-29',
    {'name': 'add_task', 'date': '2028-02-29'},
  ),
  _Case.link(
    'несуществующая 2026-02-29 — bad_format',
    'enitor://add?title=X&date=2026-02-29',
    _err('invalid_args', 'date', 'badFormat'),
  ),
  _Case.link(
    '31.02 — bad_format, а не перенос на март',
    'enitor://add?title=X&date=2026-02-31',
    _err('invalid_args', 'date', 'badFormat'),
  ),
  _Case.link(
    'формат 2026-1-5 без ведущих нулей — bad_format',
    'enitor://add?title=X&date=2026-1-5',
    _err('invalid_args', 'date', 'badFormat'),
  ),
  _Case.link(
    'ровно +5 лет — принимается',
    'enitor://add?title=X&date=2031-10-25',
    {'name': 'add_task', 'date': '2031-10-25'},
  ),
  _Case.link(
    '+5 лет и 1 день — out_of_range',
    'enitor://add?title=X&date=2031-10-26',
    _err('invalid_args', 'date', 'outOfRange'),
  ),
  _Case.link(
    'ровно −5 лет — принимается (граница включена)',
    'enitor://add?title=X&date=2021-10-25',
    {'name': 'add_task', 'date': '2021-10-25'},
  ),
  _Case.link(
    '−5 лет и 1 день — out_of_range',
    'enitor://add?title=X&date=2021-10-24',
    _err('invalid_args', 'date', 'outOfRange'),
  ),

  // ---- время ----
  _Case.link(
    'время 00:00 и 00:01',
    'enitor://add?title=X&start=00:00&end=00:01',
    {'name': 'add_task', 'start': '00:00', 'end': '00:01'},
  ),
  _Case.link(
    'время 23:58 и 23:59',
    'enitor://add?title=X&start=23:58&end=23:59',
    {'name': 'add_task', 'start': '23:58', 'end': '23:59'},
  ),
  _Case.link(
    'start 24:00 — out_of_range',
    'enitor://add?title=X&start=24:00',
    _err('invalid_args', 'start', 'outOfRange'),
  ),
  _Case.link(
    'end 12:60 — out_of_range',
    'enitor://add?title=X&start=12:00&end=12:60',
    _err('invalid_args', 'end', 'outOfRange'),
  ),
  _Case.link(
    'start 9:05 без ведущего нуля — принимается (formats.md: H:MM или HH:MM)',
    'enitor://add?title=X&start=9:05',
    {'name': 'add_task', 'start': '09:05'},
  ),
  _Case.link(
    'start 0900 без двоеточия — bad_format',
    'enitor://add?title=X&start=0900',
    _err('invalid_args', 'start', 'badFormat'),
  ),
  _Case.link(
    'конец раньше начала — end_before_start',
    'enitor://add?title=X&start=10:00&end=09:00',
    _err('invalid_args', 'end', 'endBeforeStart'),
  ),
  _Case.link(
    'конец равен началу — end_before_start',
    'enitor://schedule?title=X&start=10:00&end=10:00',
    _err('invalid_args', 'end', 'endBeforeStart'),
  ),
  _Case.link(
    'schedule без start — missing по полю start',
    'enitor://schedule?title=X',
    _err('invalid_args', 'start', 'missing'),
  ),
  _Case.link(
    'schedule: конец раньше начала — end_before_start',
    'enitor://schedule?title=X&start=10:00&end=09:30',
    _err('invalid_args', 'end', 'endBeforeStart'),
  ),

  // ---- title ----
  _Case.link(
    'ссылка: title пустой — пустая анкета',
    'enitor://add?title=',
    {'name': 'add_task', 'title': ''},
  ),
  _Case.link(
    'ссылка: title из пробелов — пустая анкета',
    'enitor://add?title=%20%20%20',
    {'name': 'add_task', 'title': ''},
  ),
  _Case.link(
    'ссылка: без title (плитка) — пустая анкета',
    'enitor://add',
    {'name': 'add_task', 'title': ''},
  ),
  _Case.link(
    'title обрезается по краям',
    'enitor://add?title=%20%20Buy%20%20',
    {'name': 'add_task', 'title': 'Buy'},
  ),
  _Case.link(
    'title ровно 500 символов — принимается',
    _link('add', {'title': 'a' * 500}),
    {'name': 'add_task', 'title': 'a' * 500},
  ),
  _Case.link(
    'title 501 символ — too_long',
    _link('add', {'title': 'a' * 501}),
    _err('invalid_args', 'title', 'tooLong'),
  ),
  _Case.link(
    'title 500 эмодзи — принимается (символы, не UTF-16)',
    _link('add', {'title': '\u{1F600}' * 500}),
    {'name': 'add_task', 'title': '\u{1F600}' * 500},
  ),
  _Case.link(
    'title 501 эмодзи — too_long',
    _link('add', {'title': '\u{1F600}' * 501}),
    _err('invalid_args', 'title', 'tooLong'),
  ),
  _Case.link(
    'title кириллицей',
    'enitor://add?title=%D0%9A%D1%83%D0%BF%D0%B8%D1%82%D1%8C%20%D0%BC%D0%BE%D0%BB%D0%BE%D0%BA%D0%BE',
    {'name': 'add_task', 'title': 'Купить молоко'},
  ),
  _Case.link(
    'title с NUL (%00) — bad_format',
    'enitor://add?title=a%00b',
    _err('invalid_args', 'title', 'badFormat'),
  ),
  _Case.json(
    'json title с \\u0000 — bad_format',
    r'{"command":"add_task","args":{"title":"a\u0000b"}}',
    _err('invalid_args', 'title', 'badFormat'),
  ),
  _Case.json(
    'json add_task без title — missing',
    '{"command":"add_task","args":{"date":"2026-11-02"}}',
    _err('invalid_args', 'title', 'missing'),
  ),

  // ---- кодирование ----
  _Case.link(
    'плюс как пробел',
    'enitor://add?title=Buy+milk',
    {'name': 'add_task', 'title': 'Buy milk'},
  ),
  _Case.link(
    'закодированный плюс остаётся плюсом',
    'enitor://add?title=C%2B%2B',
    {'name': 'add_task', 'title': 'C++'},
  ),
  _Case.link(
    'закодированный процент',
    'enitor://add?title=100%25',
    {'name': 'add_task', 'title': '100%'},
  ),
  _Case.link(
    'двойное кодирование декодируется один раз: %2520 → %20',
    'enitor://add?title=%2520',
    {'name': 'add_task', 'title': '%20'},
  ),
  _Case.link(
    'битая UTF-8 последовательность — bad_format',
    'enitor://add?title=Hi%E0%A4%A',
    _err('invalid_args', 'link', 'badFormat'),
  ),
  _Case.link(
    'закодированный & не делит параметры',
    'enitor://add?title=A%26B&date=2026-11-02',
    {'name': 'add_task', 'title': 'A&B', 'date': '2026-11-02'},
  ),

  // ---- теги ----
  _Case.link(
    'теги через запятую',
    'enitor://add?title=X&tags=a,b',
    {
      'name': 'add_task',
      'tags': ['a', 'b'],
    },
  ),
  _Case.link(
    'решётки срезаются, пробелы и ## тоже',
    'enitor://add?title=X&tags=%23a,%20%23%23b',
    {
      'name': 'add_task',
      'tags': ['a', 'b'],
    },
  ),
  _Case.link(
    'пустые элементы пропускаются',
    'enitor://add?title=X&tags=a,,b,%20,',
    {
      'name': 'add_task',
      'tags': ['a', 'b'],
    },
  ),
  _Case.link(
    'дубли убираются',
    'enitor://add?title=X&tags=a,b,a,%23a',
    {
      'name': 'add_task',
      'tags': ['a', 'b'],
    },
  ),
  _Case.link(
    '10 тегов — принимается',
    'enitor://add?title=X&tags=t1,t2,t3,t4,t5,t6,t7,t8,t9,t10',
    {'name': 'add_task', 'tags': hasLength(10)},
  ),
  _Case.link(
    '11 тегов — too_long по полю tags',
    'enitor://add?title=X&tags=t1,t2,t3,t4,t5,t6,t7,t8,t9,t10,t11',
    _err('invalid_args', 'tags', 'tooLong'),
  ),
  _Case.link(
    'тег 40 символов — принимается',
    _link('add', {'title': 'X', 'tags': 'a' * 40}),
    {
      'name': 'add_task',
      'tags': ['a' * 40],
    },
  ),
  _Case.link(
    'тег 41 символ — too_long',
    _link('add', {'title': 'X', 'tags': 'a' * 41}),
    _err('invalid_args', 'tags', 'tooLong'),
  ),
  _Case.json(
    'json tags массивом',
    '{"command":"add_task","args":{"title":"X","tags":["x","y"]}}',
    {
      'name': 'add_task',
      'tags': ['x', 'y'],
    },
  ),
  _Case.json(
    'json tags числом — bad_format',
    '{"command":"add_task","args":{"title":"X","tags":5}}',
    _err('invalid_args', 'tags', 'badFormat'),
  ),

  // ---- priority ----
  _Case.link(
    'priority low',
    'enitor://add?title=X&priority=low',
    {'name': 'add_task', 'priority': 'low'},
  ),
  _Case.link(
    'priority urgent — bad_format',
    'enitor://add?title=X&priority=urgent',
    _err('invalid_args', 'priority', 'badFormat'),
  ),
  _Case.link(
    'priority HIGH — принимается (formats.md: без учёта регистра)',
    'enitor://add?title=X&priority=HIGH',
    {'name': 'add_task', 'priority': 'high'},
  ),

  // ---- незнакомые параметры ----
  _Case.link(
    'незнакомый параметр — команда разобрана, в warnings',
    'enitor://add?title=X&foo=1',
    {
      'name': 'add_task',
      'title': 'X',
      'warnings': ['foo'],
    },
  ),
  _Case.link(
    'schedule: незнакомый параметр в warnings',
    'enitor://schedule?title=X&start=09:00&color=red',
    {
      'name': 'add_schedule_item',
      'warnings': ['color'],
    },
  ),
  _Case.json(
    'json: незнакомое поле верхнего уровня в warnings',
    '{"command":"list_today","extra":true}',
    {
      'name': 'list_today',
      'warnings': ['extra'],
    },
  ),
  _Case.json(
    'json: незнакомое поле в args в warnings',
    '{"command":"add_task","args":{"title":"X","color":"red"}}',
    {
      'name': 'add_task',
      'title': 'X',
      'warnings': ['color'],
    },
  ),

  // ---- complete_task ----
  _Case.json(
    'complete_task: id из 3 символов — out_of_range',
    '{"command":"complete_task","args":{"id":"abc"}}',
    _err('invalid_args', 'id', 'outOfRange'),
  ),
  _Case.json(
    'complete_task: id из 4 символов — принимается',
    '{"command":"complete_task","args":{"id":"abcd"}}',
    {'name': 'complete_task', 'id': 'abcd'},
  ),
  _Case.json(
    'complete_task: без id — missing',
    '{"command":"complete_task","args":{}}',
    _err('invalid_args', 'id', 'missing'),
  ),

  // ---- open ----
  _Case.link(
    'open: неизвестный экран — bad_format',
    'enitor://open?screen=home',
    _err('invalid_args', 'screen', 'badFormat'),
  ),
  _Case.link(
    'open: без экрана — missing',
    'enitor://open',
    _err('invalid_args', 'screen', 'missing'),
  ),

  // ---- лимиты описания, места, заметки ----
  _Case.link(
    'desc 5001 символ — too_long (в поле description)',
    _link('add', {'title': 'X', 'desc': 'a' * 5001}),
    _err('invalid_args', 'description', 'tooLong'),
  ),
  _Case.link(
    'location 501 — too_long',
    _link('schedule', {
      'title': 'X',
      'start': '09:00',
      'location': 'a' * 501,
    }),
    _err('invalid_args', 'location', 'tooLong'),
  ),
  _Case.link(
    'note 5001 — too_long',
    _link('schedule', {'title': 'X', 'start': '09:00', 'note': 'a' * 5001}),
    _err('invalid_args', 'note', 'tooLong'),
  ),
  _Case.json(
    'json add_task без title и args — missing title',
    '{"command":"add_task"}',
    _err('invalid_args', 'title', 'missing'),
  ),

  // ---- текст, похожий на HTML/SQL: сохраняется как есть ----
  _Case.link(
    'ссылка: HTML в title сохраняется без изменений',
    _link('add', {'title': '<script>alert(1)</script>'}),
    {'name': 'add_task', 'title': '<script>alert(1)</script>'},
  ),
  _Case.link(
    'ссылка: SQL в title сохраняется без изменений',
    _link('add', {'title': "'; DROP TABLE tasks; --"}),
    {'name': 'add_task', 'title': "'; DROP TABLE tasks; --"},
  ),
  _Case.json(
    'json: HTML в title сохраняется без изменений',
    jsonEncode({
      'command': 'add_task',
      'args': {'title': '<script>alert(1)</script>'},
    }),
    {'name': 'add_task', 'title': '<script>alert(1)</script>'},
  ),

  // ---- мусор на входе ----
  _Case.link(
    'не enitor-схема (https) — bad_format',
    'https://enitor.app/add?title=x',
    _err('invalid_args', 'link', 'badFormat'),
  ),
  _Case.link(
    'неизвестное действие — unknown_command',
    'enitor://unknown',
    _err('unknown_command'),
  ),
  _Case.link(
    'пустая строка — bad_format',
    '',
    _err('invalid_args', 'link', 'badFormat'),
  ),
  _Case.json(
    'JSON-массив вместо объекта — bad_format',
    '[{"command":"add_task"}]',
    _err('invalid_args', 'request', 'badFormat'),
  ),
  _Case.json(
    'битый JSON — bad_format',
    '{"command":',
    _err('invalid_args', 'request', 'badFormat'),
  ),
  _Case.json(
    'args не объект — bad_format по полю args',
    '{"command":"add_task","args":"title"}',
    _err('invalid_args', 'args', 'badFormat'),
  ),
  _Case.json(
    'command не строка — missing по полю command',
    '{"command":5}',
    _err('invalid_args', 'command', 'missing'),
  ),
  _Case.json(
    'неизвестная команда — unknown_command',
    '{"command":"delete_all"}',
    _err('unknown_command'),
  ),
  _Case.json(
    'idempotencyKey 101 символ — too_long',
    jsonEncode({
      'command': 'add_task',
      'idempotencyKey': 'k' * 101,
      'args': {'title': 'X'},
    }),
    _err('invalid_args', 'idempotencyKey', 'tooLong'),
  ),
  _Case.json(
    'idempotencyKey 100 символов — принимается',
    jsonEncode({
      'command': 'add_task',
      'idempotencyKey': 'k' * 100,
      'args': {'title': 'X'},
    }),
    {'name': 'add_task', 'idempotencyKey': 'k' * 100},
  ),
];

void main() {
  test('в таблице разбора не меньше 40 случаев', () {
    expect(cases.length, greaterThanOrEqualTo(40));
  });

  for (final c in cases) {
    test(c.name, () => _check(c));
  }
}
