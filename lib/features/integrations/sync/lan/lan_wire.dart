import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'lan_crypto.dart';

// Чистый Dart: обмен сообщениями по TLS. Одно соединение — один запрос
// (подписанный заголовок `auth`, потом тело) и один ответ; каждое
// сообщение — длина (4 байта) + JSON.

/// Больше этого сообщение не принимаем: первый обмен заполненного устройства
/// — все записи сразу, но и за годы это мегабайты, а не сотни.
const kLanMaxFrame = 64 * 1024 * 1024;

/// Предел сообщения, пока не известно, кто его шлёт: подписанный заголовок
/// запроса, знакомство по коду, запрос старой версии без заголовка. Тело
/// побольше сервер читает только после проверки подписи заголовка — иначе
/// любой в той же сети мог бы занять память телефона чужим «запросом».
const kLanMaxUnsigned = 64 * 1024;

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

/// Читает сообщения из потока байтов по одному — по запросу [next], с
/// пределом на каждое. Между сообщениями подписка на паузе (у сокета отмена
/// закрыла бы его раньше ответа), лишние байты ждут следующего [next].
class LanFrameReader {
  LanFrameReader(Stream<List<int>> input) {
    _sub = input.listen(
      (chunk) {
        _buf.add(chunk);
        _pump();
      },
      onError: (Object e) => _fail(LanWireException('connect', '$e')),
      onDone: () {
        _closed = true;
        _pump();
      },
    );
    _pause();
  }

  late final StreamSubscription<List<int>> _sub;

  // Пауза подписки считается вложенно: две паузы требуют двух resume.
  // Держим ровно одну.
  bool _paused = false;
  void _pause() {
    if (_paused) return;
    _paused = true;
    _sub.pause();
  }

  void _resume() {
    if (!_paused) return;
    _paused = false;
    _sub.resume();
  }

  final _buf = BytesBuilder(copy: false);
  bool _closed = false;
  Completer<Map<String, dynamic>>? _want;
  int _max = kLanMaxFrame;

  /// Длина текущего сообщения, когда её 4 байта уже пришли.
  int? _need;

  Future<Map<String, dynamic>> next({int maxFrame = kLanMaxFrame}) {
    final want = _want = Completer<Map<String, dynamic>>();
    _max = maxFrame;
    _pump();
    if (_want != null) _resume();
    return want.future;
  }

  void _fail(Object e) {
    final want = _want;
    _want = null;
    _pause();
    if (want != null && !want.isCompleted) want.completeError(e);
  }

  void _pump() {
    final want = _want;
    if (want == null) return;
    if (_need == null && _buf.length >= 4) {
      final bytes = _buf.takeBytes();
      _buf.add(bytes);
      _need = ByteData.sublistView(bytes, 0, 4).getUint32(0);
    }
    final need = _need;
    // Отказ по длине — не дочитывая тела.
    if (need != null && need > _max) {
      return _fail(const LanWireException('protocol', 'frame too large'));
    }
    if (need != null && _buf.length >= 4 + need) {
      final bytes = _buf.takeBytes();
      _need = null;
      _want = null;
      _pause();
      if (bytes.length > 4 + need) {
        _buf.add(Uint8List.sublistView(bytes, 4 + need));
      }
      try {
        final decoded = jsonDecode(
          utf8.decode(Uint8List.sublistView(bytes, 4, 4 + need)),
        );
        if (decoded is! Map<String, dynamic>) {
          want.completeError(
            const LanWireException('protocol', 'not an object'),
          );
        } else {
          want.complete(decoded);
        }
      } on FormatException catch (e) {
        want.completeError(LanWireException('protocol', '$e'));
      }
      return;
    }
    if (_closed) {
      _fail(const LanWireException('protocol', 'connection closed'));
    }
  }
}

/// Прочитать одно сообщение из потока байтов.
Future<Map<String, dynamic>> readLanFrame(
  Stream<List<int>> input, {
  int maxFrame = kLanMaxFrame,
}) =>
    LanFrameReader(input).next(maxFrame: maxFrame);

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
  Map<String, dynamic> Function(String serverFingerprint)? header,
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
    // Подписанный заголовок — отдельным маленьким сообщением перед телом:
    // сосед проверит его, прежде чем читать тело.
    if (header != null) socket.add(encodeLanFrame(header(seen)));
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
