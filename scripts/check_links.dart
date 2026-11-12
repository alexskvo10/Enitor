// Проверяет относительные ссылки в README.md и в docs/**/*.md, docs/**/*.html.
//
// Ищет ссылки вида `](путь)` в Markdown и `href="путь"` / `src="путь"` в HTML.
// Внешние адреса (http, https, mailto, enitor и любые другие схемы) и ссылки
// только на якорь (#...) не проверяются, сети здесь нет. Якорь и query после
// путя отбрасываются, проверяется только наличие файла или папки.
//
// Запуск из корня репозитория:
//   dart run scripts/check_links.dart
// Код выхода: 0 — битых ссылок нет, 1 — есть битые, 2 — запущено не из корня.
import 'dart:io';

final _markdownLink = RegExp(r'\]\(([^)\s]+)');
final _htmlAttribute =
    RegExp(r'''\b(?:href|src)\s*=\s*["']([^"']+)["']''', caseSensitive: false);
final _externalScheme = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*:|^//');

void main() {
  final root = Directory.current.absolute;
  final readme = File.fromUri(root.uri.resolve('README.md'));
  if (!readme.existsSync()) {
    stderr.writeln('Запускайте из корня репозитория (там, где README.md).');
    exit(2);
  }

  final targets = <File>[readme];
  final docs = Directory.fromUri(root.uri.resolve('docs/'));
  if (docs.existsSync()) {
    for (final entity in docs.listSync(recursive: true)) {
      if (entity is File &&
          (entity.path.endsWith('.md') || entity.path.endsWith('.html'))) {
        targets.add(entity);
      }
    }
  }

  var checked = 0;
  var external = 0;
  var anchors = 0;
  var absolute = 0;
  final broken = <String>[];

  for (final file in targets) {
    final rel = file.absolute.path
        .substring(root.path.length + 1)
        .replaceAll('\\', '/');
    final lines = file.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      for (final pattern in [_markdownLink, _htmlAttribute]) {
        for (final match in pattern.allMatches(lines[i])) {
          final raw = match.group(1)!.trim();
          if (raw.startsWith('#')) {
            anchors++;
            continue;
          }
          if (_externalScheme.hasMatch(raw)) {
            external++;
            continue;
          }
          if (raw.startsWith('/')) {
            absolute++;
            continue;
          }

          final pathPart = raw.split('#').first.split('?').first;
          var decoded = pathPart;
          try {
            decoded = Uri.decodeFull(pathPart);
          } catch (_) {
            // Оставляем как есть: битое процентное кодирование — тоже ошибка.
          }
          final target = file.absolute.uri.resolveUri(Uri(path: decoded));
          checked++;
          final type = FileSystemEntity.typeSync(target.toFilePath());
          if (type == FileSystemEntityType.notFound) {
            broken.add('$rel:${i + 1} -> $raw');
          }
        }
      }
    }
  }

  stdout.writeln(
    'Файлов: ${targets.length}, относительных ссылок проверено: $checked.',
  );
  stdout.writeln(
    'Пропущено: внешних $external, на якорь $anchors, абсолютных путей $absolute.',
  );
  if (broken.isEmpty) {
    stdout.writeln('Битых ссылок нет.');
    exit(0);
  }
  stdout.writeln('Битые ссылки (${broken.length}):');
  for (final line in broken) {
    stdout.writeln('  $line');
  }
  exit(1);
}
