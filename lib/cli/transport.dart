import 'dart:async';
import 'dart:io';

import 'pipe_frame.dart';

/// Канал до приложения. В тестах подменяется фейком.
abstract interface class CliTransport {
  /// Отправляет конверт и возвращает ответ приложения как есть (JSON-текст).
  Future<String> send(String envelopeJson);
}

/// Enitor не запущен: канала с нашим именем нет.
class EnitorNotRunning implements Exception {
  const EnitorNotRunning();

  @override
  String toString() => 'EnitorNotRunning';
}

/// Проблема с обменом по каналу (битый кадр, таймаут, нет SID).
class TransportException implements Exception {
  const TransportException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Канал Windows: `\\.\pipe\Enitor-<SID текущего пользователя>`.
class WindowsPipeTransport implements CliTransport {
  WindowsPipeTransport({
    this.timeout = const Duration(seconds: 5),
    this.pipeName,
  });

  final Duration timeout;

  /// Своё имя канала — только для тестов, чтобы не задеть настоящий Enitor.
  final String? pipeName;

  @override
  Future<String> send(String envelopeJson) async {
    // Префикс `\\?\`, а не `\\.\`: Dart переписывает `\\.\pipe\…` в
    // сетевой UNC-путь, и канал либо не находится, либо (с
    // PIPE_REJECT_REMOTE_CLIENTS у сервера) отвергает нас как удалённых.
    final path =
        r'\\?\pipe\' + (pipeName ?? 'Enitor-${await currentUserSid()}');
    final file = await _open(path);
    try {
      return await _exchange(file, envelopeJson).timeout(
        timeout,
        onTimeout: () => throw const TransportException('Enitor did not answer in time'),
      );
    } on FileSystemException catch (e) {
      // Канал оборвался посреди обмена — сообщение, а не трассировка стека.
      throw TransportException(
        'Lost connection to Enitor (${e.osError?.message.trim() ?? e.message}). Try again.',
      );
    } finally {
      // close() встаёт в очередь за висящим чтением, поэтому не ждём его:
      // при таймауте процесс всё равно завершится через exit().
      unawaited(file.close().catchError((_) => file));
    }
  }

  /// `File.open(FileMode.write)` на Windows даёт GENERIC_READ|GENERIC_WRITE,
  /// то есть канал открывается на чтение и запись. Занятый канал
  /// (ERROR_PIPE_BUSY = 231) ждём, отсутствующий (ERROR_FILE_NOT_FOUND = 2)
  /// означает, что Enitor не запущен.
  Future<RandomAccessFile> _open(String path) async {
    for (var attempt = 0;; attempt++) {
      try {
        return await File(path).open(mode: FileMode.write);
      } on FileSystemException catch (e) {
        final code = e.osError?.errorCode;
        if (code == 231 && attempt < 10) {
          await Future<void>.delayed(const Duration(milliseconds: 200));
          continue;
        }
        if (code == 2 || code == 53) {
          throw const EnitorNotRunning();
        }
        rethrow;
      }
    }
  }

  Future<String> _exchange(RandomAccessFile file, String envelopeJson) async {
    await file.writeFrom(encodeFrame(envelopeJson));
    final header = await _readExact(file, 4);
    final len = header[0] | (header[1] << 8) | (header[2] << 16) | (header[3] << 24);
    if (len == 0 || len > kMaxReplyBytes) {
      throw TransportException('Bad reply frame length: $len');
    }
    final body = await _readExact(file, len);
    final decoded = decodeFrame([...header, ...body], maxBytes: kMaxReplyBytes);
    if (decoded.error != null) {
      throw TransportException('Bad reply frame: ${decoded.error}');
    }
    return decoded.json!;
  }

  /// Канал может отдавать данные кусками, читаем, пока не наберём n байт.
  Future<List<int>> _readExact(RandomAccessFile file, int n) async {
    final out = <int>[];
    while (out.length < n) {
      final chunk = await file.read(n - out.length);
      if (chunk.isEmpty) {
        throw const TransportException('Enitor closed the pipe early');
      }
      out.addAll(chunk);
    }
    return out;
  }
}

/// SID текущего пользователя из `whoami /user /fo csv /nh`.
Future<String> currentUserSid() async {
  final result = await Process.run('whoami', ['/user', '/fo', 'csv', '/nh']);
  final match = RegExp(r'S-\d+(-\d+)+').firstMatch('${result.stdout}');
  if (result.exitCode != 0 || match == null) {
    throw const TransportException('Cannot read the current user SID');
  }
  return match.group(0)!;
}
