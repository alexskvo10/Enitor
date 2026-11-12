import 'dart:convert';

import 'transport.dart';

/// Ошибка аргументов командной строки: выход с кодом 2.
class _UsageError implements Exception {
  const _UsageError(this.message);

  final String message;
}

/// Флаги, которые понимает каждая команда. Остальное — ошибка на нашей стороне.
const _allowedFlags = <String, Set<String>>{
  'add': {'--date', '--at', '--until', '--desc', '--priority', '--tag', '--key'},
  'schedule': {'--at', '--until', '--date', '--place', '--note', '--key'},
  'today': {'--date'},
  'done': <String>{},
};

const _help = '''
enitor-cli: command line for Enitor on this Windows PC.
Talks to the running Enitor app through a local pipe (only your user can use it).

Usage:
  enitor-cli add <title words...> [--date YYYY-MM-DD] [--at HH:MM] [--until HH:MM]
                 [--desc TEXT] [--priority none|low|medium|high] [--tag TAG]... [--key KEY]
  enitor-cli schedule <title words...> --at HH:MM [--until HH:MM] [--date YYYY-MM-DD]
                 [--place TEXT] [--note TEXT] [--key KEY]
  enitor-cli today [--date YYYY-MM-DD]
  enitor-cli done <task id, or a unique prefix of at least 4 characters>

Global options:
  --json          print the app's reply as one line of JSON and nothing else
  --version       print the command format version
  -h, --help      show this help

Exit codes:
  0  success
  2  wrong arguments
  3  Enitor is not running (or still starting)
  4  forbidden: turned off in Enitor -> Integrations -> Permissions
  5  the app refused the command; its message is printed to stderr

Example:
  enitor-cli add Buy milk --date 2026-11-02 --at 18:00 --tag home
''';

/// Запуск команды. Всё через параметры, без exit() и глобального stdout,
/// чтобы тестировать. [retryDelay] и [notReadyRetries] — пауза и число
/// повторов при `not_ready` (по умолчанию 15 × 200 мс ≈ 3 с).
Future<int> runCli(
  List<String> args, {
  required CliTransport transport,
  required StringSink out,
  required StringSink err,
  Duration retryDelay = const Duration(milliseconds: 200),
  int notReadyRetries = 15,
}) async {
  if (args.contains('--version')) {
    out.writeln('enitor-cli 1');
    return 0;
  }
  final asJson = args.contains('--json');
  final rest = args.where((a) => a != '--json').toList();
  if (rest.isEmpty || rest.contains('--help') || rest.contains('-h')) {
    out.write(_help);
    return 0;
  }

  final _Request request;
  try {
    request = _buildRequest(rest.first, rest.sublist(1));
  } on _UsageError catch (e) {
    return _usage(err, e.message);
  }

  final envelope = jsonEncode({
    'v': 1,
    'kind': 'command',
    'source': 'cli',
    'request': {
      'v': 1,
      'command': request.command,
      if (request.key != null) 'idempotencyKey': request.key,
      'args': request.args,
    },
  });

  final _Reply reply;
  try {
    reply = await _sendWithRetry(
      transport,
      envelope,
      retryDelay: retryDelay,
      notReadyRetries: notReadyRetries,
    );
  } on EnitorNotRunning {
    err.writeln('Enitor is not running (or still starting). Start Enitor and try again.');
    return 3;
  } on TransportException catch (e) {
    err.writeln(e.message);
    return 5;
  }

  final data = reply.data;
  if (data['ok'] != true) {
    final error = (data['error'] as Map<String, Object?>?) ?? const {};
    if (asJson) {
      out.writeln(reply.raw);
    }
    err.writeln('${error['message'] ?? error['code'] ?? 'Enitor refused the command'}');
    return error['code'] == 'forbidden' ? 4 : 5;
  }

  if (asJson) {
    out.writeln(reply.raw);
    return 0;
  }
  try {
    _printHuman(request.command, data['result'] as Map<String, Object?>, out);
  } on TypeError {
    err.writeln('Unexpected reply from Enitor');
    return 5;
  }
  return 0;
}

class _Request {
  const _Request(this.command, this.args, this.key);

  final String command;
  final Map<String, Object?> args;
  final String? key;
}

class _Reply {
  const _Reply(this.raw, this.data);

  /// Ответ как пришёл из канала.
  final String raw;
  final Map<String, Object?> data;
}

int _usage(StringSink err, String message) {
  err.writeln('error: $message');
  err.writeln('Run "enitor-cli --help" for usage.');
  return 2;
}

/// Отправляет конверт; при `not_ready` ждёт и повторяет.
Future<_Reply> _sendWithRetry(
  CliTransport transport,
  String envelope, {
  required Duration retryDelay,
  required int notReadyRetries,
}) async {
  var retries = 0;
  while (true) {
    final raw = await transport.send(envelope);
    final data = _parseReply(raw);
    final error = data['error'];
    final code = error is Map ? error['code'] : null;
    if (code != 'not_ready') {
      return _Reply(raw, data);
    }
    if (retries >= notReadyRetries) {
      throw const EnitorNotRunning();
    }
    retries++;
    await Future<void>.delayed(retryDelay);
  }
}

Map<String, Object?> _parseReply(String raw) {
  try {
    final data = jsonDecode(raw);
    if (data is Map<String, Object?>) {
      return data;
    }
  } on FormatException {
    // ниже — общая ошибка
  }
  throw const TransportException('Bad reply from Enitor');
}

/// Разбор аргументов команды. Позиционные слова собираем в [words],
/// флаги — в [flags] (повторяемые копятся в список, остальные — последний).
class _Parsed {
  _Parsed(this.words, this.flags);

  final List<String> words;
  final Map<String, List<String>> flags;

  String? last(String name) {
    final values = flags[name];
    return values == null || values.isEmpty ? null : values.last;
  }

  List<String> all(String name) => flags[name] ?? const [];
}

_Parsed _parse(List<String> tokens, Set<String> allowed) {
  final words = <String>[];
  final flags = <String, List<String>>{};
  for (var i = 0; i < tokens.length; i++) {
    final token = tokens[i];
    if (!token.startsWith('-') || token == '-') {
      words.add(token);
      continue;
    }
    if (!token.startsWith('--')) {
      throw _UsageError('unknown option "$token"');
    }
    final eq = token.indexOf('=');
    final name = eq < 0 ? token : token.substring(0, eq);
    if (!allowed.contains(name)) {
      throw _UsageError('unknown option "$name"');
    }
    final String value;
    if (eq >= 0) {
      value = token.substring(eq + 1);
    } else {
      if (i + 1 >= tokens.length || tokens[i + 1].startsWith('--')) {
        throw _UsageError('option $name needs a value');
      }
      value = tokens[++i];
    }
    flags.putIfAbsent(name, () => []).add(value);
  }
  return _Parsed(words, flags);
}

void _put(Map<String, Object?> map, String key, String? value) {
  if (value != null) {
    map[key] = value;
  }
}

_Request _buildRequest(String command, List<String> tokens) {
  final allowed = _allowedFlags[command];
  if (allowed == null) {
    throw _UsageError('unknown command "$command"');
  }
  final parsed = _parse(tokens, allowed);
  final words = parsed.words;

  switch (command) {
    case 'add':
      final title = words.join(' ').trim();
      if (title.isEmpty) {
        throw const _UsageError('add needs a task title');
      }
      final args = <String, Object?>{'title': title};
      _put(args, 'description', parsed.last('--desc'));
      _put(args, 'date', parsed.last('--date'));
      _put(args, 'start', parsed.last('--at'));
      _put(args, 'end', parsed.last('--until'));
      _put(args, 'priority', parsed.last('--priority'));
      if (parsed.all('--tag').isNotEmpty) {
        args['tags'] = parsed.all('--tag');
      }
      return _Request('add_task', args, parsed.last('--key'));
    case 'schedule':
      final title = words.join(' ').trim();
      if (title.isEmpty) {
        throw const _UsageError('schedule needs a title');
      }
      final start = parsed.last('--at');
      if (start == null) {
        throw const _UsageError('schedule needs --at HH:MM');
      }
      final args = <String, Object?>{'title': title, 'start': start};
      _put(args, 'end', parsed.last('--until'));
      _put(args, 'date', parsed.last('--date'));
      _put(args, 'location', parsed.last('--place'));
      _put(args, 'note', parsed.last('--note'));
      return _Request('add_schedule_item', args, parsed.last('--key'));
    case 'today':
      if (words.isNotEmpty) {
        throw _UsageError('today takes no title, got "${words.first}"');
      }
      final args = <String, Object?>{};
      _put(args, 'date', parsed.last('--date'));
      return _Request('list_today', args, null);
    default:
      // done
      if (words.isEmpty) {
        throw const _UsageError('done needs a task id');
      }
      if (words.length > 1) {
        throw _UsageError('done takes one task id, got ${words.length}');
      }
      return _Request('complete_task', {'id': words.single}, null);
  }
}

void _printHuman(String command, Map<String, Object?> result, StringSink out) {
  switch (command) {
    case 'add_task':
      final task = result['task'] as Map<String, Object?>;
      out.writeln('Added "${task['title']}" (id: ${task['id']})');
      break;
    case 'add_schedule_item':
      final item = result['item'] as Map<String, Object?>;
      out.writeln('Scheduled "${item['title']}" (id: ${item['id']})');
      break;
    case 'complete_task':
      final task = result['task'] as Map<String, Object?>;
      out.writeln('Completed "${task['title']}" (id: ${task['id']})');
      break;
    default:
      _printToday(result, out);
  }
}

/// Дата, затем задачи `[x] 09:00 Название  (id: …)` и пункты расписания
/// `• 10:30–12:00 Пара @ 214`.
void _printToday(Map<String, Object?> result, StringSink out) {
  out.writeln('${result['date']}');
  final rows = <String>[];
  for (final raw in result['tasks'] as List<Object?>) {
    final task = raw as Map<String, Object?>;
    final mark = task['done'] == true ? 'x' : ' ';
    final time = task['start'] == null ? '' : '${task['start']} ';
    rows.add('[$mark] $time${task['title']}  (id: ${_short(task['id'])})');
  }
  for (final raw in result['schedule'] as List<Object?>) {
    final item = raw as Map<String, Object?>;
    final end = item['end'] == null ? '' : '–${item['end']}';
    final place = item['location'] == null ? '' : ' @ ${item['location']}';
    rows.add('• ${item['start']}$end ${item['title']}$place');
  }
  if (rows.isEmpty) {
    out.writeln('Nothing for this day');
  }
  for (final row in rows) {
    out.writeln(row);
  }
}

String _short(Object? id) {
  final text = '$id';
  return text.length > 8 ? text.substring(0, 8) : text;
}
