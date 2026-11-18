import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:enitor/data/models/recurrence_rule.dart';
import 'package:enitor/data/models/schedule_item.dart';
import 'package:enitor/features/integrations/sync/sync_client.dart';
import 'package:enitor/features/integrations/sync/sync_engine.dart';
import 'package:enitor/server/server_app.dart';
import 'package:enitor/server/sync_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../integrations/sync/memory_storage.dart';

// Эталонный сервер на настоящем HttpServer: вход по токену, REST для
// автоматики, дни с повторами, поток событий, сигнал UnifiedPush и сквозной
// обмен с движком синхронизации устройства.

const _token = 'test-token';
final _now = DateTime(2026, 10, 28, 12);
const _day = '2026-10-28';

void main() {
  late SyncStore store;
  late EnitorServer app;
  late HttpServer server;
  late String base;

  setUp(() async {
    store = SyncStore.memory();
    app = EnitorServer(
      store,
      token: _token,
      webPage: '<p>page</p>',
      clock: () => _now,
    );
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((r) => unawaited(app.handle(r)));
    base = 'http://127.0.0.1:${server.port}';
  });
  tearDown(() async {
    await server.close(force: true);
    await app.close();
  });

  Future<(int, Map<String, dynamic>)> call(
    String method,
    String path, {
    Object? body,
    String? token = _token,
  }) async {
    final req = http.Request(method, Uri.parse('$base$path'));
    if (token != null) req.headers['Authorization'] = 'Bearer $token';
    if (body != null) req.body = jsonEncode(body);
    final res = await http.Response.fromStream(await req.send());
    return (res.statusCode, jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<dynamic> ok(String method, String path, {Object? body}) async {
    final (code, j) = await call(method, path, body: body);
    expect(code, 200, reason: '$method $path → $j');
    return j['result'];
  }

  test('без токена и с чужим — 401; ping с верным', () async {
    expect((await call('GET', '/v1/ping', token: null)).$1, 401);
    final (code, j) = await call('GET', '/v1/ping', token: 'wrong');
    expect(code, 401);
    expect(j['error']['code'], 'unauthorized');
    expect((await ok('GET', '/v1/ping'))['server'], 'enitor-server');
  });

  test('страница и CORS отдаются без токена', () async {
    final page = await http.get(Uri.parse('$base/'));
    expect(page.body, '<p>page</p>');
    final pre =
        await http.Request('OPTIONS', Uri.parse('$base/v1/tasks')).send();
    expect(pre.statusCode, 204);
    expect(pre.headers['access-control-allow-origin'], '*');
  });

  test('задача: создать, поправить, перенести, отметить, удалить', () async {
    final t = await ok(
      'POST',
      '/v1/tasks',
      body: {
        'title': ' Купить хлеб ',
        'date': _day,
        'start': '09:30',
        'priority': 'high',
        'tags': ['дом'],
      },
    ) as Map;
    expect(t['title'], 'Купить хлеб');
    expect(t['startMinutes'], 570);
    expect(t['priority'], 3);
    final id = t['id'] as String;

    final day = await ok('GET', '/v1/days/$_day') as Map;
    expect((day['tasks'] as List).single['id'], id);

    await ok(
      'PATCH',
      '/v1/tasks/$id',
      body: {'date': '2026-10-29', 'start': null},
    );
    expect(store.get('tasks', id)!['date'], startsWith('2026-10-29'));
    expect(store.get('tasks', id)!['startMinutes'], isNull);

    await ok('POST', '/v1/tasks/$id/complete');
    expect(store.get('tasks', id)!['completedAt'], isNotNull);
    await ok('POST', '/v1/tasks/$id/uncomplete');
    expect(store.get('tasks', id)!['completedAt'], isNull);

    await ok('DELETE', '/v1/tasks/$id');
    expect(store.get('tasks', id), isNull);
    expect((await call('DELETE', '/v1/tasks/$id')).$1, 404);
  });

  test('неверные поля — 400 с именем поля, запись не меняется', () async {
    var (code, j) = await call('POST', '/v1/tasks', body: {'title': ''});
    expect(code, 400);
    expect(j['error']['field'], 'title');
    (code, j) = await call(
      'POST',
      '/v1/tasks',
      body: {'title': 'x', 'date': '2026-02-30'},
    );
    expect(j['error']['field'], 'date');
    (code, j) =
        await call('POST', '/v1/tasks', body: {'title': 'x', 'start': '25:00'});
    expect(j['error']['field'], 'start');
    (code, j) =
        await call('POST', '/v1/tasks', body: {'title': 'x', 'order': 'нет'});
    expect(j['error']['code'], 'bad_record');
    expect(store.all('tasks'), isEmpty);
  });

  group('повторы', () {
    setUp(() async {
      await store.put(
        'recurrence',
        'rule1',
        RecurrenceRule(
          id: 'rule1',
          taskTitle: 'Зарядка',
          kind: RecurrenceKind.interval,
          startDate: DateTime(2026, 10, 1),
          createdAt: _now,
          updatedAt: _now,
        ).toJson(),
      );
    });

    test('день показывает ещё не созданный экземпляр с id устройств', () async {
      final day = await ok('GET', '/v1/days/$_day') as Map;
      final t = (day['tasks'] as List).single as Map;
      expect(t['id'], 'r-rule1-20261028');
      expect(t['virtual'], isTrue);
      expect(store.all('tasks'), isEmpty);
    });

    test('отметка экземпляра создаёт его, удаление — исключение правила',
        () async {
      await ok('POST', '/v1/tasks/r-rule1-20261028/complete');
      final t = store.get('tasks', 'r-rule1-20261028')!;
      expect(t['completedAt'], isNotNull);
      expect(t['recurrenceRuleId'], 'rule1');
      expect(t.containsKey('virtual'), isFalse);

      await ok('DELETE', '/v1/tasks/r-rule1-20261029');
      final rule = RecurrenceRule.fromJson(store.get('recurrence', 'rule1')!);
      expect(rule.exceptDates.single, DateTime(2026, 10, 29));
      final next = await ok('GET', '/v1/days/2026-10-29') as Map;
      expect(next['tasks'], isEmpty);
    });

    test('диапазон дней, ограничение длины', () async {
      final days =
          await ok('GET', '/v1/days?from=2026-10-28&to=2026-10-30') as List;
      expect(
        days.map((d) => d['date']),
        ['2026-10-28', '2026-10-29', '2026-10-30'],
      );
      expect(
        (await call('GET', '/v1/days?from=2026-01-01&to=2026-12-31')).$1,
        400,
      );
    });
  });

  test('цели: создать на месяц, прогресс до цели — выполнена', () async {
    final g = await ok(
      'POST',
      '/v1/goals',
      body: {
        'title': 'Прочитать книги',
        'period': 'month',
        'date': _day,
        'targetCount': 3,
      },
    ) as Map;
    expect(g['month'], 10);
    final id = g['id'] as String;
    await ok('POST', '/v1/goals/$id/progress', body: {'value': 3});
    expect(store.get('goals', id)!['completed'], isTrue);
    await ok('POST', '/v1/goals/$id/uncomplete');
    expect(store.get('goals', id)!['completed'], isFalse);
    final list = await ok('GET', '/v1/goals?date=2026-10-05') as List;
    expect(list, hasLength(1));
    expect(await ok('GET', '/v1/goals?date=2026-11-05'), isEmpty);
    expect(
      (await call('POST', '/v1/goals', body: {'title': 'x', 'period': 'day'}))
          .$1,
      400,
    );
  });

  test('расписание: серия, правка одного дня, удаление одного дня', () async {
    final s = await ok(
      'POST',
      '/v1/schedule',
      body: {
        'title': 'Матанализ',
        'date': '2026-10-26',
        'start': '10:00',
        'end': '11:30',
        'repeat': 'weekly',
        'weekdays': [1, 3],
      },
    ) as Map;
    final id = s['id'] as String;
    final wed = await ok('GET', '/v1/days/$_day') as Map;
    expect((wed['schedule'] as List).single['title'], 'Матанализ');

    final one = await ok(
      'PATCH',
      '/v1/schedule/$id?scope=day&date=$_day',
      body: {'location': 'ауд. 101'},
    ) as Map;
    expect(one['repeat'], isNull);
    expect(one['location'], 'ауд. 101');
    final after = await ok('GET', '/v1/days/$_day') as Map;
    expect((after['schedule'] as List).single['id'], one['id']);

    await ok('DELETE', '/v1/schedule/$id?scope=day&date=2026-11-02');
    final item = ScheduleItem.fromJson(store.get('schedule', id)!);
    expect(item.occursOn(DateTime(2026, 11, 2)), isFalse);
    expect(item.occursOn(DateTime(2026, 11, 4)), isTrue);

    final (code, j) = await call(
      'PATCH',
      '/v1/schedule/$id',
      body: {'end': '09:00'},
    );
    expect(code, 400);
    expect(j['error']['field'], 'end');

    await ok('DELETE', '/v1/schedule/$id');
    expect(store.get('schedule', id), isNull);
  });

  test('поток событий: текущая ревизия сразу, новая — после правки', () async {
    final client = SyncClient(baseUrl: base, token: _token);
    final revs = <int>[];
    final first = Completer<void>();
    final got = Completer<void>();
    final sub = client.events().listen((r) {
      revs.add(r);
      if (revs.length == 1) first.complete();
      if (revs.length == 2) got.complete();
    });
    // Правка — только когда поток подключён: иначе под нагрузкой сервер
    // отдал бы сразу ревизию 1, и второго события не было бы.
    await first.future.timeout(const Duration(seconds: 5));
    await ok('POST', '/v1/tasks', body: {'title': 'x', 'date': _day});
    await got.future.timeout(const Duration(seconds: 5));
    expect(revs, [0, 1]);
    await sub.cancel();
    client.close();
  });

  test('сигнал UnifiedPush уходит на адрес устройства, без данных', () async {
    final pushes = <String>[];
    final push = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    push.listen((r) async {
      pushes.add(await utf8.decoder.bind(r).join());
      r.response.statusCode = 201;
      await r.response.close();
    });
    final endpoint = 'http://127.0.0.1:${push.port}/up/abc';
    await ok('PUT', '/v1/devices/A/push', body: {'endpoint': endpoint});
    expect(store.pushEndpoints['A'], endpoint);
    await ok('POST', '/v1/tasks', body: {'title': 'секрет', 'date': _day});
    await Future<void>.delayed(
      kPushDebounce + const Duration(milliseconds: 500),
    );
    expect(pushes, hasLength(1));
    expect(pushes.single, isNot(contains('секрет')));
    await push.close(force: true);
  });

  test('список устройств: обмен отмечает, DELETE забывает', () async {
    expect((await ok('GET', '/v1/devices'))['devices'], isEmpty);
    await ok(
      'POST',
      '/v1/sync',
      body: {
        'deviceId': 'A',
        'deviceName': 'Windows · PC',
        'cursor': 0,
        'changes': <Object>[],
      },
    );
    await ok(
      'POST',
      '/v1/sync',
      body: {
        'deviceId': 'B',
        'cursor': 0,
        'changes': <Object>[],
      },
    );
    await ok(
      'PUT',
      '/v1/devices/A/push',
      body: {'endpoint': 'https://ntfy.example/up'},
    );
    final list = (await ok('GET', '/v1/devices'))['devices'] as List;
    expect([for (final d in list) d['id']], ['B', 'A']); // недавние первыми
    expect(list.last['name'], 'Windows · PC');
    expect(list.last['push'], isTrue);
    expect(DateTime.parse(list.first['lastSeen'] as String).isUtc, isTrue);

    await ok('DELETE', '/v1/devices/A');
    expect(store.pushEndpoints, isEmpty);
    expect((await ok('GET', '/v1/devices'))['devices'], hasLength(1));
    expect((await call('DELETE', '/v1/devices/A')).$1, 404);
  });

  test('сквозь HTTP: правка автоматики доходит до устройства', () async {
    final dev = await MemoryStorage.create();
    final client = SyncClient(baseUrl: '$base/', token: _token);
    final engine = SyncEngine(dev, deviceId: 'A', send: client.sync);
    final t = await ok(
      'POST',
      '/v1/tasks',
      body: {'title': 'С сервера', 'date': _day},
    ) as Map;
    await engine.run();
    expect(dev.readList('tasks').single['title'], 'С сервера');

    await ok('POST', '/v1/tasks/${t['id']}/complete');
    final r = await engine.run();
    expect(r.received, 1);
    expect(dev.readList('tasks').single['completedAt'], isNotNull);
    expect(dev.readMap(kSyncPendingDaysKey)!['days'], [_day]);

    // И обратно: правка устройства видна через REST.
    final list = dev.readList('tasks');
    list.single['title'] = 'Поправлено на телефоне';
    await dev.writeList('tasks', list);
    await engine.run();
    expect(
      (await ok('GET', '/v1/tasks/${t['id']}'))['title'],
      'Поправлено на телефоне',
    );

    final bad = SyncClient(baseUrl: base, token: 'wrong');
    await expectLater(
      bad.sync({'cursor': 0, 'changes': <Object>[]}),
      throwsA(
        isA<SyncException>().having((e) => e.code, 'code', 'unauthorized'),
      ),
    );
    client.close();
    bad.close();
  });

  test('данные переживают перезапуск, старые пометки удаления стираются',
      () async {
    final dir = await Directory.systemTemp.createTemp('enitor-server');
    final file = File('${dir.path}/data.json');
    final s1 = await SyncStore.open(file);
    await s1.put('dayRatings', 'k', {'value': 7});
    await s1.put('dayRatings', 'gone', {'value': 1});
    await s1.delete('dayRatings', 'gone');
    final raw = jsonDecode(await file.readAsString()) as Map;
    raw['records']['dayRatings']['gone']['at'] =
        DateTime.now().subtract(const Duration(days: 91)).toIso8601String();
    await file.writeAsString(jsonEncode(raw));

    final s2 = await SyncStore.open(file);
    expect(s2.get('dayRatings', 'k'), {'value': 7});
    expect(s2.rev, 3);
    final out = await s2.sync({'cursor': 0, 'changes': <Object>[]});
    expect((out['changes'] as List).map((c) => c['id']), ['k']);
    await dir.delete(recursive: true);
  });

  test('папку восстановили из старой копии — устройство с курсором впереди '
      'получает всё', () async {
    final dir = await Directory.systemTemp.createTemp('enitor-server');
    final file = File('${dir.path}/data.json');
    final s1 = await SyncStore.open(file);
    await s1.put('dayRatings', 'x', {'value': 1});
    final copy = await file.readAsString(); // бэкап папки на rev 1
    await s1.put('dayRatings', 'y', {'value': 2});
    await s1.put('dayRatings', 'z', {'value': 3}); // устройство B видело rev 3
    await file.writeAsString(copy); // восстановили

    final s2 = await SyncStore.open(file);
    await s2.put('dayRatings', 'w', {'value': 4}); // снова rev 2
    final out = await s2.sync({
      'cursor': 3,
      'epoch': s2.epoch,
      'changes': <Object>[],
    });
    expect((out['changes'] as List).map((c) => c['id']),
        containsAll(['x', 'w']));
    await dir.delete(recursive: true);
  });
}
