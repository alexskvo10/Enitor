import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../../data/models/goal.dart';
import '../../../data/models/task.dart';
import '../../../data/repositories/goal_repository.dart';
import '../../../data/repositories/task_repository.dart';
import '../../../data/sources/local/local_storage.dart';
import '../core/command_handler.dart';
import '../core/integration_command.dart';
import '../core/secret_store.dart';

// Ключи «устройство»: адреса, очередь и журнал живут только на этом
// устройстве — в бэкап не попадают, и восстановление бэкапа ничего не
// отправляет заново.
const kWebhookEndpointsKey = 'device.webhooks.endpoints';
const kWebhookQueueKey = 'device.webhooks.queue';
const kWebhookSettingsKey = 'device.webhooks.settings';

/// Типы событий (formats.md, раздел 3).
enum WebhookEvent {
  taskCompleted('task.completed'),
  dayClosed('day.closed'),
  goalAchieved('goal.achieved'),
  ping('ping');

  const WebhookEvent(this.wire);
  final String wire;

  static WebhookEvent? fromWire(String s) =>
      values.where((e) => e.wire == s).firstOrNull;
}

/// Пауза перед каждым повтором: 1 мин → 5 мин → 30 мин → 2 ч → 12 ч, дальше —
/// «не доставлено».
const kWebhookRetryDelays = [
  Duration(minutes: 1),
  Duration(minutes: 5),
  Duration(minutes: 30),
  Duration(hours: 2),
  Duration(hours: 12),
];

/// Потолок очереди: при переполнении выпадают самые старые записи.
const kWebhookQueueLimit = 500;
const kWebhookTimeout = Duration(seconds: 10);

class WebhookEndpoint {
  const WebhookEndpoint({
    required this.id,
    required this.url,
    required this.events,
    this.enabled = true,
  });

  final String id;
  final String url;
  final Set<WebhookEvent> events;

  /// Выключается сам при ответе 410 Gone — адрес сказал «меня больше нет».
  final bool enabled;

  WebhookEndpoint copyWith({
    String? url,
    Set<WebhookEvent>? events,
    bool? enabled,
  }) =>
      WebhookEndpoint(
        id: id,
        url: url ?? this.url,
        events: events ?? this.events,
        enabled: enabled ?? this.enabled,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'url': url,
        'events': [for (final e in events) e.wire],
        'enabled': enabled,
      };

  factory WebhookEndpoint.fromJson(Map<String, dynamic> j) => WebhookEndpoint(
        id: j['id'] as String,
        url: j['url'] as String,
        events: {
          for (final e in (j['events'] as List? ?? const []))
            if (WebhookEvent.fromWire(e as String) != null)
              WebhookEvent.fromWire(e)!,
        },
        enabled: j['enabled'] as bool? ?? true,
      );
}

enum DeliveryStatus { pending, delivered, failed }

/// Одна доставка: событие × адрес. Она же — строка журнала.
class WebhookDelivery {
  const WebhookDelivery({
    required this.id,
    required this.endpointId,
    required this.eventId,
    required this.type,
    required this.body,
    required this.createdAt,
    required this.nextAt,
    this.attempts = 0,
    this.status = DeliveryStatus.pending,
    this.lastCode,
  });

  /// `X-Enitor-Delivery`: свой у каждой серии попыток.
  final String id;
  final String endpointId;
  final String eventId;
  final WebhookEvent type;
  final String body;
  final DateTime createdAt;
  final DateTime nextAt;
  final int attempts;
  final DeliveryStatus status;

  /// Код последнего ответа; 0 — нет ответа (сеть, таймаут).
  final int? lastCode;

  WebhookDelivery copyWith({
    DateTime? nextAt,
    int? attempts,
    DeliveryStatus? status,
    int? lastCode,
  }) =>
      WebhookDelivery(
        id: id,
        endpointId: endpointId,
        eventId: eventId,
        type: type,
        body: body,
        createdAt: createdAt,
        nextAt: nextAt ?? this.nextAt,
        attempts: attempts ?? this.attempts,
        status: status ?? this.status,
        lastCode: lastCode ?? this.lastCode,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'endpointId': endpointId,
        'eventId': eventId,
        'type': type.wire,
        'body': body,
        'createdAt': createdAt.toIso8601String(),
        'nextAt': nextAt.toIso8601String(),
        'attempts': attempts,
        'status': status.name,
        if (lastCode != null) 'lastCode': lastCode,
      };

  static WebhookDelivery? fromJson(Map<String, dynamic> j) {
    final type = WebhookEvent.fromWire(j['type'] as String? ?? '');
    if (type == null) return null;
    return WebhookDelivery(
      id: j['id'] as String,
      endpointId: j['endpointId'] as String,
      eventId: j['eventId'] as String,
      type: type,
      body: j['body'] as String,
      createdAt: DateTime.parse(j['createdAt'] as String),
      nextAt: DateTime.parse(j['nextAt'] as String),
      attempts: j['attempts'] as int? ?? 0,
      status: DeliveryStatus.values
              .where((s) => s.name == j['status'])
              .firstOrNull ??
          DeliveryStatus.pending,
      lastCode: j['lastCode'] as int?,
    );
  }
}

/// id события: хэш записи, типа и версии формата. Повтор того же факта
/// (сняли галочку и поставили снова) даёт тот же id — получатель отбросит
/// дубль.
String webhookEventId(String recordId, WebhookEvent type) =>
    'evt_${sha256.convert(utf8.encode('$recordId|${type.wire}|v$kCommandFormatVersion')).toString().substring(0, 24)}';

/// Тело события по formats.md.
String webhookBody({
  required WebhookEvent type,
  required String eventId,
  required DateTime at,
  required Map<String, Object?> data,
}) =>
    jsonEncode({
      'v': kCommandFormatVersion,
      'id': eventId,
      'type': type.wire,
      'createdAt': _isoWithOffset(at),
      'data': data,
    });

String _isoWithOffset(DateTime t) {
  // UTC уже несёт «Z» — второе смещение сломало бы дату.
  if (t.isUtc) return t.toIso8601String();
  final o = t.timeZoneOffset;
  final sign = o.isNegative ? '-' : '+';
  final h = o.inHours.abs().toString().padLeft(2, '0');
  final m = (o.inMinutes.abs() % 60).toString().padLeft(2, '0');
  return '${t.toIso8601String()}$sign$h:$m';
}

/// Подпись: HMAC-SHA256(secret, timestamp + "." + body) в hex.
String webhookSignature(String secret, int timestamp, String body) =>
    'sha256=${Hmac(sha256, utf8.encode(secret)).convert(utf8.encode('$timestamp.$body'))}';

/// «День закрыт» — тем же правилом, что в приложении: все задачи дня, кроме
/// перенесённых оригиналов, выполнены.
Map<String, Object?>? dayClosedData(DateTime day, List<Task> tasks) {
  final relevant = tasks.where((t) => !t.isTransferred).toList();
  if (relevant.isEmpty || relevant.any((t) => !t.isCompleted)) return null;
  return {
    'date': formatYmd(day),
    'done': relevant.length,
    'total': relevant.length,
    'productivity': 100,
  };
}

Map<String, Object?> goalToWire(Goal g) => {
      'id': g.id,
      'title': g.title,
      'period': g.period.name,
      if (g.targetCount != null) 'target': g.targetCount,
      'progress': g.progressCount,
      if (g.isTime) 'unit': 'minutes',
    };

/// Очередь, отправка, повторы. Работает, пока приложение открыто; при
/// открытии досылает накопленное.
class WebhookService {
  WebhookService(
    this._ref, {
    http.Client Function()? client,
    DateTime Function()? clock,
  })  : _client = client ?? http.Client.new,
        _clock = clock ?? DateTime.now;

  final Ref _ref;
  final http.Client Function() _client;
  final DateTime Function() _clock;
  Timer? _timer;
  Future<void>? _processing;
  bool _again = false;

  /// Вызывается при 410: адрес отключён — показать уведомление.
  void Function(WebhookEndpoint)? onGone;

  LocalStorage get _storage => _ref.read(localStorageProvider);

  /// Экраны перечитывают адреса и журнал после каждой записи.
  void _bump() => _ref.read(webhookRevisionProvider.notifier).state++;

  List<WebhookEndpoint> get endpoints => [
        for (final j in _storage.readList(kWebhookEndpointsKey))
          WebhookEndpoint.fromJson(j),
      ];

  Future<void> saveEndpoints(List<WebhookEndpoint> list) async {
    await _storage.writeList(
      kWebhookEndpointsKey,
      [for (final e in list) e.toJson()],
    );
    // Доставки удалённых адресов слать некуда: иначе их ошибки навсегда
    // остаются пометкой «не доставлено» на строке «Интеграции».
    final ids = {for (final e in list) e.id};
    final queue = deliveries;
    if (queue.any((d) => !ids.contains(d.endpointId))) {
      await _saveDeliveries([
        for (final d in queue)
          if (ids.contains(d.endpointId)) d,
      ]);
    } else {
      _bump();
    }
  }

  List<WebhookDelivery> get deliveries => [
        for (final j in _storage.readList(kWebhookQueueKey))
          if (WebhookDelivery.fromJson(j) case final d?) d,
      ];

  Future<void> _saveDeliveries(List<WebhookDelivery> list) async {
    await _storage.writeList(
      kWebhookQueueKey,
      [for (final d in list) d.toJson()],
    );
    _bump();
  }

  /// Сколько дней хранить журнал доставленного: 7 (по умолчанию) или 30.
  int get retentionDays =>
      (_storage.readMap(kWebhookSettingsKey)?['retentionDays'] as int?) ?? 7;

  Future<void> setRetentionDays(int days) async {
    await _storage.writeMap(kWebhookSettingsKey, {'retentionDays': days});
    _bump();
  }

  /// Ставит событие в очередь каждому включённому адресу, который его ждёт.
  /// Одно и то же событие одному адресу дважды не ставится.
  Future<void> enqueue(
    WebhookEvent type,
    String recordId,
    Map<String, Object?> data, {
    String? onlyEndpoint,
  }) async {
    final now = _clock();
    final eventId = type == WebhookEvent.ping
        // Каждая проверка — новая: её id не должен совпасть с прошлой.
        ? 'evt_ping_${_randomId()}'
        : webhookEventId(recordId, type);
    final body = webhookBody(type: type, eventId: eventId, at: now, data: data);
    final list = deliveries;
    for (final e in endpoints) {
      if (onlyEndpoint != null && e.id != onlyEndpoint) continue;
      if (!e.enabled || (type != WebhookEvent.ping && !e.events.contains(type))) {
        continue;
      }
      if (list.any((d) => d.endpointId == e.id && d.eventId == eventId)) {
        continue;
      }
      list.add(
        WebhookDelivery(
          id: _randomId(),
          endpointId: e.id,
          eventId: eventId,
          type: type,
          body: body,
          createdAt: now,
          nextAt: now,
        ),
      );
    }
    await _saveDeliveries(_trim(list, now));
    await process();
  }

  /// Потолок очереди и срок хранения журнала.
  List<WebhookDelivery> _trim(List<WebhookDelivery> list, DateTime now) {
    final keepFrom = now.subtract(Duration(days: retentionDays));
    final kept = list
        .where(
          (d) =>
              d.status == DeliveryStatus.pending ||
              d.createdAt.isAfter(keepFrom),
        )
        .toList();
    return kept.length > kWebhookQueueLimit
        ? kept.sublist(kept.length - kWebhookQueueLimit)
        : kept;
  }

  /// Отправляет всё, чему пришло время, и заводит таймер на следующее.
  /// Вызов во время отправки не теряется: отправка пройдёт ещё круг, и
  /// вызвавший дождётся его.
  Future<void> process() {
    if (_processing != null) {
      _again = true;
      return _processing!;
    }
    return _processing = () async {
      try {
        do {
          _again = false;
          await _processOnce();
        } while (_again);
      } finally {
        _processing = null;
      }
    }();
  }

  Future<void> _processOnce() async {
    final now = _clock();
    final eps = {for (final e in endpoints) e.id: e};
    for (final d in deliveries) {
      if (d.status != DeliveryStatus.pending || d.nextAt.isAfter(now)) continue;
      final ep = eps[d.endpointId];
      if (ep == null || !ep.enabled) {
        await _update(d.id, d.copyWith(status: DeliveryStatus.failed));
        continue;
      }
      final earlyFrom = _early.remove(d.id);
      final code = await _post(ep, d);
      final attempts = d.attempts + 1;
      final WebhookDelivery next;
      if (code == 0 && earlyFrom != null) {
        // Досрочная попытка ([retryNow]), а сети всё нет — в счёт попыток
        // не идёт, расписание прежнее.
        next = d.copyWith(nextAt: earlyFrom);
      } else if (code >= 200 && code < 300) {
        next = d.copyWith(
          status: DeliveryStatus.delivered,
          attempts: attempts,
          lastCode: code,
        );
      } else if (code == 410) {
        next = d.copyWith(
          status: DeliveryStatus.failed,
          attempts: attempts,
          lastCode: code,
        );
        final off = ep.copyWith(enabled: false);
        eps[ep.id] = off;
        await saveEndpoints([
          for (final e in endpoints) e.id == ep.id ? off : e,
        ]);
        onGone?.call(off);
      } else if (attempts > kWebhookRetryDelays.length) {
        next = d.copyWith(
          status: DeliveryStatus.failed,
          attempts: attempts,
          lastCode: code,
        );
      } else {
        next = d.copyWith(
          attempts: attempts,
          lastCode: code,
          nextAt: now.add(kWebhookRetryDelays[attempts - 1]),
        );
      }
      await _update(d.id, next);
    }
    final list = _trim(deliveries, now);
    await _saveDeliveries(list);
    _scheduleNext(list, now);
  }

  /// Итог одной доставки — в очередь, какой она стала сейчас: пока шла
  /// отправка, в неё могли добавить события (их нельзя затереть старым
  /// снимком).
  Future<void> _update(String id, WebhookDelivery next) => _saveDeliveries([
        for (final x in deliveries) x.id == id ? next : x,
      ]);

  void _scheduleNext(List<WebhookDelivery> list, DateTime now) {
    _timer?.cancel();
    final pending = list.where((d) => d.status == DeliveryStatus.pending);
    if (pending.isEmpty) return;
    final next = pending.map((d) => d.nextAt).reduce((a, b) => a.isBefore(b) ? a : b);
    final wait = next.isAfter(now) ? next.difference(now) : Duration.zero;
    _timer = Timer(wait, () => unawaited(process()));
  }

  /// Код ответа; 0 — ответа не было (сеть, таймаут, неверный адрес).
  Future<int> _post(WebhookEndpoint ep, WebhookDelivery d) async {
    final client = _client();
    try {
      final secret = await _ref.read(secretStoreProvider).webhookSecret(ep.id);
      final ts = _clock().millisecondsSinceEpoch ~/ 1000;
      final r = await client
          .post(
            Uri.parse(ep.url),
            headers: {
              'Content-Type': 'application/json',
              'User-Agent': 'Enitor',
              'X-Enitor-Event': d.type.wire,
              'X-Enitor-Delivery': d.id,
              'X-Enitor-Timestamp': '$ts',
              'X-Enitor-Signature': webhookSignature(secret, ts, d.body),
            },
            body: utf8.encode(d.body),
          )
          .timeout(kWebhookTimeout);
      return r.statusCode;
    } catch (e) {
      debugPrint('webhook ${ep.id}: $e');
      return 0;
    } finally {
      client.close();
    }
  }

  /// Досрочные попытки: id доставки → когда она стояла по расписанию.
  final _early = <String, DateTime>{};

  /// Вернулись в приложение — сеть могла появиться (выключили авиарежим):
  /// что не ушло из-за сети, шлём сейчас, а не через полчаса по расписанию.
  Future<void> retryNow() async {
    final now = _clock();
    final list = <WebhookDelivery>[];
    for (final d in deliveries) {
      if (d.status == DeliveryStatus.pending &&
          d.lastCode == 0 &&
          d.nextAt.isAfter(now)) {
        _early[d.id] = d.nextAt;
        list.add(d.copyWith(nextAt: now));
      } else {
        list.add(d);
      }
    }
    if (_early.isEmpty) return;
    await _saveDeliveries(list);
    await process();
  }

  /// «Отправить ещё раз» из журнала: новая серия попыток.
  Future<void> resend(String deliveryId) async {
    final now = _clock();
    await _saveDeliveries([
      for (final d in deliveries)
        d.id == deliveryId
            ? WebhookDelivery(
                id: _randomId(),
                endpointId: d.endpointId,
                eventId: d.eventId,
                type: d.type,
                body: d.body,
                createdAt: now,
                nextAt: now,
              )
            : d,
    ]);
    await process();
  }

  Future<void> clearLog() async => _saveDeliveries([
        for (final d in deliveries)
          if (d.status == DeliveryStatus.pending) d,
      ]);

  /// «Проверить»: событие ping сразу на один адрес. true — доставлено.
  Future<bool> test(String endpointId) async {
    await enqueue(WebhookEvent.ping, 'ping', const {}, onlyEndpoint: endpointId);
    final last = deliveries
        .where((d) => d.endpointId == endpointId && d.type == WebhookEvent.ping)
        .lastOrNull;
    return last?.status == DeliveryStatus.delivered;
  }

  /// Подписка на действия пользователя на этом устройстве. Изменения
  /// хранилища вообще (перенос, повторы, будущая синхронизация) событий не
  /// дают — только то, что человек сделал здесь.
  List<StreamSubscription<Object?>> listen() {
    final tasks = _ref.read(taskRepositoryProvider);
    final goals = _ref.read(goalRepositoryProvider);
    return [
      tasks.completedEvents.listen((t) async {
        await enqueue(
          WebhookEvent.taskCompleted,
          t.id,
          {'task': taskToWire(t)},
        );
        final day = dayClosedData(t.date, tasks.tasksForDay(t.date));
        if (day != null) {
          await enqueue(WebhookEvent.dayClosed, formatYmd(t.date), day);
        }
      }),
      goals.achievedEvents.listen(
        (g) => enqueue(
          WebhookEvent.goalAchieved,
          g.id,
          {'goal': goalToWire(g)},
        ),
      ),
    ];
  }

  void dispose() => _timer?.cancel();

  static final _rnd = Random.secure();
  static String _randomId() =>
      List.generate(16, (_) => _rnd.nextInt(256).toRadixString(16).padLeft(2, '0'))
          .join();
}

final webhookServiceProvider = Provider<WebhookService>((ref) {
  final s = WebhookService(ref);
  ref.onDispose(s.dispose);
  return s;
});

/// Номер записи: растёт после каждого изменения адресов или очереди.
final webhookRevisionProvider = StateProvider<int>((ref) => 0);

final webhookEndpointsProvider = Provider<List<WebhookEndpoint>>((ref) {
  ref.watch(webhookRevisionProvider);
  return ref.watch(webhookServiceProvider).endpoints;
});

final webhookDeliveriesProvider = Provider<List<WebhookDelivery>>((ref) {
  ref.watch(webhookRevisionProvider);
  return ref.watch(webhookServiceProvider).deliveries;
});

/// Есть недоставленные — для спокойной пометки на строке «Интеграции».
/// Доставки удалённых адресов не в счёт: их журнал не виден, и снять пометку
/// было бы нечем (остались от версий, где удаление их не уносило).
final webhookFailedProvider = Provider<bool>((ref) {
  final ids = {for (final e in ref.watch(webhookEndpointsProvider)) e.id};
  return ref.watch(webhookDeliveriesProvider).any(
        (d) =>
            d.status == DeliveryStatus.failed &&
            d.lastCode != 410 &&
            ids.contains(d.endpointId),
      );
});
