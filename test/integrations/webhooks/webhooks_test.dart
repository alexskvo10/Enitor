import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:enitor/data/models/goal.dart';
import 'package:enitor/data/repositories/goal_repository.dart';
import 'package:enitor/data/repositories/task_repository.dart';
import 'package:enitor/data/sources/local/local_storage.dart';
import 'package:enitor/features/integrations/core/secret_store.dart';
import 'package:enitor/features/integrations/webhooks/webhooks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Вебхуки: каждое действие → ровно одно событие; подпись сверяется
// независимой проверкой по formats.md; повторы по расписанию на подменённом
// времени; 410 выключает адрес; потолок очереди; обрыв → повтор; доставлено
// ровно один раз.

/// Проверка подписи так, как её сделал бы получатель по formats.md.
bool verify(String secret, Map<String, String> h, String body) {
  final ts = h['x-enitor-timestamp']!;
  final mac = Hmac(sha256, utf8.encode(secret));
  final expected = 'sha256=${mac.convert(utf8.encode('$ts.$body'))}';
  return h['x-enitor-signature'] == expected;
}

void main() {
  late ProviderContainer container;
  late MemorySecretBackend secrets;
  late HttpServer server;
  late List<(Map<String, String>, String)> received;
  var status = 200;
  var now = DateTime(2026, 10, 25, 12);

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // Биндинг тестов подменяет HttpClient заглушкой «всегда 400»; здесь
    // нужен настоящий запрос на локальный сервер.
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({});
    secrets = MemorySecretBackend();
    received = [];
    status = 200;
    now = DateTime(2026, 10, 25, 12);
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      final body = await utf8.decodeStream(req);
      final headers = <String, String>{};
      req.headers.forEach((k, v) => headers[k] = v.join(','));
      received.add((headers, body));
      req.response.statusCode = status;
      await req.response.close();
    });
    final storage = LocalStorage(await SharedPreferences.getInstance());
    container = ProviderContainer(
      overrides: [
        localStorageProvider.overrideWithValue(storage),
        secretStoreProvider.overrideWithValue(SecretStore(secrets)),
        webhookServiceProvider.overrideWith(
          (ref) => WebhookService(ref, clock: () => now),
        ),
      ],
    );
  });
  tearDown(() async {
    container.dispose();
    await server.close(force: true);
  });

  WebhookService hooks() => container.read(webhookServiceProvider);
  String url() => 'http://127.0.0.1:${server.port}/hook';

  Future<void> addEndpoint({
    Set<WebhookEvent> events = const {
      WebhookEvent.taskCompleted,
      WebhookEvent.dayClosed,
      WebhookEvent.goalAchieved,
    },
  }) =>
      hooks().saveEndpoints([
        WebhookEndpoint(id: 'w1', url: url(), events: events),
      ]);

  Future<void> settle() async {
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  test('выполнение задачи → task.completed с верной подписью и заголовками',
      () async {
    await addEndpoint(events: {WebhookEvent.taskCompleted});
    hooks().listen();
    final tasks = container.read(taskRepositoryProvider);
    final a = await tasks.createAndAdd(title: 'Отчёт', date: now);
    await tasks.createAndAdd(title: 'Ещё', date: now);
    await tasks.toggleCompleted(a);
    await settle();

    expect(received.length, 1);
    final (h, body) = received.single;
    final secret = await container.read(secretStoreProvider).webhookSecret('w1');
    expect(verify(secret, h, body), isTrue);
    expect(verify('wrong', h, body), isFalse);
    expect(h['x-enitor-event'], 'task.completed');
    expect(h['x-enitor-delivery'], isNotEmpty);
    final json = jsonDecode(body) as Map<String, Object?>;
    expect(json['type'], 'task.completed');
    expect(json['v'], 1);
    expect((json['data']! as Map)['task'], containsPair('title', 'Отчёт'));
    expect(json['id'], webhookEventId(a.id, WebhookEvent.taskCompleted));
  });

  test('удалённый адрес уносит свои неудачи — пометка «не доставлено» гаснет',
      () async {
    status = 404;
    await addEndpoint(events: {WebhookEvent.taskCompleted});
    hooks().listen();
    final tasks = container.read(taskRepositoryProvider);
    final t = await tasks.createAndAdd(title: 'A', date: now);
    await tasks.createAndAdd(title: 'B', date: now);
    await tasks.toggleCompleted(t);
    await settle();
    // 404 — повторы по графику; после последнего доставка «не доставлена».
    for (final delay in kWebhookRetryDelays) {
      now = now.add(delay + const Duration(seconds: 1));
      await hooks().process();
    }
    expect(container.read(webhookFailedProvider), isTrue);

    // Старые версии оставляли доставки после удаления адреса — не в счёт.
    await container
        .read(localStorageProvider)
        .writeList(kWebhookEndpointsKey, []);
    container.read(webhookRevisionProvider.notifier).state++;
    expect(hooks().deliveries, isNotEmpty);
    expect(container.read(webhookFailedProvider), isFalse);

    await addEndpoint(events: {WebhookEvent.taskCompleted});
    await hooks().saveEndpoints([]);
    expect(hooks().deliveries, isEmpty);
    expect(container.read(webhookFailedProvider), isFalse);
  });

  test('снять и снова поставить галочку — тот же id, второй раз не шлём',
      () async {
    await addEndpoint(events: {WebhookEvent.taskCompleted});
    hooks().listen();
    final tasks = container.read(taskRepositoryProvider);
    final t = await tasks.createAndAdd(title: 'A', date: now);
    await tasks.toggleCompleted(t);
    await tasks.toggleCompleted(tasks.taskById(t.id)!);
    await tasks.toggleCompleted(tasks.taskById(t.id)!);
    await settle();
    expect(received.length, 1);
  });

  test('последняя задача дня → task.completed и day.closed', () async {
    await addEndpoint();
    hooks().listen();
    final tasks = container.read(taskRepositoryProvider);
    final a = await tasks.createAndAdd(title: 'A', date: now);
    final b = await tasks.createAndAdd(title: 'B', date: now);
    await tasks.toggleCompleted(a);
    await settle();
    expect(received.map((r) => r.$1['x-enitor-event']), ['task.completed']);
    await tasks.toggleCompleted(b);
    await settle();
    expect(
      received.map((r) => r.$1['x-enitor-event']),
      ['task.completed', 'task.completed', 'day.closed'],
    );
    final day = jsonDecode(received.last.$2) as Map<String, Object?>;
    expect(day['data'], {
      'date': '2026-10-25',
      'done': 2,
      'total': 2,
      'productivity': 100,
    });
  });

  test('цель достигнута → goal.achieved', () async {
    await addEndpoint(events: {WebhookEvent.goalAchieved});
    hooks().listen();
    final goals = container.read(goalRepositoryProvider);
    final g = await goals.addGoal(
      title: 'Прочитать книгу',
      period: GoalPeriod.year,
      year: now.year,
    );
    await goals.toggleComplete(g);
    await settle();
    expect(received.single.$1['x-enitor-event'], 'goal.achieved');
  });

  test('изменения не от пользователя (перенос) событий не дают', () async {
    await addEndpoint();
    hooks().listen();
    final tasks = container.read(taskRepositoryProvider);
    final t = await tasks.createAndAdd(title: 'A', date: now);
    await tasks.transferTask(t, targetDate: now.add(const Duration(days: 1)));
    await settle();
    expect(received, isEmpty);
  });

  test('сервер лежит → повторы по расписанию → поднялся → ровно один раз',
      () async {
    await addEndpoint(events: {WebhookEvent.taskCompleted});
    status = 503;
    await hooks().enqueue(WebhookEvent.taskCompleted, 'x', const {});
    expect(received.length, 1);
    var d = hooks().deliveries.single;
    expect(d.status, DeliveryStatus.pending);
    expect(d.nextAt, now.add(const Duration(minutes: 1)));

    // Рано — ничего не шлём.
    now = now.add(const Duration(seconds: 30));
    await hooks().process();
    expect(received.length, 1);

    // Второй и третий провал → 5 мин, затем 30 мин.
    now = now.add(const Duration(seconds: 31));
    await hooks().process();
    d = hooks().deliveries.single;
    expect(d.nextAt, now.add(const Duration(minutes: 5)));
    now = d.nextAt;
    await hooks().process();
    expect(hooks().deliveries.single.nextAt, now.add(const Duration(minutes: 30)));

    status = 200;
    now = hooks().deliveries.single.nextAt;
    await hooks().process();
    await hooks().process();
    expect(received.length, 4);
    expect(hooks().deliveries.single.status, DeliveryStatus.delivered);
  });

  test('после 12 ч — «не доставлено», без новых попыток', () async {
    await addEndpoint(events: {WebhookEvent.taskCompleted});
    status = 500;
    await hooks().enqueue(WebhookEvent.taskCompleted, 'x', const {});
    for (final delay in kWebhookRetryDelays) {
      now = now.add(delay);
      await hooks().process();
    }
    expect(received.length, 6);
    expect(hooks().deliveries.single.status, DeliveryStatus.failed);
    now = now.add(const Duration(days: 1));
    await hooks().process();
    expect(received.length, 6);
    expect(container.read(webhookFailedProvider), isTrue);
  });

  test('вернулись в приложение — недошедшее из-за сети уходит сразу',
      () async {
    var online = false;
    final service = WebhookService(
      _refOf(container),
      clock: () => now,
      client: () => MockClient((_) async {
        if (!online) throw const SocketException('airplane');
        return http.Response('', 200);
      }),
    );
    await service.saveEndpoints([
      WebhookEndpoint(
        id: 'w1',
        url: url(),
        events: const {WebhookEvent.taskCompleted},
      ),
    ]);
    await service.enqueue(WebhookEvent.taskCompleted, 'x', const {});
    // Два провала по расписанию: следующая попытка — через 30 мин.
    now = now.add(const Duration(minutes: 1));
    await service.process();
    now = now.add(const Duration(minutes: 5));
    await service.process();
    final scheduled = service.deliveries.single;
    expect(scheduled.attempts, 3);
    expect(scheduled.nextAt, now.add(const Duration(minutes: 30)));

    // Открыли приложение, а сети всё нет — попытка не засчитана.
    now = now.add(const Duration(minutes: 2));
    await service.retryNow();
    expect(service.deliveries.single.attempts, 3);
    expect(service.deliveries.single.nextAt, scheduled.nextAt);

    // Сеть вернулась — уходит сразу, не дожидаясь расписания.
    online = true;
    await service.retryNow();
    expect(service.deliveries.single.status, DeliveryStatus.delivered);
    service.dispose();
  });

  test('410 → адрес выключен, уведомление', () async {
    await addEndpoint(events: {WebhookEvent.taskCompleted});
    status = 410;
    WebhookEndpoint? gone;
    hooks().onGone = (e) => gone = e;
    await hooks().enqueue(WebhookEvent.taskCompleted, 'x', const {});
    expect(gone?.id, 'w1');
    expect(hooks().endpoints.single.enabled, isFalse);
    await hooks().enqueue(WebhookEvent.taskCompleted, 'y', const {});
    expect(received.length, 1);
  });

  test('обрыв и таймаут → повтор, а не потеря', () async {
    final service = WebhookService(
      _refOf(container),
      clock: () => now,
      client: () => MockClient((_) async => throw TimeoutException('slow')),
    );
    await service.saveEndpoints([
      WebhookEndpoint(
        id: 'w1',
        url: url(),
        events: const {WebhookEvent.taskCompleted},
      ),
    ]);
    await service.enqueue(WebhookEvent.taskCompleted, 'x', const {});
    final d = service.deliveries.single;
    expect(d.lastCode, 0);
    expect(d.status, DeliveryStatus.pending);
    service.dispose();
  });

  test('событие, поставленное во время отправки, не теряется', () async {
    final gate = Completer<void>();
    var calls = 0;
    final service = WebhookService(
      _refOf(container),
      clock: () => now,
      client: () => MockClient((_) async {
        if (++calls == 1) await gate.future;
        return http.Response('', 200);
      }),
    );
    await service.saveEndpoints([
      WebhookEndpoint(
        id: 'w1',
        url: url(),
        events: const {WebhookEvent.taskCompleted},
      ),
    ]);
    final first = service.enqueue(WebhookEvent.taskCompleted, 'x', const {});
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final second = service.enqueue(WebhookEvent.taskCompleted, 'y', const {});
    await Future<void>.delayed(const Duration(milliseconds: 50));
    gate.complete();
    await Future.wait([first, second]);
    expect(calls, 2);
    expect(service.deliveries, hasLength(2));
    expect(
      service.deliveries.map((d) => d.status),
      everyElement(DeliveryStatus.delivered),
    );
    service.dispose();
  });

  test('потолок очереди — 500, старые выпадают', () async {
    await addEndpoint(events: {WebhookEvent.taskCompleted});
    await container.read(localStorageProvider).writeList(kWebhookQueueKey, [
      for (var i = 0; i < 600; i++)
        WebhookDelivery(
          id: 'd$i',
          endpointId: 'w1',
          eventId: 'e$i',
          type: WebhookEvent.taskCompleted,
          body: '{}',
          createdAt: now,
          nextAt: now.add(const Duration(days: 1)),
        ).toJson(),
    ]);
    await hooks().process();
    final list = hooks().deliveries;
    expect(list.length, kWebhookQueueLimit);
    expect(list.first.id, 'd100');
  });

  test('«Проверить» шлёт ping и сообщает итог', () async {
    await addEndpoint();
    expect(await hooks().test('w1'), isTrue);
    expect(received.single.$1['x-enitor-event'], 'ping');
    status = 500;
    expect(await hooks().test('w1'), isFalse);
  });

  test('без адресов — ни одного запроса; очередь и адреса не в бэкапе',
      () async {
    hooks().listen();
    final tasks = container.read(taskRepositoryProvider);
    final t = await tasks.createAndAdd(title: 'A', date: now);
    await tasks.toggleCompleted(t);
    await settle();
    expect(received, isEmpty);
    await addEndpoint();
    await hooks().enqueue(WebhookEvent.taskCompleted, 'x', const {});
    final snap = container.read(localStorageProvider).snapshot();
    expect(snap.keys.where((k) => k.startsWith('device.')), isEmpty);
  });

  test('журнал: срок хранения 7 дней, очистка не трогает ожидающие', () async {
    await addEndpoint(events: {WebhookEvent.taskCompleted});
    await hooks().enqueue(WebhookEvent.taskCompleted, 'old', const {});
    now = now.add(const Duration(days: 8));
    await hooks().enqueue(WebhookEvent.taskCompleted, 'new', const {});
    expect(hooks().deliveries.length, 1);
    status = 500;
    await hooks().enqueue(WebhookEvent.taskCompleted, 'pending', const {});
    await hooks().clearLog();
    expect(hooks().deliveries.single.status, DeliveryStatus.pending);
  });
}

/// Ref контейнера — чтобы собрать сервис с подменённым http-клиентом.
Ref _refOf(ProviderContainer c) => c.read(_refProvider);
final _refProvider = Provider<Ref>((ref) => ref);
