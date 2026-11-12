import 'dart:async';
import 'dart:convert';
import 'dart:io';

// Чистый Dart: поиск устройств Enitor в той же сети — широковещательный UDP.
// В сообщении нет данных: только id устройства и TCP-порт. Подлинность
// проверяется потом, на TLS-соединении.

const kLanDiscoveryPort = 48788;

/// Устройство откликнулось.
class LanAnnounce {
  const LanAnnounce({
    required this.id,
    required this.port,
    required this.address,
    this.pairing = false,
  });

  final String id;
  final int port;

  /// Откуда пришёл пакет — по этому адресу и стучимся.
  final String address;

  /// Открыто знакомство: на этом устройстве сейчас показан код.
  final bool pairing;
}

/// Разобрать пакет; чужое — null.
LanAnnounce? parseLanAnnounce(List<int> data, String address) {
  try {
    final m = jsonDecode(utf8.decode(data));
    if (m is! Map || m['enitor'] != 1) return null;
    final id = m['id'], port = m['port'];
    if (id is! String || id.isEmpty || id.length > 64) return null;
    if (port is! int || port <= 0 || port > 65535) return null;
    return LanAnnounce(
      id: id,
      port: port,
      address: address,
      pairing: m['pair'] == true,
    );
  } catch (_) {
    return null;
  }
}

List<int> encodeLanAnnounce({
  required String id,
  required int port,
  bool pairing = false,
  bool query = false,
}) =>
    utf8.encode(
      jsonEncode({
        'enitor': 1,
        'id': id,
        'port': port,
        if (pairing) 'pair': true,
        if (query) 'q': true,
      }),
    );

/// Широковещательные адреса: общий и /24 каждого IPv4-интерфейса (Windows
/// шлёт 255.255.255.255 только в одну сеть). Маску Dart не даёт — /24
/// покрывает почти все домашние сети.
Future<List<InternetAddress>> lanBroadcastTargets() async {
  final out = <String>{'255.255.255.255'};
  try {
    for (final i in await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    )) {
      for (final a in i.addresses) {
        final p = a.address.split('.');
        if (p.length == 4) out.add('${p[0]}.${p[1]}.${p[2]}.255');
      }
    }
  } catch (_) {}
  return [for (final a in out) InternetAddress(a)];
}

/// Свои адреса в сети (для QR-кода).
Future<List<String>> lanLocalAddresses() async {
  try {
    return [
      for (final i in await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      ))
        for (final a in i.addresses) a.address,
    ];
  } catch (_) {
    return const [];
  }
}

/// Слушает и рассылает объявления. На каждый пакет с вопросом отвечает
/// напрямую — телефон, который не ловит широковещательные пакеты, узнаёт
/// соседа из ответа на свой вопрос.
class LanDiscovery {
  LanDiscovery({
    required this.id,
    required this.port,
    this.discoveryPort = kLanDiscoveryPort,
  });

  final String id;
  int port;
  final int discoveryPort;
  bool pairing = false;

  RawDatagramSocket? _socket;
  final _found = StreamController<LanAnnounce>.broadcast();

  Stream<LanAnnounce> get found => _found.stream;

  Future<void> start() async {
    if (_socket != null) return;
    final s = _socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      discoveryPort,
      reuseAddress: true,
    );
    s.broadcastEnabled = true;
    s.listen((e) {
      if (e != RawSocketEvent.read) return;
      final d = s.receive();
      if (d == null) return;
      final a = parseLanAnnounce(d.data, d.address.address);
      if (a == null || a.id == id) return;
      try {
        if (jsonDecode(utf8.decode(d.data))['q'] == true) {
          s.send(_packet(query: false), d.address, d.port);
        }
      } catch (_) {}
      _found.add(a);
    });
  }

  List<int> _packet({required bool query}) =>
      encodeLanAnnounce(id: id, port: port, pairing: pairing, query: query);

  /// Спросить сеть «кто здесь?» (заодно объявить себя).
  Future<void> ask() async {
    final s = _socket;
    if (s == null) return;
    for (final t in await lanBroadcastTargets()) {
      try {
        s.send(_packet(query: true), t, discoveryPort);
      } catch (_) {}
    }
  }

  /// Спросить конкретный адрес (запомненный или из QR-кода).
  void askAt(String address) {
    final s = _socket;
    if (s == null) return;
    try {
      s.send(_packet(query: true), InternetAddress(address), discoveryPort);
    } catch (_) {}
  }

  void stop() {
    _socket?.close();
    _socket = null;
  }
}
