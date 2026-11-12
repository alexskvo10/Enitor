import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:enitor/data/repositories/stats_repository.dart';
import 'package:enitor/data/repositories/task_repository.dart';
import 'package:enitor/data/sources/local/local_storage.dart';
import 'package:enitor/features/integrations/core/secret_store.dart';
import 'package:enitor/features/integrations/sync/sync_client.dart';
import 'package:enitor/features/integrations/sync/sync_engine.dart';
import 'package:enitor/features/integrations/sync/sync_service.dart';
import 'package:enitor/server/server_app.dart';
import 'package:enitor/server/sync_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'memory_storage.dart';

// Служба синхронизации целиком: два «устройства» (свои хранилища и
// репозитории) и эталонный сервер на 127.0.0.1.

const _token = 'tok';
final _day = DateTime(2026, 10, 28);

class _Device {
  _Device(this.storage, this.secrets)
      : container = ProviderContainer(overrides: [
          localStorageProvider.overrideWithValue(storage),
          secretStoreProvider.overrideWithValue(SecretStore(secrets)),
        ],);

  final MemoryStorage storage;
  final MemorySecretBackend secrets;
  final ProviderContainer container;

  SyncService get sync => container.read(syncServiceProvider);
  TaskRepository get tasks => container.read(taskRepositoryProvider);
}

void main() {
  late SyncStore store;
  late EnitorServer app;
  late HttpServer server;
  late String base;
  late _Device a, b;

  setUp(() async {
    store = SyncStore.memory();
    app = EnitorServer(store, token: _token);
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((r) => unawaited(app.handle(r)));
    base = 'http://127.0.0.1:${server.port}';
    a = _Device(await MemoryStorage.create(), MemorySecretBackend());
    b = _Device(await MemoryStorage.create(), MemorySecretBackend());
  });
  tearDown(() async {
    a.container.dispose();
    b.container.dispose();
    await server.close(force: true);
    await app.close();
  });

  test('неверный токен: подключение не сохраняется', () async {
    await expectLater(
      a.sync.connect(url: base, token: 'wrong', takeServer: false),
      throwsA(
          isA<SyncException>().having((e) => e.code, 'code', 'unauthorized'),),
    );
    expect(a.sync.settings.connected, isFalse);
    expect(await SecretStore(a.secrets).serverToken(), isNull);
  });

  test('задача с телефона появляется на ПК, экраны получают её сразу',
      () async {
    final t = await a.tasks.createAndAdd(title: 'Позвонить', date: _day);
    await a.sync.connect(url: base, token: _token, takeServer: false);
    expect(a.sync.settings.lastSyncAt, isNotNull);
    expect(a.sync.log.first.sent, greaterThan(0));

    final seen = b.tasks.watchTasksForDay(_day).skip(1).first;
    await b.sync.connect(url: '$base/', token: _token, takeServer: false);
    expect((await seen).single.id, t.id);
    expect(b.sync.settings.url, base);
  });

  test('отметка автоматикой на сервере пересчитывает статистику дня', () async {
    final t = await a.tasks.createAndAdd(title: 'Зарядка', date: _day);
    await a.sync.connect(url: base, token: _token, takeServer: false);
    await http.post(
      Uri.parse('$base/v1/tasks/${t.id}/complete'),
      headers: {'Authorization': 'Bearer $_token'},
    );
    await a.sync.syncNow();
    expect(a.tasks.tasksForDay(_day).single.isCompleted, isTrue);
    final stats =
        await a.container.read(statsRepositoryProvider).watchDay(_day).first;
    expect(stats!.completedTasks, 1);
    expect(a.storage.readMap(kSyncPendingDaysKey)!['days'], isEmpty);
  });

  test('«взять с сервера» заменяет данные устройства, перед этим бэкап',
      () async {
    await a.tasks.createAndAdd(title: 'На сервере', date: _day);
    await a.sync.connect(url: base, token: _token, takeServer: false);
    await b.tasks.createAndAdd(title: 'Только на B', date: _day);
    await b.sync.connect(url: base, token: _token, takeServer: true);
    expect(b.tasks.allTasks.map((t) => t.title), ['На сервере']);
  });

  test('ошибка сети попадает в журнал и состояние, данные целы', () async {
    await a.sync.connect(url: base, token: _token, takeServer: false);
    await a.tasks.createAndAdd(title: 'x', date: _day);
    await server.close(force: true);
    await a.sync.syncNow();
    expect(a.sync.settings.lastErrorCode, 'network');
    expect(a.sync.log.first.error, isNotNull);
    expect(a.tasks.allTasks, hasLength(1));
  });

  test('отключение забывает токен и базу, задачи остаются', () async {
    await a.tasks.createAndAdd(title: 'x', date: _day);
    await a.sync.connect(url: base, token: _token, takeServer: false);
    await a.sync.disconnect();
    expect(a.sync.settings.connected, isFalse);
    expect(await SecretStore(a.secrets).serverToken(), isNull);
    expect(a.storage.readMap(kSyncBaseKey), isNull);
    expect(a.tasks.allTasks, hasLength(1));
    expect(jsonEncode(a.storage.values).contains(_token), isFalse);
  });
}
