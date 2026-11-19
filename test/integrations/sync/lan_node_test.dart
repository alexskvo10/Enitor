import 'dart:io';

import 'package:enitor/data/models/task.dart';
import 'package:enitor/features/integrations/sync/lan/lan_crypto.dart';
import 'package:enitor/features/integrations/sync/lan/lan_discovery.dart';
import 'package:enitor/features/integrations/sync/lan/lan_group.dart';
import 'package:enitor/features/integrations/sync/lan/lan_node.dart';
import 'package:enitor/features/integrations/sync/lan/lan_wire.dart';
import 'package:flutter_test/flutter_test.dart';

import 'memory_storage.dart';

// Синхронизация по сети вживую: несколько «устройств» на одном компьютере,
// настоящие TLS-сокеты на 127.0.0.1. Поиск в сети здесь не проверяем —
// адрес даём сами, как из QR-кода.

final _day = DateTime(2026, 11, 11);

Map<String, dynamic> _task(String id, String title) => Task(
      id: id,
      title: title,
      date: _day,
      createdAt: _day,
      updatedAt: _day,
    ).toJson();

class _Device {
  _Device(this.storage, this.node);

  final MemoryStorage storage;
  final LanNode node;

  String get id => node.deviceId;
  Map<String, dynamic>? task(String id) =>
      storage.readList('tasks').where((t) => t['id'] == id).firstOrNull;
  Future<void> setTasks(List<Map<String, dynamic>> l) =>
      storage.writeList('tasks', l);
  LanMember? member(String id) =>
      node.members.where((m) => m.id == id).firstOrNull;
}

late Directory _dir;
final _all = <_Device>[];

Future<_Device> _device(String name) async {
  final storage = await MemoryStorage.create();
  final node = LanNode(
    storage: storage,
    identity: LanIdentity.generate(),
    storeFile: File('${_dir.path}/$name-${_all.length}.json'),
    deviceName: name,
    // Свой порт поиска у каждого: тесты не должны слышать друг друга.
    discoveryPort: 0,
    preferredPort: 0,
    // Перебор адресов — только по этому компьютеру, не по настоящей сети.
    sweepHosts: () async => ['127.0.0.1'],
  );
  await node.start();
  final d = _Device(storage, node);
  _all.add(d);
  return d;
}

/// [guest] знакомится с [host] по коду (подтверждение — [accept]).
Future<LanMember> _pair(_Device host, _Device guest, {bool accept = true}) {
  final p = host.node.openPairing();
  host.node.confirmJoin = (_) async => accept;
  return guest.node.join(p.code, hosts: ['127.0.0.1'], port: host.node.port);
}

void main() {
  setUp(() async {
    _dir = await Directory.systemTemp.createTemp('enitor-lan-');
  });

  group('чтение сообщений', () {
    final f1 = encodeLanFrame({'n': 1});
    final f2 = encodeLanFrame({'n': 2, 'pad': 'x' * 3000});

    test('два сообщения одним куском и одно, порезанное на части', () async {
      final r = LanFrameReader(
        Stream.fromIterable([
          [...f1, ...f2.sublist(0, 10)],
          f2.sublist(10, 2000),
          f2.sublist(2000),
        ]),
      );
      expect((await r.next())['n'], 1);
      expect((await r.next())['n'], 2);
      await expectLater(r.next(), throwsA(isA<LanWireException>()));
    });

    test('три сообщения одним куском — читаются все', () async {
      final r = LanFrameReader(Stream.value([...f1, ...f2, ...f1]));
      expect((await r.next())['n'], 1);
      expect((await r.next())['n'], 2);
      expect((await r.next())['n'], 1);
    });

    test('слишком длинное отвергается по заголовку длины', () async {
      // Только 4 байта длины: тело не нужно, чтобы отказать.
      final head = Stream<List<int>>.value(f2.sublist(0, 4));
      await expectLater(
        readLanFrame(head, maxFrame: 1000),
        throwsA(isA<LanWireException>()),
      );
    });
  });

  tearDown(() async {
    for (final d in _all) {
      await d.node.stop();
    }
    _all.clear();
    await _dir.delete(recursive: true);
  });

  test(
      'знакомство по коду: оба устройства в группе, задачи ходят в обе стороны',
      () async {
    final a = await _device('Windows · LAPTOP');
    final b = await _device('Android');
    String? asked;
    final p = a.node.openPairing();
    a.node.confirmJoin = (name) async {
      asked = name;
      return true;
    };
    final host = await b.node
        .join(
          formatPairCode(p.code).toLowerCase(),
          hosts: ['127.0.0.1'],
          port: a.node.port,
        )
        .catchError((Object e) => throw e);
    expect(asked, 'Android');
    expect(host.id, a.id);
    expect(a.member(b.id)?.name, 'Android');
    expect(b.member(a.id)?.name, 'Windows · LAPTOP');
    expect(a.node.pairing, isNull, reason: 'код одноразовый');

    await a.setTasks([_task('x', 'Купить хлеб')]);
    await b.node.syncPeer(a.id);
    expect(b.task('x')?['title'], 'Купить хлеб');

    await b.setTasks([_task('x', 'Купить хлеб и молоко')]);
    await b.node.syncPeer(a.id);
    await a.node.localRound();
    expect(a.task('x')?['title'], 'Купить хлеб и молоко');
    expect(b.node.peer(a.id)?.error, isNull);
  });

  test('поддельное объявление по UDP не уводит адрес соседа', () async {
    final a = await _device('Windows');
    final b = await _device('Android');
    final stranger = await _device('Чужой');
    await _pair(a, b);
    await b.node.syncPeer(a.id);

    // Кто-то в сети объявляет себя соседом «a» со своего порта.
    b.node.debugFound(
      LanAnnounce(id: a.id, port: stranger.node.port, address: '127.0.0.1'),
    );
    await a.setTasks([_task('x', 'Купить хлеб')]);
    await a.node.localRound();
    await b.node.syncPeer(a.id);

    expect(b.task('x')?['title'], 'Купить хлеб');
    expect(b.node.peer(a.id)?.port, a.node.port);
    expect(b.node.peer(a.id)?.error, isNull);
  });

  test('код вводят с ошибками в регистре и дефисах — всё равно подходит', () {
    expect(normalizePairCode('k7qf 3mzp-x2ra'), 'K7QF3MZPX2RA');
    expect(normalizePairCode('K7QF-3MZP-X2RO'), 'K7QF3MZPX2R0');
    expect(normalizePairCode('K7QF-3MZP-X2R'), isNull);
    expect(normalizePairCode('K7QF-3MZP-X2RU'), isNull);
    expect(formatPairCode('K7QF3MZPX2RA'), 'K7QF-3MZP-X2RA');
    expect(generatePairCode(), hasLength(kPairCodeLength));
  });

  test('неверный код: отказ, после пяти ошибок код меняется', () async {
    final a = await _device('A');
    final b = await _device('B');
    final p = a.node.openPairing();
    final first = p.code;
    final wrong = first.replaceRange(0, 1, first[0] == '0' ? '1' : '0');
    for (var i = 0; i < kPairingMaxFailures; i++) {
      await expectLater(
        b.node.join(wrong, hosts: ['127.0.0.1'], port: a.node.port),
        throwsA(isA<LanException>().having((e) => e.code, 'code', 'bad_code')),
      );
    }
    expect(a.node.pairing!.code, isNot(first));
    expect(a.member(b.id), isNull);
  });

  test('на устройстве с кодом нажали «Нет» — никто ни к кому не добавлен',
      () async {
    final a = await _device('A');
    final b = await _device('B');
    await expectLater(
      _pair(a, b, accept: false),
      throwsA(isA<LanException>().having((e) => e.code, 'code', 'declined')),
    );
    expect(a.member(b.id), isNull);
    expect(b.member(a.id), isNull);
  });

  test(
      'в QR-коде несколько адресов, первый недоступен — подключается по второму',
      () async {
    final a = await _device('A');
    final b = await _device('B');
    final p = a.node.openPairing();
    a.node.confirmJoin = (_) async => true;
    final host = await b.node.join(
      p.code,
      // 10.x пробуется первым (домашние адреса — вперёд) и не отвечает.
      hosts: ['127.0.0.1', '10.255.255.1'],
      port: a.node.port,
      fingerprint: a.node.identity.fingerprint,
    );
    expect(host.id, a.id);
  });

  test('чужой сертификат вместо запомненного (из QR) — соединение рвётся',
      () async {
    final a = await _device('A');
    final b = await _device('B');
    final p = a.node.openPairing();
    a.node.confirmJoin = (_) async => true;
    await expectLater(
      b.node.join(
        p.code,
        hosts: ['127.0.0.1'],
        port: a.node.port,
        fingerprint: 'ab' * 32,
      ),
      throwsA(isA<LanException>().having((e) => e.code, 'code', 'pin')),
    );
    expect(a.member(b.id), isNull);
  });

  test('по цепочке: правка с ноутбука доходит до планшета через телефон',
      () async {
    final laptop = await _device('Windows');
    final phone = await _device('Android');
    final tablet = await _device('Android tablet');
    await _pair(laptop, phone);
    await _pair(phone, tablet);

    await laptop.setTasks([_task('x', 'Сдать отчёт')]);
    await phone.node.syncPeer(laptop.id);
    await tablet.node.syncPeer(phone.id);
    expect(tablet.task('x')?['title'], 'Сдать отчёт');
    // Список группы разошёлся: планшет знает ноутбук, хотя не знакомился с ним.
    expect(tablet.member(laptop.id)?.name, 'Windows');
  });

  test('встречный обмен в одно время не зависает, правки обеих сторон доходят',
      () async {
    final a = await _device('A');
    final b = await _device('B');
    await _pair(a, b);
    await a.setTasks([_task('a', 'С ноутбука')]);
    await b.setTasks([_task('b', 'С телефона')]);
    await Future.wait([a.node.syncPeer(b.id), b.node.syncPeer(a.id)])
        .timeout(const Duration(seconds: 10));
    await a.node.syncPeer(b.id);
    await b.node.syncPeer(a.id);
    expect(a.task('b')?['title'], 'С телефона');
    expect(b.task('a')?['title'], 'С ноутбука');
  });

  test('отключённое устройство больше не получает данные и узнаёт об этом',
      () async {
    final a = await _device('A');
    final b = await _device('B');
    await _pair(a, b);
    var revoked = false;
    b.node.onRevoked = () => revoked = true;
    await a.node.revoke(b.id);
    await a.setTasks([_task('secret', 'Новое после отключения')]);
    await b.node.syncPeer(a.id);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(b.task('secret'), isNull);
    expect(revoked, isTrue);
    expect(b.storage.readMap(kLanGroupKey), isNull);
    expect(b.node.inGroup, isFalse);
  });

  test('до соседа не достучаться, но он сам обменялся с нами — это не ошибка',
      () async {
    final a = await _device('A');
    final b = await _device('B');
    await _pair(a, b);
    await b.node.syncPeer(a.id);
    // Входящие на B закрыты (VPN на телефоне); остановка — чтобы и его
    // фоновые обмены не мешали проверке.
    await b.node.stop();
    final p = a.node.peer(b.id)!;
    await a.node.syncPeer(b.id);
    expect(p.error, isNull);
    // Давно не было обмена — вот тогда ошибка.
    p.lastSync = DateTime.now().subtract(const Duration(minutes: 5));
    await a.node.syncPeer(b.id);
    expect(p.error, 'connect');
  });

  test('сосед сменил адрес, поиск его не видит — находится перебором',
      () async {
    final a = await _device('A');
    final b = await _device('B');
    final stranger = await _device('Чужой');
    await _pair(a, b);
    await b.setTasks([_task('y', 'С раздачи')]);
    // Старый адрес из домашней сети, обмена давно не было.
    final p = a.node.peer(b.id)!
      ..address = '10.255.255.1'
      ..lastSeen = null
      ..lastSync = DateTime.now().subtract(const Duration(hours: 9));
    await a.node.tick(sweep: true);
    expect(p.address, '127.0.0.1');
    expect(p.error, isNull);
    expect(a.task('y')?['title'], 'С раздачи');

    // Проверка сертификата узнаёт только соседей группы.
    final fp = b.member(b.id)!.fingerprint;
    expect(await lanProbe('127.0.0.1', b.node.port, {fp}), fp);
    expect(await lanProbe('127.0.0.1', stranger.node.port, {fp}), isNull);
  });

  test('подпись запроса годится только для того соседа, кому она сделана', () {
    final me = LanIdentity.generate();
    final other = LanIdentity.generate();
    final sig = lanAuthSign(me, 'ab' * 32);
    expect(lanAuthVerify(me.certPem, 'ab' * 32, sig), isTrue);
    expect(lanAuthVerify(me.certPem, 'cd' * 32, sig), isFalse);
    expect(lanAuthVerify(other.certPem, 'ab' * 32, sig), isFalse);
    expect(lanAuthVerify('мусор', 'ab' * 32, sig), isFalse);
  });

  test('адреса из ссылки знакомства — только домашние', () {
    for (final ip in ['192.168.1.5', '10.0.0.2', '172.20.1.1', '127.0.0.1']) {
      expect(isPrivateLanAddress(ip), isTrue, reason: ip);
    }
    for (final ip in ['8.8.8.8', '172.32.0.1', 'example.com', '::1', '']) {
      expect(isPrivateLanAddress(ip), isFalse, reason: ip);
    }
  });

  test('битая копия сервера на диске — узел всё равно запускается', () async {
    final a = await _device('A');
    final file = a.node.storeFile;
    await a.node.stop();
    await file.writeAsString('{"rev": 3, "records": {"tasks": ');
    await a.node.start();
    expect(a.node.running, isTrue);
    await a.setTasks([_task('x', 'После сбоя')]);
    await a.node.localRound();
    expect(await file.readAsString(), contains('После сбоя'));
  });

  test('отключение расходится по группе', () async {
    final a = await _device('A');
    final b = await _device('B');
    final c = await _device('C');
    await _pair(a, b);
    await _pair(a, c);
    await c.node.syncPeer(a.id);
    expect(c.member(b.id)?.revoked, isFalse);
    await a.node.revoke(b.id);
    await c.node.syncPeer(a.id);
    expect(c.member(b.id)?.revoked, isTrue);
  });

  test('«Выйти из группы»: соседи в сети узнают, своё про группу стёрто',
      () async {
    final a = await _device('A');
    final b = await _device('B');
    await _pair(a, b);
    await b.node.syncPeer(a.id);
    await b.node.leave();
    expect(a.member(b.id)?.revoked, isTrue);
    expect(b.storage.readMap(kLanGroupKey), isNull);
    expect(b.node.inGroup, isFalse);
  });

  group('тело запроса — только после подписи', () {
    Future<Map<String, dynamic>> send(
      _Device to,
      Map<String, dynamic> body, {
      Map<String, dynamic> Function(String fp)? header,
    }) async {
      try {
        return await lanRequest(
          '127.0.0.1',
          to.node.port,
          (_) => body,
          header: header,
          pin: to.node.identity.fingerprint,
        );
      } on LanWireException catch (e) {
        // Сервер мог закрыть соединение, не дочитав отправленное.
        return {'ok': false, 'error': e.code};
      }
    }

    test('чужой с поддельным заголовком получает отказ', () async {
      final a = await _device('A');
      final stranger = LanIdentity.generate();
      final r = await send(
        a,
        {'t': 'sync', 'pad': 'x' * 200000},
        header: (fp) => {
          't': 'auth',
          'from': 'stranger',
          'cert': stranger.certPem,
          'sig': lanAuthSign(stranger, fp),
        },
      );
      // Отказ приходит раньше, чем чужой допишет тело, — он видит либо
      // его, либо обрыв.
      expect(r['error'], isIn(['unauthorized', 'connect']));
      expect(r.containsKey('group'), isFalse);
    });

    test('без заголовка большое не читается вовсе', () async {
      final a = await _device('A');
      final r = await send(a, {'t': 'sync', 'pad': 'x' * 200000});
      expect(r['ok'], isNot(true));
    });

    test('свой по-старому (одним маленьким сообщением) — принят', () async {
      final a = await _device('A');
      final b = await _device('B');
      await _pair(a, b);
      final r = await lanRequest(
        '127.0.0.1',
        a.node.port,
        (fp) => {
          't': 'group',
          'v': 1,
          'from': b.id,
          'cert': b.node.identity.certPem,
          'sig': lanAuthSign(b.node.identity, fp),
        },
        pin: a.node.identity.fingerprint,
      );
      expect(r['ok'], isTrue);
    });
  });

  group('слияние списка группы', () {
    final t0 = DateTime.utc(2026, 11, 1), t1 = DateTime.utc(2026, 11, 2);
    LanMember m({
      String name = 'A',
      bool revoked = false,
      DateTime? at,
      String fp = 'f',
    }) =>
        LanMember(
          id: 'a',
          name: name,
          fingerprint: fp,
          tokenHash: 't',
          updatedAt: at ?? t0,
          revoked: revoked,
        );

    test('отключение побеждает более позднюю запись', () {
      final out =
          mergeLanGroups({'a': m(revoked: true)}, [m(name: 'B', at: t1)]);
      expect(out['a']!.revoked, isTrue);
      expect(out['a']!.name, 'B');
    });

    test('тот же id с другими ключами не принимается', () {
      final out = mergeLanGroups({'a': m()}, [m(fp: 'other', at: t1)]);
      expect(out['a']!.fingerprint, 'f');
    });
  });
}
