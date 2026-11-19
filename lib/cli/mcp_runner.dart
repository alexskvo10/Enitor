import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'mcp.dart';
import 'transport.dart';

/// Сколько ждать, пока запущенный нами Enitor поднимет канал.
const _launchWait = Duration(seconds: 10);

/// `enitor-cli mcp`: MCP по stdio. Если Enitor не запущен, запускает его
/// свёрнутым (рядом лежащий `enitor.exe --minimized`) и ждёт канал до 10 с.
Future<void> runMcp({CliTransport? transport}) async {
  final t = transport ?? WindowsPipeTransport();
  var launched = false;

  Future<String> send(String envelope) async {
    try {
      return await _sendReady(t, envelope);
    } on EnitorNotRunning {
      if (launched || !await _launchEnitor()) rethrow;
      launched = true;
      final deadline = DateTime.now().add(_launchWait);
      while (DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 300));
        try {
          return await _sendReady(t, envelope);
        } on EnitorNotRunning {
          continue;
        }
      }
      rethrow;
    }
  }

  // stdin/stdout — канал протокола: только UTF-8 и только JSON-RPC, без
  // посторонних строк (диагностика — в stderr).
  stdout.encoding = utf8;
  final server = McpServer(send: send);
  await server.serve(
    stdin.transform(utf8.decoder).transform(const LineSplitter()),
    stdout.writeln,
  );
  await stdout.flush();
}

/// `not_ready` (Enitor ещё стартует) — как «не запущен»: подождём.
Future<String> _sendReady(CliTransport t, String envelope) async {
  final raw = await t.send(envelope);
  // По коду ошибки, а не по подстроке: «not_ready» в названии задачи — это
  // данные, а не ответ «ещё стартую».
  Object? error;
  try {
    final decoded = jsonDecode(raw);
    error = decoded is Map ? decoded['error'] : null;
  } on FormatException {
    error = null;
  }
  if (error is Map && error['code'] == 'not_ready') {
    throw const EnitorNotRunning();
  }
  return raw;
}

Future<bool> _launchEnitor() async {
  final dir = File(Platform.resolvedExecutable).parent.path;
  final exe = File('$dir\\enitor.exe');
  if (!exe.existsSync()) {
    stderr.writeln('enitor.exe not found next to enitor-cli.exe');
    return false;
  }
  try {
    await Process.start(
      exe.path,
      ['--minimized'],
      mode: ProcessStartMode.detached,
    );
    return true;
  } on ProcessException catch (e) {
    stderr.writeln('Cannot start Enitor: ${e.message}');
    return false;
  }
}
