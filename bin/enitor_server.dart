import 'dart:async';
import 'dart:io';

import 'package:enitor/core/utils/secrets.dart';
import 'package:enitor/server/server_app.dart';
import 'package:enitor/server/sync_store.dart';
import 'package:enitor/server/web_page.dart';

const _usage = '''
enitor-server [options]

  --port <n>      порт (8787)
  --host <addr>   адрес (127.0.0.1); 0.0.0.0 — принимать из домашней сети
  --data <dir>    папка с данными (enitor-data)
  --token <t>     свой токен вместо созданного сервером
  --show-token    напечатать токен и выйти
  -h, --help      эта справка

«Сегодня» и время записей сервер считает по своему часовому поясу —
задайте ваш: TZ=Europe/Moscow enitor-server''';

/// Эталонный сервер Enitor: синхронизация устройств и REST для автоматики.
/// Описание — docs/integrations/server.md.
Future<void> main(List<String> args) async {
  final opt = <String, String>{};
  final flags = <String>{};
  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    if (a == '-h' || a == '--help' || a == '--show-token') {
      flags.add(a);
    } else if (const ['--port', '--host', '--data', '--token'].contains(a) &&
        i + 1 < args.length) {
      opt[a] = args[++i];
    } else {
      stderr.writeln('Unknown option: $a\n\n$_usage');
      exit(2);
    }
  }
  if (flags.contains('-h') || flags.contains('--help')) {
    stdout.writeln(_usage);
    return;
  }
  final port = int.tryParse(opt['--port'] ?? '8787');
  if (port == null || port <= 0 || port > 65535) {
    stderr.writeln('--port: 1..65535');
    exit(2);
  }
  final host = opt['--host'] ?? '127.0.0.1';

  final dir = Directory(opt['--data'] ?? 'enitor-data');
  await dir.create(recursive: true);
  String path(String name) => '${dir.path}${Platform.pathSeparator}$name';
  final tokenFile = File(path('token'));
  var token = opt['--token'];
  var created = false;
  if (token != null) {
    await tokenFile.writeAsString(token);
  } else if (await tokenFile.exists()) {
    token = (await tokenFile.readAsString()).trim();
  } else {
    token = generateSecretToken();
    await tokenFile.writeAsString(token);
    created = true;
  }
  if (flags.contains('--show-token')) {
    stdout.writeln(token);
    return;
  }

  final store = await SyncStore.open(File(path('enitor-data.json')));
  final app = EnitorServer(store, token: token, webPage: kWebPage);
  final server = await HttpServer.bind(host, port);
  stdout.writeln('enitor-server: http://$host:$port  (data: ${dir.path})');
  // Пояс сервера — «сегодня» для задач без даты и время записей. На VPS
  // обычно UTC, и задачи «на сегодня» ночью уезжали бы на другой день.
  final now = DateTime.now();
  final off = now.timeZoneOffset;
  final sign = off.isNegative ? '-' : '+';
  final hh = off.inHours.abs().toString().padLeft(2, '0');
  final mm = (off.inMinutes.abs() % 60).toString().padLeft(2, '0');
  stdout.writeln(
    'Time zone: ${now.timeZoneName} ($sign$hh:$mm) — set TZ=<your zone> '
    'if it differs from your devices',
  );
  if (created) {
    stdout.writeln('Token (Enitor → Settings → Sync → Own server):\n$token');
  }
  ProcessSignal.sigint.watch().listen((_) async {
    await server.close(force: true);
    await app.close();
    exit(0);
  });
  // Не ждём ответа: поток событий держит соединение открытым.
  await for (final req in server) {
    unawaited(app.handle(req));
  }
}
