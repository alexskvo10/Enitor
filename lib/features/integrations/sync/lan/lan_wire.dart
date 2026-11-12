import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'lan_crypto.dart';

// Чистый Dart: обмен сообщениями по TLS. Одно соединение — один запрос и
// один ответ: длина (4 байта) + JSON.

/// Больше этого сообщение не принимаем: первый обмен заполненного устройства
/// — все записи сразу, но и за годы это мегабайты, а не сотни.
const kLanMaxFrame = 64 * 1024 * 1024;

class LanWireException implements Exception {
  const LanWireException(this.code, [this.message = '']);

  /// `connect` (не достучались), `timeout`, `pin` (сертификат соседа не тот,
  /// что запомнили), `protocol` (ответ не по формату).
  final String code;
  final String message;

  @override
  String toString() =>
      'LanWireException($code${message.isEmpty ? '' : ': $message'})';
}

Uint8List encodeLanFrame(Map<String, dynamic> msg) {
  final body = utf8.encode(jsonEncode(msg));
  final out = Uint8List(4 + body.length);
  ByteData.sublistView(out).setUint32(0, body.length);
  out.setRange(4, out.length, body);
  return out;
}

/// Прочитать одно сообщение из потока байтов. Подписку не отменяет, а
/// ставит на паузу: у сокета отмена закрыла бы его раньше ответа.
Future<Map<String, dynamic>> readLanFrame(Stream<List<int>> input) {
  final done = Completer<Map<String, dynamic>>();
  final buf = BytesBuilder(copy: false);
  int? need;
  late final StreamSubscription<List<int>> sub;
  void fail(Object e) {
    if (!done.isCompleted) done.completeError(e);
  }

  sub = input.listen(
    (chunk) {
      if (done.isCompleted) return;
      buf.add(chunk);
      if (need == null && buf.length >= 4) {
        need = ByteData.sublistView(buf.toBytes(), 0, 4).getUint32(0);
        if (need! > kLanMaxFrame) {
          sub.pause();
          return fail(const LanWireException('protocol', 'frame too large'));
        }
      }
      if (need != null && buf.length >= 4 + need!) {
        sub.pause();
        try {
          final bytes = buf.toBytes();
          final decoded = jsonDecode(utf8.decode(bytes.sublist(4, 4 + need!)));
          if (decoded is! Map<String, dynamic>) {
            return fail(const LanWireException('protocol', 'not an object'));
          }
          done.complete(decoded);
        } on FormatException catch (e) {
          fail(LanWireException('protocol', '$e'));
        }
      }
    },
    onError: (Object e) => fail(LanWireException('connect', '$e')),
    onDone: () => fail(const LanWireException('protocol', 'connection closed')),
  );
  return done.future;
}

/// Чей сертификат на [host]:[port], если он из [wanted]; иначе null.
/// Ничего не отправляет: чужому устройству в сети не достаётся даже список
/// группы — рукопожатие с чужим сертификатом рвётся.
Future<String?> lanProbe(
  String host,
  int port,
  Set<String> wanted, {
  Duration timeout = const Duration(milliseconds: 800),
}) async {
  Socket? raw;
  try {
    raw = await Socket.connect(host, port, timeout: timeout);
    final s = await SecureSocket.secure(
      raw,
      context: SecurityContext(withTrustedRoots: false),
      onBadCertificate: (c) => wanted.contains(derFingerprint(c.der)),
    ).timeout(timeout * 2);
    final cert = s.peerCertificate;
    s.destroy();
    final fp = cert == null ? null : derFingerprint(cert.der);
    return wanted.contains(fp) ? fp : null;
  } catch (_) {
    raw?.destroy();
    return null;
  }
}

/// Запрос соседу. [pin] — отпечаток сертификата, который должен быть у
/// соседа; null — принять любой (только знакомство: там подлинность
/// проверяет код).
/// [build] получает отпечаток соседа: подпись знакомства включает его.
Future<Map<String, dynamic>> lanRequest(
  String host,
  int port,
  Map<String, dynamic> Function(String serverFingerprint) build, {
  String? pin,
  Duration connectTimeout = const Duration(seconds: 5),
  Duration timeout = const Duration(seconds: 30),
}) async {
  var pinFailed = false;
  final SecureSocket socket;
  try {
    socket = await SecureSocket.connect(
      host,
      port,
      context: SecurityContext(withTrustedRoots: false),
      timeout: connectTimeout,
      onBadCertificate: (cert) {
        if (pin != null && derFingerprint(cert.der) != pin) {
          pinFailed = true;
          return false;
        }
        return true;
      },
    );
  } on HandshakeException catch (e) {
    throw LanWireException(pinFailed ? 'pin' : 'connect', '$e');
  } on SocketException catch (e) {
    throw LanWireException('connect', '$e');
  } on TimeoutException {
    throw const LanWireException('connect', 'timeout');
  }
  try {
    // Сверяем ещё раз по итогу рукопожатия, а не только в onBadCertificate:
    // тот вызывается не для каждого сертификата цепочки и не всегда.
    final cert = socket.peerCertificate;
    final seen = cert == null ? '' : derFingerprint(cert.der);
    if (pin != null && seen != pin) throw const LanWireException('pin');
    socket.add(encodeLanFrame(build(seen)));
    await socket.flush();
    return await readLanFrame(socket).timeout(timeout);
  } on TimeoutException {
    throw const LanWireException('timeout');
  } on LanWireException {
    rethrow;
  } on FormatException catch (e) {
    throw LanWireException('protocol', '$e');
  } on SocketException catch (e) {
    throw LanWireException('connect', '$e');
  } finally {
    socket.destroy();
  }
}
