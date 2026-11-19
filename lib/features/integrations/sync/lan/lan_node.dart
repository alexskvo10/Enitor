import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../../core/utils/secrets.dart';
import '../../../../data/sources/local/local_storage.dart';
import '../../../../server/sync_store.dart';
import '../sync_engine.dart';
import 'lan_crypto.dart';
import 'lan_discovery.dart';
import 'lan_group.dart';
import 'lan_wire.dart';

// Чистый Dart: синхронизация по локальной сети.
//
// У каждого устройства — своя копия «сервера» ([SyncStore], тот же код, что
// в enitor-server). Свои данные устройство сводит с ней обычным
// [SyncEngine] без сети, а соседи по сети подключаются к ней тем же
// протоколом, что к серверу. Так любое открытое устройство — место встречи,
// а правки доходят и по цепочке: телефон → ноутбук → планшет.

const kLanGroupKey = 'device.lan.group';
const kLanPeersKey = 'device.lan.peers';
const kLanLocalBaseKey = 'device.lan.base';
const kLanLocalCursorKey = 'device.lan.cursor';
const kLanStoreResetKey = 'device.lan.storeReset';

/// База и курсор обмена с соседом `<id>`: `device.lan.peer.<id>.base`.
const kLanPeerKeyPrefix = 'device.lan.peer.';
String lanPeerBaseKey(String id) => '$kLanPeerKeyPrefix$id.base';
String lanPeerCursorKey(String id) => '$kLanPeerKeyPrefix$id.cursor';

/// Код знакомства действует столько.
const kPairingTtl = Duration(minutes: 5);

/// После стольких неверных кодов подряд код меняется.
const kPairingMaxFailures = 5;

/// Сколько ждём «Подключить?» на устройстве с кодом.
const kPairingConfirmTimeout = Duration(seconds: 90);

/// Сосед «в сети», если откликался не раньше этого.
const kLanOnlineWindow = Duration(seconds: 75);

const kLanPreferredPort = 48789;

/// Больше стольких входящих соединений сразу не держим: каждое может прислать
/// заголовок до [kLanMaxUnsigned], а прислать его может кто угодно в сети.
const kLanMaxIncoming = 4;

/// Пропавших соседей (поиск их не находит) сам перебором ищем не чаще этого;
/// по кнопке «Синхронизировать сейчас» — сразу.
const kLanSweepEvery = Duration(minutes: 5);

/// Соседние адреса во всех своих локальных сетях (/24): где искать соседа,
/// которого не нашёл поиск — VPN глушит широковещательные пакеты, а в новой
/// сети (раздача с телефона) у соседа новый адрес.
Future<List<String>> lanSweepHosts() async {
  final own = await lanLocalAddresses();
  final out = <String>{};
  for (final ip in own) {
    if (!isPrivateLanAddress(ip) ||
        ip.startsWith('127.') ||
        ip.startsWith('169.254.')) {
      continue;
    }
    final net = ip.substring(0, ip.lastIndexOf('.'));
    for (var h = 1; h < 255; h++) {
      out.add('$net.$h');
    }
  }
  return out.difference(own.toSet()).toList();
}

/// Адрес домашней сети (IPv4) или этого же компьютера. Из ссылки знакомства
/// берём только такие: чужая ссылка не заставит устройство стучаться куда
/// попало.
bool isPrivateLanAddress(String ip) {
  final a = InternetAddress.tryParse(ip);
  if (a == null || a.type != InternetAddressType.IPv4) return false;
  final b = a.rawAddress;
  return b[0] == 10 ||
      b[0] == 127 ||
      (b[0] == 172 && b[1] >= 16 && b[1] < 32) ||
      (b[0] == 192 && b[1] == 168) ||
      (b[0] == 169 && b[1] == 254);
}

/// Почему знакомство или обмен не удались.
class LanException implements Exception {
  const LanException(this.code);

  /// `not_found` — никого с открытым кодом в сети; `bad_code`; `declined`
  /// (на том устройстве нажали «Нет» или не ответили); `bad_reply`;
  /// `unauthorized` — сосед не знает это устройство; `connect`, `timeout`,
  /// `pin` (у соседа другой сертификат), `protocol`.
  final String code;

  @override
  String toString() => 'LanException($code)';
}

/// Сосед: где его видели и как прошёл последний обмен.
class LanPeer {
  LanPeer({required this.address, required this.port, this.lastSync});

  String address;
  int port;
  DateTime? lastSeen;
  DateTime? lastSync;
  String? error;
  DateTime? lastAttempt;

  /// Новый адрес из объявления по UDP. Объявление может прислать кто угодно
  /// в той же сети, поэтому адрес меняется, только когда по нему ответил
  /// сосед со своим сертификатом (см. [LanNode.syncPeer]).
  (String, int)? unverified;

  bool online(DateTime now) => [lastSeen, lastSync]
      .any((t) => t != null && now.difference(t) < kLanOnlineWindow);
}

/// Открытое знакомство на этом устройстве.
class LanPairing {
  LanPairing(this.code, this.expires);

  String code;
  DateTime expires;
  int failures = 0;
}

class LanNode {
  LanNode({
    required LocalStorage storage,
    required this.identity,
    required this.storeFile,
    required this.deviceName,
    this.discoveryPort = kLanDiscoveryPort,
    this.preferredPort = kLanPreferredPort,
    this.sweepHosts = lanSweepHosts,
    DateTime Function()? clock,
  })  : _storage = storage,
        _clock = clock ?? DateTime.now;

  /// Где перебором искать пропавших соседей ([lanSweepHosts]).
  final Future<List<String>> Function() sweepHosts;

  final LocalStorage _storage;
  final LanIdentity identity;
  final File storeFile;
  String deviceName;
  final int discoveryPort;
  final int preferredPort;
  final DateTime Function() _clock;

  /// Чужие правки записаны в хранилище: перечитать репозитории.
  void Function(Set<String> collections)? onApplied;

  /// Что-то поменялось для экрана (соседи, знакомство, ошибки).
  void Function()? onChanged;

  /// Кто-то ввёл верный код: спросить человека «Подключить [name]?».
  Future<bool> Function(String name)? confirmJoin;

  /// Это устройство отключили с другого устройства группы.
  void Function()? onRevoked;

  late final String deviceId = _loadDeviceId();
  Map<String, LanMember> _members = {};
  final _peers = <String, LanPeer>{};
  LanPairing? pairing;

  SyncStore? _store;
  SyncEngine? _local;
  SyncEngine? _current;
  SecureServerSocket? _server;
  LanDiscovery? _discovery;
  StreamSubscription<LanAnnounce>? _foundSub;
  final _pairingSeen = <String, LanAnnounce>{};
  Timer? _tick;
  DateTime _lastSweep = DateTime(2000);
  bool _sweeping = false;
  bool _running = false;
  bool _leaving = false;
  int _incoming = 0;

  /// Входящие обмены, которые ещё идут: [stop] ждёт их, иначе запрос,
  /// дочитанный после остановки, писал бы в уже закрытую копию сервера.
  final _serving = <Future<void>>{};

  /// Хранилище пишет обмен — эти правки не свои, по ним обмен не запускать.
  bool get writing =>
      (_local?.writing ?? false) || (_current?.writing ?? false);

  bool get running => _running;
  int get port => _server?.port ?? 0;

  /// Все устройства группы, включая это.
  List<LanMember> get members => _members.values.toList();

  /// Есть с кем синхронизироваться.
  bool get inGroup =>
      _members.values.any((m) => m.id != deviceId && !m.revoked);

  LanPeer? peer(String id) => _peers[id];

  // ── Состояние ─────────────────────────────────────────────────────────────

  String _loadDeviceId() {
    final raw = _storage.readMap(kLanGroupKey);
    final id = raw?['deviceId'];
    if (id is String && id.isNotEmpty) return id;
    return generateSecretToken().substring(0, 22);
  }

  void _load() {
    final raw = _storage.readMap(kLanGroupKey);
    _members = {
      for (final m in lanMembersFromWire(raw?['members'])) m.id: m,
    };
    final self = _members[deviceId];
    if (self == null ||
        self.fingerprint != identity.fingerprint ||
        self.name != deviceName) {
      _members[deviceId] = LanMember(
        id: deviceId,
        name: deviceName,
        fingerprint: identity.fingerprint,
        tokenHash: identity.tokenHash,
        updatedAt: _clock().toUtc(),
      );
    }
    final peers = _storage.readMap(kLanPeersKey) ?? const {};
    peers.forEach((id, v) {
      if (v is! Map || v['a'] is! String || v['p'] is! int) return;
      _peers[id] = LanPeer(
        address: v['a'] as String,
        port: v['p'] as int,
        lastSync: DateTime.tryParse(v['s'] as String? ?? ''),
      );
    });
  }

  Future<void> _saveGroup() => _storage.writeMap(kLanGroupKey, {
        'deviceId': deviceId,
        'members': [for (final m in _members.values) m.toJson()],
      });

  Future<void> _savePeers() => _storage.writeMap(kLanPeersKey, {
        for (final e in _peers.entries)
          e.key: {
            'a': e.value.address,
            'p': e.value.port,
            if (e.value.lastSync != null)
              's': e.value.lastSync!.toIso8601String(),
          },
      });

  List<Map<String, dynamic>> _groupWire() =>
      [for (final m in _members.values) m.toJson()];

  /// Принять список группы от соседа. true — это устройство отключили.
  bool _mergeGroup(Object? wire) {
    final before = jsonEncode(_groupWire());
    _members = mergeLanGroups(_members, lanMembersFromWire(wire));
    if (jsonEncode(_groupWire()) != before) unawaited(_saveGroup());
    if (!_leaving && (_members[deviceId]?.revoked ?? false)) {
      unawaited(_forget().then((_) => onRevoked?.call()));
      return true;
    }
    return false;
  }

  void _notePeer(
    String id,
    String address,
    Object? port, {
    bool verified = true,
  }) {
    if (port is! int || port <= 0 || port > 65535) return;
    final p = _peers[id];
    if (p != null && !verified) {
      if (p.address == address && p.port == port) {
        p
          ..unverified = null
          ..lastSeen = _clock();
      } else {
        p.unverified = (address, port);
      }
      return;
    }
    if (p == null) {
      _peers[id] = LanPeer(address: address, port: port)..lastSeen = _clock();
      unawaited(_savePeers());
    } else {
      final moved = p.address != address || p.port != port;
      p
        ..address = address
        ..port = port
        ..unverified = null
        ..lastSeen = _clock();
      if (moved) unawaited(_savePeers());
    }
  }

  // ── Запуск ────────────────────────────────────────────────────────────────

  Future<void> start() async {
    if (_running) return;
    try {
      await _start();
    } catch (_) {
      // Порт или файл подвели на полпути — не оставлять открытым то, что
      // успели открыть: следующий запуск начнёт с чистого листа.
      await stop();
      rethrow;
    }
  }

  Future<void> _start() async {
    _load();
    await _saveGroup();
    if (_storage.readMap(kLanStoreResetKey) != null) {
      try {
        if (await storeFile.exists()) await storeFile.delete();
      } catch (_) {}
      await _storage.remove(kLanStoreResetKey);
    }
    SyncStore store;
    try {
      store = await SyncStore.open(storeFile);
    } catch (_) {
      // Копия испорчена (оборванная запись): собрать заново из своих данных.
      // Соседи заметят новую копию по смене эпохи и заберут всё с начала.
      try {
        await storeFile.delete();
      } catch (_) {}
      await _storage.remove(kLanLocalBaseKey);
      await _storage.remove(kLanLocalCursorKey);
      store = await SyncStore.open(storeFile);
    }
    _store = store;
    _local = SyncEngine(
      _storage,
      deviceId: deviceId,
      deviceName: deviceName,
      baseKey: kLanLocalBaseKey,
      cursorKey: kLanLocalCursorKey,
      send: store.sync,
    )..onApplied = (c) => onApplied?.call(c);
    final ctx = SecurityContext(withTrustedRoots: false)
      ..useCertificateChainBytes(utf8.encode(identity.certPem))
      ..usePrivateKeyBytes(utf8.encode(identity.keyPem));
    try {
      _server = await SecureServerSocket.bind(
        InternetAddress.anyIPv4,
        preferredPort,
        ctx,
      );
    } on SocketException {
      _server = await SecureServerSocket.bind(InternetAddress.anyIPv4, 0, ctx);
    }
    // Ошибки рукопожатия (чужие сканеры порта) — не повод останавливаться.
    _server!.listen(
      (s) {
        if (_incoming >= kLanMaxIncoming) return s.destroy();
        _incoming++;
        late final Future<void> serving;
        serving = _serve(s).whenComplete(() {
          _incoming--;
          _serving.remove(serving);
        });
        _serving.add(serving);
      },
      onError: (_) {},
    );
    final d = _discovery = LanDiscovery(
      id: deviceId,
      port: _server!.port,
      discoveryPort: discoveryPort,
    );
    await d.start();
    _foundSub = d.found.listen(_onFound);
    _running = true;
    // Первый перебор — через полминуты, на втором круге: обычный поиск за
    // это время находит тех, кто отвечает на него.
    _lastSweep =
        _clock().subtract(kLanSweepEvery - const Duration(seconds: 30));
    resume();
  }

  /// Приложение ушло в фон (Android): не зовём соседей и не перебираем
  /// адреса — правок здесь нет, а радио и батарея тратятся. Сервер узла
  /// работает: сосед сам придёт обменяться.
  void suspend() {
    _tick?.cancel();
    _tick = null;
  }

  /// Снова на экране: обход каждые 30 с и сразу один, не дожидаясь таймера.
  void resume() {
    if (!_running) return;
    _tick ??=
        Timer.periodic(const Duration(seconds: 30), (_) => unawaited(tick()));
    unawaited(tick());
  }

  Future<void> stop() async {
    _running = false;
    _tick?.cancel();
    _tick = null;
    await _foundSub?.cancel();
    _foundSub = null;
    _discovery?.stop();
    _discovery = null;
    await _server?.close();
    _server = null;
    // Начатые входящие — доответить (сокет с таймаутом чтения не повиснет
    // надолго, но и вечно ждать не будем).
    await Future.wait(_serving.toList())
        .timeout(const Duration(seconds: 15), onTimeout: () => const []);
    // Идущий обмен дописывает копию сервера — закрывать её после него.
    await _tail;
    _local = null;
    await _store?.close();
    _store = null;
  }

  /// Позвать соседей и обменяться с теми, кто в сети; пропавших поискать
  /// перебором адресов ([sweep] — сразу, не дожидаясь [kLanSweepEvery]).
  Future<void> tick({bool sweep = false}) async {
    if (!_running) return;
    final d = _discovery;
    if (d != null) {
      d.pairing = pairing != null && _clock().isBefore(pairing!.expires);
      await d.ask();
      for (final p in _peers.values) {
        d.askAt(p.address);
      }
    }
    if (pairing != null && !_clock().isBefore(pairing!.expires)) {
      closePairing();
    }
    await syncAll();
    await _findLost(now: sweep);
  }

  /// Соседи группы не в сети — перебрать адреса своих сетей; кого нашли,
  /// с тем запомнить новый адрес и обменяться.
  Future<void> _findLost({required bool now}) async {
    final t = _clock();
    final lost = <String, String>{
      for (final m in _members.values)
        if (m.id != deviceId &&
            !m.revoked &&
            !(_peers[m.id]?.online(t) ?? false))
          m.fingerprint: m.id,
    };
    if (!_running || _sweeping || lost.isEmpty) return;
    if (!now && t.difference(_lastSweep) < kLanSweepEvery) return;
    _sweeping = true;
    _lastSweep = t;
    try {
      final ports = <int>{
        if (preferredPort > 0) preferredPort,
        for (final id in lost.values)
          if (_peers[id] case final p?) p.port,
      };
      final targets = [
        for (final h in await sweepHosts())
          for (final p in ports) (h, p),
      ];
      final found = <String, (String, int)>{};
      var next = 0;
      Future<void> worker() async {
        while (
            _running && next < targets.length && found.length < lost.length) {
          final (host, port) = targets[next++];
          final fp = await lanProbe(host, port, lost.keys.toSet());
          if (fp != null) found[fp] ??= (host, port);
        }
      }

      await Future.wait([for (var i = 0; i < 128; i++) worker()]);
      for (final e in found.entries) {
        final id = lost[e.key]!;
        _notePeer(id, e.value.$1, e.value.$2);
        await syncPeer(id);
      }
    } finally {
      _sweeping = false;
    }
  }

  /// Объявление соседа, будто пришло по UDP — только для тестов.
  void debugFound(LanAnnounce a) => _onFound(a);

  void _onFound(LanAnnounce a) {
    if (a.pairing) _pairingSeen[a.address] = a;
    final m = _members[a.id];
    if (m == null || m.revoked) return;
    _notePeer(a.id, a.address, a.port, verified: false);
    final p = _peers[a.id]!;
    final last = p.lastAttempt;
    if (last == null ||
        _clock().difference(last) > const Duration(seconds: 20)) {
      unawaited(syncPeer(a.id));
    }
    onChanged?.call();
  }

  // ── Обмен ─────────────────────────────────────────────────────────────────

  Future<void> _tail = Future.value();

  /// Обмены по одному: два движка, пишущие одно хранилище, мешали бы друг
  /// другу (каждый принял бы чужую запись за правку человека).
  Future<T> _locked<T>(Future<T> Function() f) {
    final result = _tail.then((_) => f());
    _tail = result.then((_) {}, onError: (_) {});
    return result;
  }

  /// Свести хранилище со своей копией сервера.
  Future<void> localRound() => _locked(() async {
        if (_running && _local != null) await _local!.run();
      });

  Future<void> syncAll() async {
    await localRound();
    final now = _clock();
    for (final e in _peers.entries.toList()) {
      final m = _members[e.key];
      if (m == null || m.revoked || !e.value.online(now)) continue;
      await syncPeer(e.key);
    }
  }

  /// Отправить своё соседу и забрать его; потом — в свою копию сервера,
  /// чтобы забранное досталось и тем, кто подключится к этому устройству.
  Future<void> syncPeer(String id) => _locked(() async {
        final m = _members[id];
        final p = _peers[id];
        if (!_running || m == null || m.revoked || p == null) return;
        p.lastAttempt = _clock();
        final engine = _current = SyncEngine(
          _storage,
          deviceId: deviceId,
          deviceName: deviceName,
          baseKey: lanPeerBaseKey(id),
          cursorKey: lanPeerCursorKey(id),
          send: (body) async {
            final msg = {'t': 'sync', 'body': body};
            Map<String, dynamic>? r;
            // Сначала новый адрес из объявления: запрос проверяет сертификат
            // соседа, так что ответ по нему — подтверждение. Не ответил —
            // подделка или устарело, работаем по прежнему.
            final next = p.unverified;
            if (next != null) {
              p.unverified = null;
              try {
                r = await _request(
                  LanPeer(address: next.$1, port: next.$2),
                  m.fingerprint,
                  msg,
                );
                p
                  ..address = next.$1
                  ..port = next.$2
                  ..lastSeen = _clock();
                unawaited(_savePeers());
              } on LanException {
                r = null;
              }
            }
            r ??= await _request(p, m.fingerprint, msg);
            return (r['result'] as Map? ?? const {}).cast<String, dynamic>();
          },
        )..onApplied = (c) => onApplied?.call(c);
        try {
          await engine.run();
          p
            ..lastSync = _clock()
            ..error = null;
          await _savePeers();
        } on LanException catch (e) {
          // Сосед недавно сам обменялся с нами — до него не достучаться
          // (VPN или брандмауэр на нём режут входящие), но обмен идёт: его
          // запросы и отдают, и забирают. Ошибкой это не показывать.
          final unreachable = e.code == 'connect' || e.code == 'timeout';
          final last = p.lastSync;
          p.error = unreachable &&
                  last != null &&
                  _clock().difference(last) < kLanOnlineWindow
              ? null
              : e.code;
        } on StoreError catch (e) {
          p.error = e.code;
        } catch (_) {
          p.error = 'protocol';
        } finally {
          _current = null;
          onChanged?.call();
        }
        if (_running && _local != null) await _local!.run();
      });

  Future<Map<String, dynamic>> _request(
    LanPeer p,
    String pin,
    Map<String, dynamic> msg,
  ) async {
    final Map<String, dynamic> r;
    try {
      r = await lanRequest(
        p.address,
        p.port,
        (_) => {
          ...msg,
          'v': 1,
          'port': port,
          'group': _groupWire(),
        },
        header: (serverFp) => {
          't': 'auth',
          'from': deviceId,
          'cert': identity.certPem,
          'sig': lanAuthSign(identity, serverFp),
        },
        pin: pin,
      );
    } on LanWireException catch (e) {
      throw LanException(e.code);
    }
    // Отказ тоже может нести список: так отключённое устройство узнаёт,
    // что его отключили.
    if (_mergeGroup(r['group'])) throw const LanException('unauthorized');
    if (r['ok'] != true) throw LanException('${r['error'] ?? 'protocol'}');
    return r;
  }

  // ── Приём ─────────────────────────────────────────────────────────────────

  Future<void> _serve(SecureSocket s) async {
    Map<String, dynamic> reply;
    try {
      reply = await _answer(LanFrameReader(s), s.remoteAddress.address);
    } on StoreError catch (e) {
      reply = {'ok': false, 'error': e.code};
    } catch (_) {
      reply = {'ok': false, 'error': 'protocol'};
    }
    try {
      s.add(encodeLanFrame(reply));
      await s.flush();
    } catch (_) {}
    s.destroy();
  }

  /// Первое сообщение — не больше [kLanMaxUnsigned]: подписанный заголовок
  /// `auth`, знакомство или запрос прежней версии без заголовка. Тело после
  /// заголовка читается, только если подпись своя.
  Future<Map<String, dynamic>> _answer(
    LanFrameReader reader,
    String from,
  ) async {
    const wait = Duration(seconds: 30);
    var req = await reader.next(maxFrame: kLanMaxUnsigned).timeout(wait);
    if (req['t'] == 'auth') {
      if (!_running || _signer(req) == null) {
        return {'ok': false, 'error': 'unauthorized'};
      }
      final body = await reader.next().timeout(wait);
      req = {
        ...body,
        'from': req['from'],
        'cert': req['cert'],
        'sig': req['sig'],
      };
    }
    return switch (req['t']) {
      'sync' || 'group' => await _handleSync(req, from),
      'pair' => await _handlePair(req, from),
      _ => {'ok': false, 'error': 'unknown'},
    };
  }

  /// Устройство группы (может быть и отключённое), подписавшее запрос
  /// ключом своего сертификата для этого устройства; иначе null.
  LanMember? _signer(Map<String, dynamic> req) {
    final from = req['from'], cert = req['cert'], sig = req['sig'];
    if (from is! String || cert is! String || sig is! String) return null;
    final m = _members[from];
    if (m == null || from == deviceId) return null;
    try {
      if (certFingerprint(cert) != m.fingerprint) return null;
    } catch (_) {
      return null;
    }
    return lanAuthVerify(cert, identity.fingerprint, sig) ? m : null;
  }

  Future<Map<String, dynamic>> _handleSync(
    Map<String, dynamic> req,
    String address,
  ) async {
    final signer = _running ? _signer(req) : null;
    if (signer == null) return {'ok': false, 'error': 'unauthorized'};
    // Отключённому — только его же запись: увидит отключение и забудет
    // группу, а не будет стучаться вечно.
    if (signer.revoked) {
      return {
        'ok': false,
        'error': 'unauthorized',
        'group': [signer.toJson()],
      };
    }
    final from = signer.id;
    if (_mergeGroup(req['group'])) {
      return {'ok': false, 'error': 'unauthorized'};
    }
    // Сосед со свежим списком, где он сам отключён, сюда не дойдёт:
    // отключение уже в нашем списке после слияния.
    if (_members[from]!.revoked) return {'ok': false, 'error': 'unauthorized'};
    _notePeer(from, address, req['port']);
    _peers[from]!
      ..lastSync = _clock()
      ..error = null;
    Map<String, dynamic>? result;
    final body = req['body'];
    if (req['t'] == 'sync' && body is Map<String, dynamic>) {
      // Без очереди обменов: сосед держит свою очередь, пока ждёт ответа, и
      // встречный обмен отсюда к нему ждал бы нас — оба стояли бы вечно.
      // Копия сервера сама по себе целостна (как сервер при параллельных
      // запросах); свои правки попадают в неё отдельным localRound.
      result = await _store!.sync(body);
      // Его правки — из копии сервера в хранилище.
      unawaited(localRound());
    }
    onChanged?.call();
    return {
      'ok': true,
      'group': _groupWire(),
      if (result != null) 'result': result,
    };
  }

  // ── Знакомство: устройство с кодом ────────────────────────────────────────

  /// Показать код. Повторный вызов даёт новый код.
  LanPairing openPairing() {
    final p =
        pairing = LanPairing(generatePairCode(), _clock().add(kPairingTtl));
    _discovery?.pairing = true;
    unawaited(_discovery?.ask());
    onChanged?.call();
    return p;
  }

  void closePairing() {
    pairing = null;
    _discovery?.pairing = false;
    onChanged?.call();
  }

  /// Ссылка для QR-кода: камера телефона откроет её в Enitor.
  Future<String> pairingLink() async {
    final p = pairing;
    if (p == null) return '';
    final hosts = await lanLocalAddresses();
    return Uri(
      scheme: 'enitor',
      host: 'pair',
      queryParameters: {
        'code': p.code,
        if (hosts.isNotEmpty) 'h': hosts.join(','),
        'p': '$port',
        'fp': identity.fingerprint,
      },
    ).toString();
  }

  Future<Map<String, dynamic>> _handlePair(
    Map<String, dynamic> req,
    String address,
  ) async {
    final p = pairing;
    if (p == null || !_clock().isBefore(p.expires)) {
      return {'ok': false, 'error': 'no_pairing'};
    }
    final id = req['id'], name = req['name'], fp = req['fp'], th = req['th'];
    final mac = req['mac'];
    if (id is! String ||
        id.isEmpty ||
        id.length > 64 ||
        id == deviceId ||
        name is! String ||
        fp is! String ||
        th is! String ||
        mac is! String) {
      return {'ok': false, 'error': 'protocol'};
    }
    final code = p.code;
    final expected =
        pairMac(code, ['join', identity.fingerprint, id, name, fp, th]);
    if (!constantTimeEquals(expected, mac)) {
      if (++p.failures >= kPairingMaxFailures) {
        p
          ..code = generatePairCode()
          ..failures = 0;
        onChanged?.call();
      }
      return {'ok': false, 'error': 'bad_code'};
    }
    final shortName = name.length > 60 ? name.substring(0, 60) : name;
    final ok = await (confirmJoin?.call(shortName) ?? Future.value(false))
        .timeout(kPairingConfirmTimeout, onTimeout: () => false);
    // Пока человек думал, код могли закрыть или заменить.
    if (!ok || pairing?.code != code) return {'ok': false, 'error': 'declined'};
    final existing = _members[id];
    if (existing != null && (existing.revoked || existing.fingerprint != fp)) {
      return {'ok': false, 'error': 'declined'};
    }
    _members[id] = LanMember(
      id: id,
      name: shortName,
      fingerprint: fp,
      tokenHash: th,
      updatedAt: _clock().toUtc(),
    );
    await _saveGroup();
    _notePeer(id, address, req['port']);
    closePairing();
    final groupJson = jsonEncode(_groupWire());
    return {
      'ok': true,
      'id': deviceId,
      'fp': identity.fingerprint,
      'groupJson': groupJson,
      'mac': pairMac(code, ['accept', identity.fingerprint, fp, id, groupJson]),
    };
  }

  // ── Знакомство: устройство, где вводят код ────────────────────────────────

  /// Подключиться к устройству, на котором показан [code]. [hosts], [port],
  /// [fingerprint] — из QR-кода; без них ищем в сети.
  Future<LanMember> join(
    String code, {
    List<String> hosts = const [],
    int? port,
    String? fingerprint,
    Duration searchTime = const Duration(seconds: 3),
  }) async {
    code = normalizePairCode(code) ?? code;
    hosts = hosts.where(isPrivateLanAddress).toList();
    if (!_running) await start();
    var error = 'not_found';
    final tried = <(String, int)>{};
    Future<LanMember?> tryAll(Iterable<(String, int)> list) async {
      for (final c in list) {
        if (!tried.add(c)) continue;
        try {
          return await _joinAt(code, c.$1, c.$2, fingerprint);
        } on LanException catch (e) {
          if (e.code == 'declined') rethrow;
          // Неверный код важнее «не достучались»: про него и скажем.
          if (error != 'bad_code') error = e.code;
        }
      }
      return null;
    }

    // Адреса из QR-кода: у компьютера их бывает несколько (VPN, виртуальные
    // сети) — домашние сначала.
    if (port != null && hosts.isNotEmpty) {
      final sorted = [...hosts]..sort((a, b) => _homeRank(a) - _homeRank(b));
      final m = await tryAll([for (final h in sorted) (h, port)]);
      if (m != null) return m;
      // Устройство из QR-кода ответило, но не так — искать другое незачем.
      if (error != 'connect' && error != 'timeout') throw LanException(error);
    }
    // Ни один не ответил (или QR-кода не было) — ищем в сети.
    _pairingSeen.clear();
    await _discovery?.ask();
    await Future<void>.delayed(searchTime);
    final m = await tryAll([
      for (final a in _pairingSeen.values) (a.address, a.port),
    ]);
    if (m != null) return m;
    throw LanException(error);
  }

  static int _homeRank(String ip) => ip.startsWith('192.168.')
      ? 0
      : ip.startsWith('10.')
          ? 1
          : ip.startsWith('172.')
              ? 2
              : 3;

  Future<LanMember> _joinAt(
    String code,
    String host,
    int hostPort,
    String? pin,
  ) async {
    var serverFp = '';
    final Map<String, dynamic> r;
    try {
      r = await lanRequest(
        host,
        hostPort,
        (fp) {
          serverFp = fp;
          return {
            't': 'pair',
            'v': 1,
            'id': deviceId,
            'name': deviceName,
            'fp': identity.fingerprint,
            'th': identity.tokenHash,
            'port': port,
            'mac': pairMac(code, [
              'join',
              fp,
              deviceId,
              deviceName,
              identity.fingerprint,
              identity.tokenHash,
            ]),
          };
        },
        pin: pin,
        connectTimeout: const Duration(seconds: 3),
        timeout: kPairingConfirmTimeout + const Duration(seconds: 15),
      );
    } on LanWireException catch (e) {
      throw LanException(e.code);
    }
    if (r['ok'] != true) throw LanException('${r['error'] ?? 'protocol'}');
    final groupJson = r['groupJson'], id = r['id'], mac = r['mac'];
    if (groupJson is! String ||
        id is! String ||
        mac is! String ||
        r['fp'] != serverFp ||
        !constantTimeEquals(
          pairMac(
            code,
            ['accept', serverFp, identity.fingerprint, deviceId, groupJson],
          ),
          mac,
        )) {
      throw const LanException('bad_reply');
    }
    final Object? wire;
    try {
      wire = jsonDecode(groupJson);
    } on FormatException {
      throw const LanException('bad_reply');
    }
    final host0 = lanMembersFromWire(wire).where((m) => m.id == id).firstOrNull;
    if (host0 == null || host0.fingerprint != serverFp) {
      throw const LanException('bad_reply');
    }
    _mergeGroup(wire);
    // Своё описание — как у соседа (он мог обрезать имя).
    await _saveGroup();
    _notePeer(id, host, hostPort);
    onChanged?.call();
    unawaited(syncPeer(id));
    return host0;
  }

  // ── Отключение ────────────────────────────────────────────────────────────

  /// Отключить устройство группы: оно больше не получит данные ни от
  /// кого из группы — отключение расходится с каждым обменом.
  Future<void> revoke(String id) async {
    final m = _members[id];
    if (m == null || id == deviceId) return;
    _members[id] = m.copyWith(revoked: true, updatedAt: _clock().toUtc());
    await _saveGroup();
    _peers.remove(id);
    await _savePeers();
    await _storage.remove(lanPeerBaseKey(id));
    await _storage.remove(lanPeerCursorKey(id));
    onChanged?.call();
    unawaited(syncAll());
  }

  /// Выйти из группы: сказать соседам в сети и забыть всё про группу.
  Future<void> leave() async {
    _leaving = true;
    final self = _members[deviceId];
    if (self != null) {
      _members[deviceId] =
          self.copyWith(revoked: true, updatedAt: _clock().toUtc());
      final now = _clock();
      for (final e in _peers.entries.toList()) {
        final m = _members[e.key];
        if (m == null || m.revoked || !e.value.online(now)) continue;
        try {
          await _request(e.value, m.fingerprint, {'t': 'group'});
        } on LanException {
          // Не в сети — узнает от других.
        }
      }
    }
    await _forget();
  }

  /// Стереть всё про группу на этом устройстве (данные остаются).
  Future<void> _forget() async {
    final ids = {..._members.keys, ..._peers.keys};
    await stop();
    for (final id in ids) {
      await _storage.remove(lanPeerBaseKey(id));
      await _storage.remove(lanPeerCursorKey(id));
    }
    await _storage.remove(kLanGroupKey);
    await _storage.remove(kLanPeersKey);
    await _storage.remove(kLanLocalBaseKey);
    await _storage.remove(kLanLocalCursorKey);
    _members = {};
    _peers.clear();
    pairing = null;
    try {
      if (await storeFile.exists()) await storeFile.delete();
    } catch (_) {}
    onChanged?.call();
  }

  /// После восстановления бэкапа: иначе отсутствующие в копии записи ушли бы
  /// соседям удалениями. Своя копия сервера — тоже заново из восстановленного:
  /// её стирает следующий [start] (по пометке — бэкапу путь к файлу неизвестен).
  static Future<void> resetAfterRestore(LocalStorage storage) async {
    await storage.writeMap(kLanStoreResetKey, const {'reset': true});
    final raw = storage.readMap(kLanGroupKey);
    final peers = storage.readMap(kLanPeersKey) ?? const {};
    final ids = {
      for (final m in lanMembersFromWire(raw?['members'])) m.id,
      ...peers.keys,
    };
    for (final id in ids) {
      await storage.remove(lanPeerBaseKey(id));
      await storage.remove(lanPeerCursorKey(id));
    }
    await storage.remove(kLanLocalBaseKey);
    await storage.remove(kLanLocalCursorKey);
  }
}
