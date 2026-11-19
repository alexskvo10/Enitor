import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:http/http.dart' as http;

const kSyncTimeout = Duration(seconds: 20);

/// Почему обмен не удался. [code]: `unauthorized` (неверный токен),
/// `http` (сервер ответил ошибкой), `network` (не достучались),
/// `bad_response` (ответ не по протоколу).
class SyncException implements Exception {
  const SyncException(this.code, this.message, {this.status});

  final String code;
  final String message;
  final int? status;

  @override
  String toString() => status == null ? message : '$status: $message';
}

/// HTTP-клиент протокола сервера (docs/integrations/server.md).
class SyncClient {
  SyncClient({
    required String baseUrl,
    required this.token,
    http.Client? client,
  })  : baseUrl = normalizeServerUrl(baseUrl),
        _client = client ?? http.Client();

  final String baseUrl;
  final String token;
  final http.Client _client;

  Map<String, String> get _headers => {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json; charset=utf-8',
      };

  Future<Map<String, dynamic>> sync(Map<String, dynamic> body) =>
      _call('POST', '/v1/sync', body);

  Future<Map<String, dynamic>> ping() => _call('GET', '/v1/ping');

  /// Адрес UnifiedPush этого устройства: по нему сервер будит телефон.
  /// null — отписаться.
  Future<void> setPushEndpoint(String deviceId, String? endpoint) => _call(
        'PUT',
        '/v1/devices/${Uri.encodeComponent(deviceId)}/push',
        {'endpoint': endpoint},
      );

  /// Устройства, подключённые к серверу (`GET /v1/devices`).
  Future<List<SyncDevice>> devices() async {
    final r = await _call('GET', '/v1/devices');
    return [
      for (final d in r['devices'] as List? ?? const [])
        if (d is Map) SyncDevice.fromJson(d.cast<String, dynamic>()),
    ];
  }

  /// Убрать устройство из списка сервера (вместе с его адресом push).
  Future<void> forgetDevice(String deviceId) =>
      _call('DELETE', '/v1/devices/${Uri.encodeComponent(deviceId)}');

  Future<Map<String, dynamic>> _call(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    final http.Response res;
    try {
      final req = http.Request(method, Uri.parse('$baseUrl$path'))
        ..headers.addAll(_headers);
      if (body != null) req.body = jsonEncode(body);
      res = await http.Response.fromStream(
        await _client.send(req).timeout(kSyncTimeout),
      );
    } on TimeoutException {
      throw const SyncException('network', 'Server did not answer in time');
    } on SyncException {
      rethrow;
    } catch (e) {
      throw SyncException('network', '$e');
    }
    Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(res.bodyBytes));
    } catch (_) {
      decoded = null;
    }
    final error = decoded is Map ? decoded['error'] : null;
    final message =
        error is Map ? '${error['message']}' : res.reasonPhrase ?? '';
    if (res.statusCode == 401 || res.statusCode == 403) {
      throw SyncException('unauthorized', message, status: res.statusCode);
    }
    if (res.statusCode >= 300) {
      throw SyncException('http', message, status: res.statusCode);
    }
    if (decoded is! Map || decoded['ok'] != true) {
      throw SyncException(
        'bad_response',
        'Not an Enitor server reply',
        status: res.statusCode,
      );
    }
    final result = decoded['result'];
    return result is Map<String, dynamic> ? result : <String, dynamic>{};
  }

  /// Сколько поток событий может молчать, прежде чем счесть его оборванным.
  static const kEventsSilence = Duration(seconds: 75);

  /// Поток ревизий из `GET /v1/events` (SSE, событие `changed`). Кончается,
  /// когда сервер закрыл соединение; ошибка — когда не открылось.
  Stream<int> events() async* {
    final req = http.Request('GET', Uri.parse('$baseUrl/v1/events'))
      ..headers['Authorization'] = 'Bearer $token'
      ..headers['Accept'] = 'text/event-stream';
    final res = await _client.send(req).timeout(kSyncTimeout);
    if (res.statusCode == 401 || res.statusCode == 403) {
      throw SyncException(
        'unauthorized',
        'Wrong token',
        status: res.statusCode,
      );
    }
    if (res.statusCode != 200) {
      throw SyncException('http', 'No event stream', status: res.statusCode);
    }
    var event = 'message';
    final data = StringBuffer();
    // Сервер шлёт «: ping» каждые 25 с. Тишина дольше — соединение умерло
    // без закрытия (сменилась сеть, уснул роутер): ошибка, и подписка
    // переподключится, а не ждёт вечно.
    final lines = res.stream
        .timeout(kEventsSilence)
        .transform(utf8.decoder)
        .transform(const LineSplitter());
    await for (final line in lines) {
      if (line.isEmpty) {
        if (event == 'changed') {
          try {
            final rev = (jsonDecode(data.toString()) as Map)['rev'];
            if (rev is int) yield rev;
          } catch (_) {}
        }
        event = 'message';
        data.clear();
      } else if (line.startsWith('event:')) {
        event = line.substring(6).trim();
      } else if (line.startsWith('data:')) {
        data.write(line.substring(5).trim());
      }
    }
  }

  void close() => _client.close();
}

/// Устройство из списка сервера.
class SyncDevice {
  const SyncDevice({required this.id, required this.name, this.lastSeen});

  factory SyncDevice.fromJson(Map<String, dynamic> j) => SyncDevice(
        id: j['id'] as String? ?? '',
        name: j['name'] as String? ?? '',
        lastSeen: DateTime.tryParse(j['lastSeen'] as String? ?? '')?.toLocal(),
      );

  final String id;
  final String name;
  final DateTime? lastSeen;
}

/// Имя устройства для списка на сервере: ОС и имя компьютера. У Android
/// имени хоста нет («localhost») — только ОС, у планшета с « tablet»
/// (экран «Сервер» переводит это слово сам).
String syncDeviceName({bool tablet = false}) {
  final os = switch (Platform.operatingSystem) {
    'android' => 'Android',
    'windows' => 'Windows',
    'linux' => 'Linux',
    'macos' => 'macOS',
    'ios' => 'iOS',
    final o => o,
  };
  final mobile = os == 'Android' || os == 'iOS';
  final kind = mobile && tablet ? '$os tablet' : os;
  final host = Platform.localHostname;
  return host.isEmpty || host == 'localhost' ? kind : '$kind · $host';
}

/// Адрес без хвостового «/» и пробелов: к нему дописываются пути `/v1/…`.
String normalizeServerUrl(String url) {
  var u = url.trim();
  while (u.endsWith('/')) {
    u = u.substring(0, u.length - 1);
  }
  return u;
}
