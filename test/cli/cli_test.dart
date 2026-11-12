import 'dart:convert';

import 'package:enitor/cli/cli.dart';
import 'package:enitor/cli/transport.dart';
import 'package:flutter_test/flutter_test.dart';

/// Фейковый канал: отдаёт заданные ответы по очереди (строка) или бросает
/// исключение. Когда ответы кончились — отвечает успешно.
class FakeTransport implements CliTransport {
  FakeTransport([List<Object>? replies]) : _replies = replies ?? <Object>[];

  final List<Object> _replies;
  final List<String> sent = [];

  @override
  Future<String> send(String envelopeJson) async {
    sent.add(envelopeJson);
    if (_replies.isEmpty) {
      return okReply;
    }
    final next = _replies.removeAt(0);
    if (next is Exception) {
      throw next;
    }
    return next as String;
  }
}

String okWith(Map<String, Object?> result) =>
    jsonEncode({'v': 1, 'ok': true, 'result': result, 'warnings': <String>[]});

String errorReply(String code, String message) => jsonEncode({
  'v': 1,
  'ok': false,
  'error': {'code': code, 'message': message},
  'warnings': <String>[],
});

final okReply = okWith({
  'date': '2026-11-02',
  'task': {
    'id': 'abcdef1234567890',
    'title': 'Buy milk',
    'date': '2026-11-02',
    'priority': 'none',
    'tags': <String>[],
    'done': false,
  },
  'item': {
    'id': 'item-1234-5678',
    'title': 'Physics',
    'date': '2026-11-02',
    'start': '09:00',
  },
  'tasks': <Object>[],
  'schedule': <Object>[],
});

class CliRun {
  const CliRun(this.code, this.out, this.err, this.sent);

  final int code;
  final String out;
  final String err;
  final List<String> sent;
}

Future<CliRun> run(
  List<String> args, {
  List<Object>? replies,
  int notReadyRetries = 15,
}) async {
  final transport = FakeTransport(replies);
  final out = StringBuffer();
  final err = StringBuffer();
  final code = await runCli(
    args,
    transport: transport,
    out: out,
    err: err,
    retryDelay: Duration.zero,
    notReadyRetries: notReadyRetries,
  );
  return CliRun(code, out.toString(), err.toString(), transport.sent);
}

Map<String, Object?> envelope(Map<String, Object?> request) => {
  'v': 1,
  'kind': 'command',
  'source': 'cli',
  'request': request,
};

Map<String, Object?> request(
  String command,
  Map<String, Object?> args, {
  String? key,
}) => {
  'v': 1,
  'command': command,
  if (key != null) 'idempotencyKey': key,
  'args': args,
};

class _Case {
  const _Case(this.args, {this.request, this.errorText});

  /// Ожидаемый запрос внутри конверта (код выхода 0 при ответе ok).
  final List<String> args;
  final Map<String, Object?>? request;

  /// Если задано — ожидаем код 2 и этот текст в err.
  final String? errorText;
}

final _argCases = <_Case>[
  // add
  _Case(
    ['add', 'Buy', 'milk'],
    request: request('add_task', {'title': 'Buy milk'}),
  ),
  _Case(
    ['add', 'Buy milk', '--date', '2026-11-02'],
    request: request('add_task', {'title': 'Buy milk', 'date': '2026-11-02'}),
  ),
  _Case(
    ['add', 'X', '--at', '09:00'],
    request: request('add_task', {'title': 'X', 'start': '09:00'}),
  ),
  _Case(
    ['add', 'X', '--until', '10:30'],
    request: request('add_task', {'title': 'X', 'end': '10:30'}),
  ),
  _Case(
    ['add', 'X', '--desc', 'some text'],
    request: request('add_task', {'title': 'X', 'description': 'some text'}),
  ),
  _Case(
    ['add', 'X', '--priority', 'high'],
    request: request('add_task', {'title': 'X', 'priority': 'high'}),
  ),
  _Case(
    ['add', 'X', '--tag', 'a', '--tag', 'b'],
    request: request('add_task', {'title': 'X', 'tags': ['a', 'b']}),
  ),
  _Case(
    ['add', 'X', '--key', 'k1'],
    request: request('add_task', {'title': 'X'}, key: 'k1'),
  ),
  _Case(
    ['add', 'X', '--date=2026-01-02'],
    request: request('add_task', {'title': 'X', 'date': '2026-01-02'}),
  ),
  _Case(
    ['add', 'X', '--date', '2026-11-02', '--date', '2026-11-03'],
    request: request('add_task', {'title': 'X', 'date': '2026-11-03'}),
  ),
  _Case(
    ['add', 'Mix', '--tag', 'x', 'words'],
    request: request('add_task', {'title': 'Mix words', 'tags': ['x']}),
  ),
  _Case(
    ['add', 'Cyr', 'Привет', 'мир'],
    request: request('add_task', {'title': 'Cyr Привет мир'}),
  ),
  _Case(
    [
      'add',
      'Buy',
      'milk',
      '--at',
      '09:00',
      '--until',
      '10:00',
      '--date',
      '2026-11-02',
      '--desc',
      'd',
      '--priority',
      'low',
      '--tag',
      't',
      '--key',
      'k',
    ],
    request: request(
      'add_task',
      {
        'title': 'Buy milk',
        'description': 'd',
        'date': '2026-11-02',
        'start': '09:00',
        'end': '10:00',
        'priority': 'low',
        'tags': ['t'],
      },
      key: 'k',
    ),
  ),
  const _Case(['add'], errorText: 'needs a task title'),
  const _Case(['add', '--date', '2026-11-02'], errorText: 'needs a task title'),
  const _Case(['add', 'X', '--date'], errorText: 'needs a value'),
  const _Case(['add', 'X', '--tag', 'a', '--tag'], errorText: 'needs a value'),
  const _Case(['add', 'X', '--bogus'], errorText: 'unknown option "--bogus"'),
  const _Case(['add', '-x'], errorText: 'unknown option "-x"'),
  // schedule
  _Case(
    ['schedule', 'Physics', '--at', '09:00'],
    request: request('add_schedule_item', {'title': 'Physics', 'start': '09:00'}),
  ),
  _Case(
    ['schedule', 'Pair', '--at', '10:30', '--until', '12:00', '--place', '214'],
    request: request('add_schedule_item', {
      'title': 'Pair',
      'start': '10:30',
      'end': '12:00',
      'location': '214',
    }),
  ),
  _Case(
    [
      'schedule',
      'Pair',
      '--at',
      '10:30',
      '--note',
      'bring pen',
      '--date',
      '2026-11-03',
      '--key',
      'k2',
    ],
    request: request(
      'add_schedule_item',
      {
        'title': 'Pair',
        'start': '10:30',
        'note': 'bring pen',
        'date': '2026-11-03',
      },
      key: 'k2',
    ),
  ),
  _Case(
    ['schedule', 'P', '--at', '9:05'],
    request: request('add_schedule_item', {'title': 'P', 'start': '9:05'}),
  ),
  const _Case(['schedule', 'Physics'], errorText: 'needs --at'),
  const _Case(['schedule', '--at', '09:00'], errorText: 'needs a title'),
  const _Case(['schedule', 'P', '--at'], errorText: 'needs a value'),
  const _Case(
    ['schedule', 'P', '--at', '09:00', '--priority', 'high'],
    errorText: 'unknown option "--priority"',
  ),
  // today
  _Case(['today'], request: request('list_today', {})),
  _Case(
    ['today', '--date', '2026-11-02'],
    request: request('list_today', {'date': '2026-11-02'}),
  ),
  const _Case(['today', 'extra'], errorText: 'today takes no title'),
  const _Case(['today', '--date'], errorText: 'needs a value'),
  const _Case(['today', '--tag', 'x'], errorText: 'unknown option "--tag"'),
  // done
  _Case(
    ['done', 'abcd1234'],
    request: request('complete_task', {'id': 'abcd1234'}),
  ),
  const _Case(['done'], errorText: 'needs a task id'),
  const _Case(['done', 'a', 'b'], errorText: 'got 2'),
  const _Case(['done', '--key', 'k'], errorText: 'unknown option "--key"'),
  // команда
  const _Case(['frobnicate'], errorText: 'unknown command "frobnicate"'),
];

void main() {
  group('таблица аргументов', () {
    for (final c in _argCases) {
      test('${c.args}', () async {
        final result = await run(c.args);
        if (c.errorText != null) {
          expect(result.code, 2);
          expect(result.err, contains(c.errorText));
          expect(result.sent, isEmpty);
        } else {
          expect(result.code, 0, reason: result.err);
          expect(jsonDecode(result.sent.single), envelope(c.request!));
        }
      });
    }
  });

  group('коды выхода', () {
    test('ok → 0', () async {
      final result = await run(['add', 'X']);
      expect(result.code, 0);
      expect(result.out, contains('Added "Buy milk"'));
    });

    test('forbidden → 4, сообщение в err', () async {
      final result = await run(
        ['add', 'X'],
        replies: [errorReply('forbidden', 'Turned off in Integrations.')],
      );
      expect(result.code, 4);
      expect(result.err, contains('Turned off in Integrations.'));
    });

    test('invalid_args → 5', () async {
      final result = await run(
        ['schedule', 'X', '--at', '25:00'],
        replies: [errorReply('invalid_args', 'Bad time.')],
      );
      expect(result.code, 5);
      expect(result.err, contains('Bad time.'));
    });

    test('not_found → 5', () async {
      final result = await run(
        ['done', 'abcd'],
        replies: [errorReply('not_found', 'No such task.')],
      );
      expect(result.code, 5);
    });

    test('Enitor не запущен → 3', () async {
      final result = await run(['today'], replies: [const EnitorNotRunning()]);
      expect(result.code, 3);
      expect(result.err, contains('not running'));
    });

    test('ошибка канала → 5', () async {
      final result = await run(
        ['today'],
        replies: [const TransportException('Enitor did not answer in time')],
      );
      expect(result.code, 5);
      expect(result.err, contains('did not answer'));
    });

    test('битый ответ → 5', () async {
      final result = await run(['today'], replies: ['not json']);
      expect(result.code, 5);
    });

    test('not_ready трижды подряд, потом ok → 0, повторы были', () async {
      final notReady = errorReply('not_ready', 'Enitor is still starting.');
      final result = await run(
        ['today'],
        replies: [notReady, notReady, notReady],
      );
      expect(result.code, 0);
      expect(result.sent.length, 4);
    });

    test('not_ready дольше лимита → 3', () async {
      final notReady = errorReply('not_ready', 'Enitor is still starting.');
      final result = await run(
        ['today'],
        replies: List<Object>.generate(40, (_) => notReady),
      );
      expect(result.code, 3);
      expect(result.sent.length, 16);
    });

    test('--version и --help', () async {
      final version = await run(['--version']);
      expect(version.code, 0);
      expect(version.out.trim(), 'enitor-cli 1');

      final help = await run(['--help']);
      expect(help.code, 0);
      expect(help.out, contains('Exit codes'));
      expect(help.sent, isEmpty);

      final none = await run([]);
      expect(none.out, contains('Usage:'));
    });
  });

  group('--json', () {
    test('печатает ответ как есть, одной строкой', () async {
      final result = await run(['add', 'Buy', 'milk', '--json']);
      expect(result.code, 0);
      expect(result.out, '$okReply\n');
    });

    test('при ошибке тоже печатает ответ приложения', () async {
      final forbidden = errorReply('forbidden', 'No.');
      final result = await run(['--json', 'add', 'X'], replies: [forbidden]);
      expect(result.code, 4);
      expect(result.out, '$forbidden\n');
    });
  });

  group('today', () {
    test('дата, задачи и расписание', () async {
      final result = await run(
        ['today'],
        replies: [
          okWith({
            'date': '2026-11-02',
            'tasks': [
              {
                'id': 'abcdef1234567890',
                'title': 'Buy milk',
                'start': '09:00',
                'done': true,
              },
              {'id': 'ff00ee11aabb', 'title': 'Call', 'done': false},
            ],
            'schedule': [
              {
                'id': 'item-1',
                'title': 'Pair',
                'start': '10:30',
                'end': '12:00',
                'location': '214',
              },
              {'id': 'item-2', 'title': 'Standup', 'start': '08:00'},
            ],
          }),
        ],
      );
      expect(result.code, 0);
      expect(
        result.out,
        '2026-11-02\n'
        '[x] 09:00 Buy milk  (id: abcdef12)\n'
        '[ ] Call  (id: ff00ee11)\n'
        '• 10:30–12:00 Pair @ 214\n'
        '• 08:00 Standup\n',
      );
    });

    test('пусто — Nothing for this day', () async {
      final result = await run(
        ['today'],
        replies: [
          okWith({'date': '2026-11-02', 'tasks': [], 'schedule': []}),
        ],
      );
      expect(result.out, '2026-11-02\nNothing for this day\n');
    });
  });
}
