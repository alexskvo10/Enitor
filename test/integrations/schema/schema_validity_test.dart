import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:json_schema/json_schema.dart';

// Схемы формата интеграций (docs/integrations/schema/): каждая — валидный
// JSON-объект, собирается валидатором draft 2020-12, с title и description,
// без $id и сетевых адресов. Ссылки — только внутри файла (#/$defs/…), поэтому
// каждый файл самодостаточен.

const _dir = 'docs/integrations/schema';
const _draft = 'https://json-schema.org/draft/2020-12/schema';

const _files = [
  'command.schema.json',
  'reply.schema.json',
  'task.schema.json',
  'schedule-item.schema.json',
  'event.schema.json',
  'pipe-envelope.schema.json',
  'export.schema.json',
];

Map<String, dynamic> _read(String name) =>
    jsonDecode(File('$_dir/$name').readAsStringSync()) as Map<String, dynamic>;

/// Все узлы JSON-документа, рекурсивно.
void _walk(Object? node, void Function(String key, Object? value) visit) {
  if (node is Map) {
    node.forEach((key, value) {
      visit(key as String, value);
      _walk(value, visit);
    });
  } else if (node is List) {
    for (final e in node) {
      _walk(e, visit);
    }
  }
}

void main() {
  test('каталог содержит ровно описанные схемы', () {
    final found = Directory(_dir)
        .listSync()
        .whereType<File>()
        .map((f) => f.uri.pathSegments.last)
        .toSet();
    expect(found, unorderedEquals(_files));
  });

  for (final name in _files) {
    group(name, () {
      test('валидный JSON-объект', () {
        expect(
          () => _read(name),
          returnsNormally,
          reason: '$name не разбирается как JSON',
        );
      });

      test('draft 2020-12, есть title и description', () {
        final schema = _read(name);
        expect(schema[r'$schema'], _draft);
        expect(schema['title'], isA<String>());
        expect(schema['description'], isA<String>());
      });

      test('собирается валидатором без ошибок', () {
        expect(
          () => JsonSchema.create(_read(name)),
          returnsNormally,
          reason: '$name — невалидная схема',
        );
      });

      test(r'без $id и без сетевых адресов', () {
        final problems = <String>[];
        _walk(_read(name), (key, value) {
          if (key == r'$id') problems.add('\$id: $value');
          if (key == r'$ref' && value is String && !value.startsWith('#/')) {
            problems.add('\$ref вне файла: $value');
          }
        });
        expect(problems, isEmpty, reason: '$name: ${problems.join(', ')}');
      });

      test(r'каждый $ref указывает на существующий $defs', () {
        final root = _read(name);
        final defs = (root[r'$defs'] as Map?)?.keys.toSet() ?? <String>{};
        final missing = <String>[];
        _walk(root, (key, value) {
          if (key != r'$ref' || value is! String) return;
          const prefix = r'#/$defs/';
          final target = value.startsWith(prefix) ? value.substring(prefix.length) : null;
          if (target == null || !defs.contains(target)) missing.add(value);
        });
        expect(missing, isEmpty, reason: '$name: нет целей для ${missing.join(', ')}');
      });
    });
  }

  test('Task в event.schema.json совпадает с task.schema.json', () {
    // Копия нужна, потому что схемы самодостаточны; расхождение роняет тест.
    final task = _read('task.schema.json');
    final copy = (_read('event.schema.json')[r'$defs'] as Map<String, dynamic>)['Task']
        as Map<String, dynamic>;
    expect(copy['properties'], equals(task['properties']));
    expect(copy['required'], equals(task['required']));
    expect(copy['additionalProperties'], equals(task['additionalProperties']));
  });
}
