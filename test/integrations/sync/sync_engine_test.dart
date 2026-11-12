import 'dart:async';
import 'dart:io';

import 'package:enitor/data/models/recurrence_task.dart';
import 'package:enitor/data/models/recurrence_rule.dart';
import 'package:enitor/data/models/task.dart';
import 'package:enitor/features/integrations/sync/sync_engine.dart';
import 'package:enitor/server/sync_store.dart';
import 'package:flutter_test/flutter_test.dart';

import 'memory_storage.dart';

// Движок синхронизации против настоящего хранилища сервера, без HTTP: два
// «устройства» с отдельными хранилищами и один SyncStore.

final _day = DateTime(2026, 10, 28);
final _t0 = DateTime(2026, 10, 28, 9);

Map<String, dynamic> _task(String id, String title, {DateTime? done}) => Task(
      id: id,
      title: title,
      date: _day,
      createdAt: _t0,
      updatedAt: done ?? _t0,
      completedAt: done,
    ).toJson();

class _Device {
  _Device(this.storage, SyncStore server, String id)
      : engine = SyncEngine(storage, deviceId: id, send: server.sync);

  final MemoryStorage storage;
  final SyncEngine engine;

  List<Map<String, dynamic>> get tasks => storage.readList('tasks');
  Map<String, dynamic>? task(String id) =>
      tasks.where((t) => t['id'] == id).firstOrNull;
  Future<void> setTasks(List<Map<String, dynamic>> l) =>
      storage.writeList('tasks', l);
  Future<SyncRoundResult> sync() => engine.run();
}

void main() {
  late SyncStore server;
  late _Device a, b;

  setUp(() async {
    server = SyncStore.memory();
    a = _Device(await MemoryStorage.create(), server, 'A');
    b = _Device(await MemoryStorage.create(), server, 'B');
  });

  test('создание, правка и удаление доходят до другого устройства', () async {
    await a.setTasks([_task('x', 'Купить хлеб')]);
    expect((await a.sync()).sent, 1);
    await b.sync();
    expect(b.task('x')!['title'], 'Купить хлеб');

    await b.setTasks([_task('x', 'Купить хлеб и молоко')]);
    expect((await b.sync()).sent, 1);
    await a.sync();
    expect(a.task('x')!['title'], 'Купить хлеб и молоко');

    await a.setTasks([]);
    await a.sync();
    await b.sync();
    expect(b.tasks, isEmpty);
    expect(server.get('tasks', 'x'), isNull);
  });

  test('повторный обмен без правок ничего не шлёт и не получает', () async {
    await a.setTasks([_task('x', 'A')]);
    await a.sync();
    final r = await a.sync();
    expect(r.sent, 0);
    expect(r.received, 0);
  });

  test('конфликт: побеждает правка, дошедшая позже', () async {
    await a.setTasks([_task('x', 'v0')]);
    await a.sync();
    await b.sync();
    await a.setTasks([_task('x', 'от A')]);
    await b.setTasks([_task('x', 'от B')]);
    await a.sync();
    await b.sync();
    await a.sync();
    expect(a.task('x')!['title'], 'от B');
    expect(b.task('x')!['title'], 'от B');
  });

  test('экземпляр повтора, созданный на обоих устройствах, — одна задача',
      () async {
    final rule = RecurrenceRule(
      id: 'rule1',
      taskTitle: 'Зарядка',
      kind: RecurrenceKind.interval,
      startDate: _day,
      createdAt: _t0,
      updatedAt: _t0,
    );
    final onA = taskFromRule(rule, _day, order: 0, now: _t0);
    final onB = taskFromRule(rule, _day,
        order: 3,
        now: _t0.add(
          const Duration(minutes: 5),
        ),);
    expect(onA.id, onB.id);
    await a.setTasks([
      onA.copyWith(completedAt: _t0, updatedAt: _t0).toJson(),
    ]);
    await b.setTasks([onB.toJson()]);
    await a.sync();
    await b.sync();
    // Создание на B отвергнуто: осталась выполненная версия A.
    expect(b.tasks, hasLength(1));
    expect(b.tasks.single['completedAt'], isNotNull);
  });

  test('удалённая на одном устройстве запись не воскресает созданием на другом',
      () async {
    await a.setTasks([_task('r-1', 'Повтор')]);
    await a.sync();
    await a.setTasks([]);
    await a.sync();
    // B не знал о записи и создал её сам (тот же предсказуемый id).
    await b.setTasks([_task('r-1', 'Повтор')]);
    await b.sync();
    expect(b.tasks, isEmpty);
    expect(server.get('tasks', 'r-1'), isNull);
  });

  test('запись, удалённая этим же устройством, создаётся заново как правка',
      () async {
    await a.setTasks([_task('t-1', 'Копия')]);
    await a.sync();
    await a.setTasks([]);
    await a.sync();
    await a.setTasks([_task('t-1', 'Копия снова')]);
    await a.sync();
    expect(server.get('tasks', 't-1')!['title'], 'Копия снова');
  });

  test('правка во время запроса не затирается чужой и уходит следующим обменом',
      () async {
    await a.setTasks([_task('x', 'v0')]);
    await a.sync();
    await b.sync();
    await b.setTasks([_task('x', 'от B')]);
    await b.sync();

    // A забирает правку B, но человек как раз правит ту же задачу.
    final slow = SyncEngine(a.storage, deviceId: 'A', send: (body) async {
      final r = await server.sync(body);
      await a.setTasks([_task('x', 'от A, пока шёл запрос')]);
      return r;
    },);
    await slow.run();
    expect(a.task('x')!['title'], 'от A, пока шёл запрос');
    await a.sync();
    expect(server.get('tasks', 'x')!['title'], 'от A, пока шёл запрос');
  });

  test('чужая запись в неверном формате не применяется', () async {
    await server.sync({
      'cursor': 0,
      'changes': [
        {
          'coll': 'tasks',
          'id': 'bad',
          'baseRev': 0,
          'data': {'title': 1}
        ,},
      ],
    });
    // Сервер сам такую не примет.
    expect(server.get('tasks', 'bad'), isNull);
    await expectLater(
      server.put('tasks', 'bad', {'id': 'bad'}),
      throwsA(isA<StoreError>()),
    );
  });

  test('оценки (карта) синхронизуются по ключу', () async {
    await a.storage.writeMap('day_ratings', {'2026-10-28T00:00:00.000': 8});
    await a.sync();
    await b.sync();
    expect(b.storage.readMap('day_ratings'), {'2026-10-28T00:00:00.000': 8});
  });

  test('дни с чужими задачами без статистики ждут пересчёта', () async {
    await server.put('tasks', 'srv', _task('srv', 'С сервера'));
    final applied = <Set<String>>[];
    b.engine.onApplied = applied.add;
    await b.sync();
    expect(applied.single, {'tasks'});
    expect(b.storage.readMap(kSyncPendingDaysKey)!['days'], ['2026-10-28']);
  });

  test('после сброса базы свои записи не удаляют серверные', () async {
    await a.setTasks([_task('x', 'A'), _task('y', 'A2')]);
    await a.sync();
    // Восстановили старый бэкап: задачи y в нём нет.
    await a.setTasks([_task('x', 'A')]);
    await SyncEngine.reset(a.storage);
    await a.sync();
    expect(server.get('tasks', 'y'), isNotNull);
    expect(a.task('y'), isNotNull);
  });
  test('копию сервера создали заново — устройство забирает всё и отдаёт своё',
      () async {
    var store = SyncStore.memory();
    final ea = SyncEngine(a.storage, deviceId: 'A', send: (b) => store.sync(b));
    final eb = SyncEngine(b.storage, deviceId: 'B', send: (b) => store.sync(b));
    await a.setTasks([for (var i = 0; i < 5; i++) _task('t$i', 'v$i')]);
    await ea.run();
    await eb.run();
    expect(b.tasks, hasLength(5));

    // Хранилище пересоздано из восстановленного бэкапа A, где только y:
    // ревизий в нём меньше, чем курсор B.
    store = SyncStore.memory();
    await a.setTasks([_task('y', 'из бэкапа')]);
    await SyncEngine.reset(a.storage);
    await ea.run();
    await eb.run();
    expect(b.task('y')?['title'], 'из бэкапа');
    // Своё B отдал новой копии заново — оно не пропало у остальных.
    expect(store.all('tasks'), hasLength(6));
  });

  test('обмен, начатый до замены данных, не записывает старую базу', () async {
    await a.setTasks([_task('x', 'A')]);
    await a.sync();
    final gate = Completer<void>();
    final slow = SyncEngine(
      a.storage,
      deviceId: 'A',
      send: (body) async {
        await gate.future;
        return server.sync(body);
      },
    );
    final inFlight = slow.run();
    await SyncEngine.replacing(() async {
      await a.setTasks([]);
      await SyncEngine.reset(a.storage);
      gate.complete();
      expect((await inFlight).sent, 0);
      expect((await a.sync()).sent, 0, reason: 'во время замены обмена нет');
    });
    expect(a.storage.readMap(kSyncBaseKey), isNull);
    // База сброшена — отсутствие x не ушло удалением.
    await a.sync();
    expect(server.get('tasks', 'x'), isNotNull);
    expect(a.task('x'), isNotNull);
  });

  test('два обмена сразу пишут файл хранилища по очереди', () async {
    final dir = await Directory.systemTemp.createTemp('enitor-store-');
    final file = File('${dir.path}/store.json');
    final s = await SyncStore.open(file);
    await Future.wait([
      for (var i = 0; i < 10; i++)
        s.sync({
          'cursor': 0,
          'changes': [
            {'coll': 'tasks', 'id': 't$i', 'baseRev': 0, 'data': _task('t$i', 'x')},
          ],
        }),
    ]);
    final again = await SyncStore.open(file);
    expect(again.all('tasks'), hasLength(10));
    expect(again.epoch, s.epoch);
    await dir.delete(recursive: true);
  });
}
