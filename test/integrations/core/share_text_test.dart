import 'package:enitor/features/integrations/core/integration_command.dart';
import 'package:enitor/features/integrations/inbox/command_inbox.dart';
import 'package:flutter_test/flutter_test.dart';

// Текст из «Поделиться» → команда add_task. Первая строка — название,
// остальное — описание. Время фиксированное.

final _noon = DateTime(2026, 10, 25, 12);

final class _Share {
  const _Share(this.name, this.text, this.expect);

  final String name;
  final String? text;

  /// Для успеха: title, description, warnings. Для ошибки: error, field, problem.
  final Map<String, Object?> expect;
}

void _check(_Share c) {
  final r = parseSharedText(c.text, now: _noon);
  if (c.expect.containsKey('error')) {
    expect(r.command, isNull);
    final e = r.error;
    expect(e, isNotNull, reason: 'ожидалась ошибка');
    expect(e!.code.wire, c.expect['error']);
    expect(e.field, c.expect['field']);
    expect(e.problem?.name, c.expect['problem']);
    return;
  }
  expect(r.error, isNull, reason: 'неожиданная ошибка: ${r.error}');
  final cmd = r.command;
  expect(cmd, isA<AddTask>());
  final task = cmd! as AddTask;
  expect(task.source, CommandSource.share);
  expect(formatYmd(task.date), '2026-10-25');
  final expected = {'warnings': const <String>[], ...c.expect};
  expect(task.title, expected['title'], reason: 'title');
  expect(task.description, expected['description'], reason: 'description');
  expect(task.warnings, expected['warnings'], reason: 'warnings');
}

final _cases = <_Share>[
  const _Share('одна строка', 'Купить молоко', {
    'title': 'Купить молоко',
    'description': null,
  }),
  const _Share('несколько строк: первая — title, остальное — description',
      'Статья\nhttps://example.com/a\nИнтересно', {
    'title': 'Статья',
    'description': 'https://example.com/a\nИнтересно',
  }),
  const _Share(
      'только ссылка — она и становится title', 'https://example.com/a', {
    'title': 'https://example.com/a',
    'description': null,
  }),
  const _Share(
      'CRLF разбирается как перевод строки', 'Первая\r\nВторая\r\nТретья', {
    'title': 'Первая',
    'description': 'Вторая\nТретья',
  }),
  const _Share('пробелы вокруг строк обрезаются', 'Заголовок   \n\n  текст  ', {
    'title': 'Заголовок',
    'description': 'текст',
  }),
  _Share('title ровно 500 символов — остаётся целиком', '${'a' * 500}\nxyz', {
    'title': 'a' * 500,
    'description': 'xyz',
  }),
  _Share(
      'title 500 эмодзи — не режется (символы, не UTF-16)', '\u{1F600}' * 500, {
    'title': '\u{1F600}' * 500,
    'description': null,
  }),
  _Share('первая строка 10 000 символов: title 500, хвост в начале description',
      '${'б' * 10000}\nдетали', {
    'title': 'б' * 500,
    // Хвост 9500 символов + «детали» обрезаются до 5000 с предупреждением.
    'description': 'б' * 5000,
    'warnings': ['description'],
  }),
  _Share('description длиннее 5000 — обрезан и предупреждение',
      'Заголовок\n${'я' * 5001}', {
    'title': 'Заголовок',
    'description': 'я' * 5000,
    'warnings': ['description'],
  }),
  _Share('description ровно 5000 — без предупреждения',
      'Заголовок\n${'я' * 5000}', {
    'title': 'Заголовок',
    'description': 'я' * 5000,
  }),
  const _Share('HTML сохраняется как есть', '<script>alert(1)</script>', {
    'title': '<script>alert(1)</script>',
    'description': null,
  }),
  const _Share('SQL сохраняется как есть', "'; DROP TABLE tasks; --", {
    'title': "'; DROP TABLE tasks; --",
    'description': null,
  }),
  const _Share('null — missing по полю text', null, {
    'error': 'invalid_args',
    'field': 'text',
    'problem': 'missing',
  }),
  const _Share('пустая строка — missing', '', {
    'error': 'invalid_args',
    'field': 'text',
    'problem': 'missing',
  }),
  const _Share('одни пробелы и переводы строк — missing', '   \n  \r\n ', {
    'error': 'invalid_args',
    'field': 'text',
    'problem': 'missing',
  }),
];

void main() {
  for (final c in _cases) {
    test('поделиться: ${c.name}', () => _check(c));
  }
}
