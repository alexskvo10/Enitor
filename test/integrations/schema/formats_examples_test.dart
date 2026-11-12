import 'dart:convert';
import 'dart:io';

import 'package:enitor/cli/cli.dart';
import 'package:enitor/cli/transport.dart';
import 'package:enitor/features/integrations/core/integration_command.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:json_schema/json_schema.dart';

// Примеры из docs/integrations/formats.md — это контракт. Каждый блок
// разбирается тем же кодом, что в приложении, и проверяется схемой.
// Упавший блок называет номер строки документа и текст.

const _doc = 'docs/integrations/formats.md';
const _dir = 'docs/integrations/schema';
final _now = DateTime(2026, 10, 25, 12);

const _languages = ['link', 'json', 'reply', 'pipe', 'event', 'export', 'text'];

class _Block {
  _Block(this.lang, this.openLine, this.lines);

  final String lang;

  /// Номер строки открывающей ``` (1-based).
  final int openLine;
  final List<String> lines;

  /// Номер строки документа для строки блока [index] (0-based).
  int lineOf(int index) => openLine + 1 + index;
}

List<_Block> _blocks(String text) {
  final out = <_Block>[];
  final src = text.split(RegExp(r'\r?\n'));
  String? lang;
  var openLine = 0;
  var buf = <String>[];
  for (var i = 0; i < src.length; i++) {
    final line = src[i].trimRight();
    if (lang == null) {
      if (line.startsWith('```') && line.length > 3) {
        lang = line.substring(3).trim();
        openLine = i + 1;
        buf = <String>[];
      }
    } else if (line.startsWith('```')) {
      out.add(_Block(lang, openLine, buf));
      lang = null;
    } else {
      buf.add(line);
    }
  }
  return out;
}

Map<String, dynamic> _read(String name) =>
    jsonDecode(File('$_dir/$name').readAsStringSync()) as Map<String, dynamic>;

JsonSchema _schema(String name) => JsonSchema.create(_read(name));

List<String> _errors(JsonSchema schema, Object? instance) => [
      for (final e in schema.validate(instance).errors) e.toString(),
    ];

/// Разбор JSON; при ошибке записывает проблему с местом в документе.
Object? _decode(String text, String where, List<String> problems) {
  try {
    return jsonDecode(text);
  } on FormatException catch (e) {
    problems.add('$where: не JSON: ${e.message}');
    return null;
  }
}

/// Фейковый канал: отвечает успешно, как приложение на `add`, `done`, `today`.
class _FakeTransport implements CliTransport {
  static final _reply = jsonEncode({
    'v': 1,
    'ok': true,
    'result': {
      'date': '2026-11-02',
      'task': {
        'id': 'abcdef1234567890',
        'title': 'Buy milk',
        'date': '2026-11-02',
        'priority': 'none',
        'tags': <String>[],
        'done': true,
      },
      'tasks': <Object>[],
      'schedule': <Object>[],
    },
    'warnings': <String>[],
  });

  @override
  Future<String> send(String envelopeJson) async => _reply;
}

void main() {
  final blocks = _blocks(File(_doc).readAsStringSync());
  List<_Block> of(String lang) => blocks.where((b) => b.lang == lang).toList();

  test('в документе есть блоки каждого языка', () {
    for (final lang in _languages) {
      expect(
        of(lang),
        isNotEmpty,
        reason: 'в $_doc нет ни одного блока ```$lang — пометка потерялась?',
      );
    }
  });

  test('```link: каждая строка разбирается parseLink без ошибки', () {
    final problems = <String>[];
    for (final b in of('link')) {
      for (var i = 0; i < b.lines.length; i++) {
        final line = b.lines[i].trim();
        if (line.isEmpty) continue;
        final r = parseLink(line, now: _now);
        if (r.error != null) {
          problems.add('$_doc:${b.lineOf(i)}: $line — ${r.error}');
        }
      }
    }
    expect(problems, isEmpty, reason: problems.join('\n'));
  });

  test('```json: блок разбирается parseJsonCommand и проходит command.schema.json', () {
    final command = _schema('command.schema.json');
    final problems = <String>[];
    for (final b in of('json')) {
      final where = '$_doc:${b.openLine + 1}';
      final text = b.lines.join('\n');
      final r = parseJsonCommand(text, source: CommandSource.cli, now: _now);
      if (r.error != null) {
        problems.add('$where: ${r.error}');
        continue;
      }
      final decoded = _decode(text, where, problems);
      problems.addAll([for (final p in _errors(command, decoded)) '$where: $p']);
    }
    expect(problems, isEmpty, reason: problems.join('\n'));
  });

  test('```reply: каждая строка проходит reply.schema.json; result.task и result.item — тоже',
      () {
    final reply = _schema('reply.schema.json');
    final task = _schema('task.schema.json');
    final item = _schema('schedule-item.schema.json');
    final problems = <String>[];
    for (final b in of('reply')) {
      for (var i = 0; i < b.lines.length; i++) {
        final line = b.lines[i].trim();
        if (line.isEmpty) continue;
        final where = '$_doc:${b.lineOf(i)}';
        final decoded = _decode(line, where, problems);
        problems.addAll([for (final p in _errors(reply, decoded)) '$where: $p']);
        final Object? result =
            decoded is Map<String, dynamic> ? decoded['result'] : null;
        if (result is Map<String, dynamic>) {
          final Object? t = result['task'];
          if (t != null) {
            problems.addAll([for (final p in _errors(task, t)) '$where: task: $p']);
          }
          final Object? s = result['item'];
          if (s != null) {
            problems.addAll([for (final p in _errors(item, s)) '$where: item: $p']);
          }
        }
      }
    }
    expect(problems, isEmpty, reason: problems.join('\n'));
  });

  test('```pipe: каждая строка проходит pipe-envelope.schema.json; request — command.schema.json',
      () {
    final pipe = _schema('pipe-envelope.schema.json');
    final command = _schema('command.schema.json');
    final problems = <String>[];
    for (final b in of('pipe')) {
      for (var i = 0; i < b.lines.length; i++) {
        final line = b.lines[i].trim();
        if (line.isEmpty) continue;
        final where = '$_doc:${b.lineOf(i)}';
        final decoded = _decode(line, where, problems);
        problems.addAll([for (final p in _errors(pipe, decoded)) '$where: $p']);
        final Object? request =
            decoded is Map<String, dynamic> ? decoded['request'] : null;
        if (request != null) {
          problems.addAll([for (final p in _errors(command, request)) '$where: request: $p']);
        }
      }
    }
    expect(problems, isEmpty, reason: problems.join('\n'));
  });

  test('```event: блок проходит event.schema.json', () {
    final event = _schema('event.schema.json');
    final problems = <String>[];
    for (final b in of('event')) {
      final where = '$_doc:${b.openLine + 1}';
      final decoded = _decode(b.lines.join('\n'), where, problems);
      problems.addAll([for (final p in _errors(event, decoded)) '$where: $p']);
    }
    expect(problems, isEmpty, reason: problems.join('\n'));
  });

  test('```export: блок проходит export.schema.json', () {
    final exportSchema = _schema('export.schema.json');
    final problems = <String>[];
    for (final b in of('export')) {
      final where = '$_doc:${b.openLine + 1}';
      final decoded = _decode(b.lines.join('\n'), where, problems);
      problems.addAll([for (final p in _errors(exportSchema, decoded)) '$where: $p']);
    }
    expect(problems, isEmpty, reason: problems.join('\n'));
  });

  test('```text: каждая строка enitor-cli разбирается runCli с кодом 0', () async {
    final problems = <String>[];
    for (final b in of('text')) {
      for (var i = 0; i < b.lines.length; i++) {
        final line = b.lines[i].trim();
        if (!line.startsWith('enitor-cli ')) continue;
        final args = line.split(RegExp(r'\s+')).skip(1).toList();
        final out = StringBuffer();
        final err = StringBuffer();
        final code = await runCli(
          args,
          transport: _FakeTransport(),
          out: out,
          err: err,
          retryDelay: Duration.zero,
        );
        if (code != 0) {
          problems.add('$_doc:${b.lineOf(i)}: $line — код $code: $err');
        }
      }
    }
    expect(problems, isEmpty, reason: problems.join('\n'));
  });
}
