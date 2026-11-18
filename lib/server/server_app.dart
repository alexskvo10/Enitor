import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../core/utils/date_utils.dart';
import '../data/models/goal.dart';
import '../data/models/recurrence_rule.dart';
import '../data/models/recurrence_task.dart';
import '../data/models/schedule_item.dart';
import '../data/models/task.dart';
import '../core/utils/secrets.dart';
import 'sync_store.dart';

// Чистый Dart: HTTP-часть `enitor-server` (протокол — docs/integrations/server.md).

const kServerVersion = 1;
const _uuid = Uuid();

/// Сколько дней можно запросить в `/v1/days` за раз.
const kMaxDaysRange = 62;

/// Пауза перед сигналом UnifiedPush: пачка правок — один сигнал.
const kPushDebounce = Duration(seconds: 1);

class EnitorServer {
  EnitorServer(
    this.store, {
    required this.token,
    this.webPage,
    http.Client? pushClient,
    DateTime Function()? clock,
  })  : _push = pushClient ?? http.Client(),
        _clock = clock ?? DateTime.now {
    _sub = store.changes.listen((_) {
      _pushTimer?.cancel();
      _pushTimer = Timer(kPushDebounce, () => unawaited(_sendPush()));
    });
  }

  final SyncStore store;
  final String token;

  /// Страница `/`; null — не отдаётся.
  final String? webPage;
  final http.Client _push;
  final DateTime Function() _clock;
  late final StreamSubscription<int> _sub;
  Timer? _pushTimer;

  Future<void> close() async {
    _pushTimer?.cancel();
    await _sub.cancel();
    _push.close();
  }

  // ── Вход ──────────────────────────────────────────────────────────────────

  Future<void> handle(HttpRequest req) async {
    final res = req.response;
    // Страницы с других адресов (часы на планшете, панели) — по токену,
    // без cookie, поэтому «*» безопасен.
    res.headers
      ..set('Access-Control-Allow-Origin', '*')
      ..set('Access-Control-Allow-Headers', 'Authorization, Content-Type')
      ..set('Access-Control-Allow-Methods', 'GET, POST, PUT, PATCH, DELETE');
    try {
      if (req.method == 'OPTIONS') {
        res.statusCode = 204;
        return await res.close();
      }
      final path = req.uri.path;
      if (path == '/' || path == '/index.html') {
        if (webPage == null) {
          throw const StoreError(404, 'not_found', 'No page');
        }
        res.headers.contentType = ContentType.html;
        res.write(webPage);
        return await res.close();
      }
      if (!path.startsWith('/v1/')) {
        throw const StoreError(404, 'not_found', 'Unknown path');
      }
      final auth = req.headers.value('authorization') ?? '';
      final given = auth.startsWith('Bearer ') ? auth.substring(7).trim() : '';
      if (given.isEmpty || !constantTimeEquals(given, token)) {
        throw const StoreError(401, 'unauthorized', 'Wrong or missing token');
      }
      if (path == '/v1/events' && req.method == 'GET') {
        return await _events(req);
      }
      final body = await _readBody(req);
      final result = await _route(req.method, req.uri, body);
      _send(res, 200, {'ok': true, 'result': result});
    } on StoreError catch (e) {
      _send(res, e.status, {'ok': false, 'error': e.toJson()});
    } catch (e) {
      _send(res, 500, {
        'ok': false,
        'error': {'code': 'internal', 'message': '$e'},
      });
    }
    await res.close();
  }

  void _send(HttpResponse res, int status, Map<String, dynamic> json) {
    res
      ..statusCode = status
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(json));
  }

  Future<Map<String, dynamic>> _readBody(HttpRequest req) async {
    final String text;
    try {
      text = await utf8.decoder.bind(req).join();
    } on FormatException {
      throw const StoreError(400, 'bad_json', 'Body is not UTF-8');
    }
    if (text.trim().isEmpty) return {};
    final Object? j;
    try {
      j = jsonDecode(text);
    } catch (_) {
      throw const StoreError(400, 'bad_json', 'Body is not JSON');
    }
    if (j is! Map<String, dynamic>) {
      throw const StoreError(400, 'bad_json', 'Body must be a JSON object');
    }
    return j;
  }

  Future<Object?> _route(
    String method,
    Uri uri,
    Map<String, dynamic> body,
  ) async {
    final seg = uri.pathSegments.skip(1).toList(); // без «v1»
    final q = uri.queryParameters;
    final key = '$method ${seg.isEmpty ? '' : seg.first}';
    switch ((key, seg.length)) {
      case ('GET ping', 1):
        return {
          'server': 'enitor-server',
          'version': kServerVersion,
          'rev': store.rev,
        };
      case ('POST sync', 1):
        return store.sync(body);
      case ('GET devices', 1):
        return {'devices': store.devices};
      case ('DELETE devices', 2):
        if (!await store.forgetDevice(seg[1])) throw _notFound(seg[1]);
        return {};
      case ('PUT devices', 3) when seg[2] == 'push':
        final ep = body['endpoint'];
        if (ep != null &&
            (ep is! String || Uri.tryParse(ep)?.hasScheme != true)) {
          throw const StoreError(
            400,
            'bad_args',
            'endpoint must be a URL',
            field: 'endpoint',
          );
        }
        await store.setPush(seg[1], ep as String?);
        return {};
      case ('GET days', 2):
        return _day(_parseDay(seg[1], 'date'));
      case ('GET days', 1):
        final from = _parseDay(q['from'], 'from');
        final to = _parseDay(q['to'] ?? q['from'], 'to');
        final n = to.difference(from).inDays;
        if (n < 0 || n >= kMaxDaysRange) {
          throw const StoreError(
            400,
            'bad_args',
            'to must be within $kMaxDaysRange days after from',
            field: 'to',
          );
        }
        return [
          for (var i = 0; i <= n; i++)
            _day(DateTime(from.year, from.month, from.day + i)),
        ];
      case ('GET tasks', 1):
        return _listByDate('tasks', q);
      case ('GET goals', 1):
        return _listGoals(q);
      case ('GET schedule', 1):
        return store.all('schedule').toList();
      case ('GET tasks' || 'GET goals' || 'GET schedule', 2):
        return _getOr404(seg.first, seg[1]);
      case ('POST tasks', 1):
        return _createTask(body);
      case ('POST goals', 1):
        return _createGoal(body);
      case ('POST schedule', 1):
        return _createSchedule(body);
      case ('PATCH tasks', 2):
        return _patchTask(seg[1], body);
      case ('PATCH goals', 2):
        return _patch('goals', seg[1], body);
      case ('PATCH schedule', 2):
        return _patchSchedule(seg[1], body, q);
      case ('POST tasks', 3)
          when seg[2] == 'complete' || seg[2] == 'uncomplete':
        return _patchTask(seg[1], {'done': seg[2] == 'complete'});
      case ('POST goals', 3)
          when seg[2] == 'complete' || seg[2] == 'uncomplete':
        return _patch('goals', seg[1], {'done': seg[2] == 'complete'});
      case ('POST goals', 3) when seg[2] == 'progress':
        return _patch('goals', seg[1], {'progress': body['value']});
      case ('DELETE tasks', 2):
        return _deleteTask(seg[1]);
      case ('DELETE goals', 2):
        if (!await store.delete('goals', seg[1])) throw _notFound(seg[1]);
        return {};
      case ('DELETE schedule', 2):
        return _deleteSchedule(seg[1], q);
    }
    throw const StoreError(404, 'not_found', 'Unknown method or path');
  }

  // ── Дни ───────────────────────────────────────────────────────────────────

  /// День целиком: задачи (с ещё не созданными экземплярами повторов —
  /// `virtual: true`, их id те же, что создадут устройства), расписание,
  /// цели периодов, в которые попадает день.
  Map<String, dynamic> _day(DateTime d) {
    final tasks = [
      for (final t in store.all('tasks'))
        if (_sameDay(t['date'], d)) t,
    ];
    final materialized = {for (final t in tasks) t['recurrenceRuleId']};
    var order = tasks.length;
    for (final r in store.all('recurrence')) {
      final rule = RecurrenceRule.fromJson(r);
      if (materialized.contains(rule.id) || !rule.occursOn(d)) continue;
      tasks.add({
        ...taskFromRule(rule, d, order: order++, now: _clock()).toJson(),
        'virtual': true,
      });
    }
    final items = store.all('schedule').map(ScheduleItem.fromJson);
    final goals = [
      for (final g in store.all('goals'))
        if (_goalCovers(Goal.fromJson(g), d)) g,
    ];
    return {
      'date': _ymd(d),
      'tasks': tasks,
      'schedule': [for (final i in scheduleForDay(items, d)) i.toJson()],
      'goals': goals,
      'stats': store.get('dayStats', d.toIso8601String()),
      'rating': store.get('dayRatings', d.toIso8601String())?['value'],
    };
  }

  bool _goalCovers(Goal g, DateTime d) =>
      !d.isBefore(g.ref.start) && !d.isAfter(g.ref.endInclusive);

  List<Map<String, dynamic>> _listByDate(String coll, Map<String, String> q) {
    final from = q['from'] == null ? null : _parseDay(q['from'], 'from');
    final to = q['to'] == null ? null : _parseDay(q['to'], 'to');
    return [
      for (final r in store.all(coll))
        if (_inRange(DateTime.parse(r['date'] as String), from, to)) r,
    ];
  }

  List<Map<String, dynamic>> _listGoals(Map<String, String> q) {
    final on = q['date'] == null ? null : _parseDay(q['date'], 'date');
    final period = q['period'];
    return [
      for (final r in store.all('goals'))
        if ((period == null || r['period'] == period) &&
            (on == null || _goalCovers(Goal.fromJson(r), on)))
          r,
    ];
  }

  bool _inRange(DateTime d, DateTime? from, DateTime? to) {
    final day = dateOnly(d);
    return (from == null || !day.isBefore(from)) &&
        (to == null || !day.isAfter(to));
  }

  // ── Задачи ────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _createTask(Map<String, dynamic> body) async {
    final date = body.containsKey('date')
        ? _parseDay(body['date'], 'date')
        : effectiveDay(_clock());
    final now = _clock();
    final id = _uuid.v4();
    final base = Task(
      id: id,
      title: _title(body),
      date: date,
      order: store.all('tasks').where((t) => _sameDay(t['date'], date)).length,
      createdAt: now,
      updatedAt: now,
    ).toJson();
    final rec =
        _normalize('tasks', _apply('tasks', base, body..remove('date')));
    return store.put('tasks', id, rec);
  }

  /// Задача по id; экземпляр повтора, которого ещё нет, создаётся.
  Map<String, dynamic> _taskOrVirtual(String id) {
    final cur = store.get('tasks', id);
    if (cur != null) return cur;
    final v = _parseVirtual(id);
    if (v == null) throw _notFound(id);
    final (rule, day) = v;
    final order =
        store.all('tasks').where((t) => _sameDay(t['date'], day)).length;
    return taskFromRule(rule, day, order: order, now: _clock()).toJson();
  }

  /// `r-<правило>-<yyyymmdd>` → правило и день, если правило на этот день есть
  /// и экземпляра ещё нет.
  (RecurrenceRule, DateTime)? _parseVirtual(String id) {
    final m = RegExp(r'^r-(.+)-(\d{4})(\d{2})(\d{2})$').firstMatch(id);
    if (m == null) return null;
    final raw = store.get('recurrence', m[1]!);
    if (raw == null) return null;
    final rule = RecurrenceRule.fromJson(raw);
    final day = DateTime(int.parse(m[2]!), int.parse(m[3]!), int.parse(m[4]!));
    if (!rule.occursOn(day)) return null;
    final exists = store.all('tasks').any(
          (t) => t['recurrenceRuleId'] == rule.id && _sameDay(t['date'], day),
        );
    return exists ? null : (rule, day);
  }

  Future<Map<String, dynamic>> _patchTask(
    String id,
    Map<String, dynamic> body,
  ) async {
    final cur = _taskOrVirtual(id);
    final rec = _normalize('tasks', _apply('tasks', cur, body));
    return store.put('tasks', id, rec);
  }

  /// Удаление как в приложении: день экземпляра повтора уходит в исключения
  /// правила, иначе устройства создали бы его снова.
  Future<Map<String, dynamic>> _deleteTask(String id) async {
    final cur = store.get('tasks', id);
    final virtual = cur == null ? _parseVirtual(id) : null;
    if (cur == null && virtual == null) throw _notFound(id);
    final ruleId = cur?['recurrenceRuleId'] as String? ?? virtual?.$1.id;
    final batch = <(String, String), Map<String, dynamic>?>{};
    if (cur != null) batch[('tasks', id)] = null;
    if (ruleId != null) {
      final raw = store.get('recurrence', ruleId);
      if (raw != null) {
        final rule = RecurrenceRule.fromJson(raw);
        final day =
            virtual?.$2 ?? dateOnly(DateTime.parse(cur!['date'] as String));
        if (!rule.exceptDates.any((d) => dateOnly(d) == day)) {
          batch[('recurrence', ruleId)] = rule.copyWith(
            exceptDates: [...rule.exceptDates, day],
            updatedAt: _clock(),
          ).toJson();
        }
      }
    }
    await store.putAll(batch);
    return {};
  }

  // ── Цели ──────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _createGoal(Map<String, dynamic> body) async {
    final periodName = body.remove('period') ?? 'month';
    final period =
        GoalPeriod.values.where((p) => p.name == periodName).firstOrNull;
    if (period == null) {
      throw const StoreError(
        400,
        'bad_args',
        'period must be week, month, season or year',
        field: 'period',
      );
    }
    final on = body.containsKey('date')
        ? _parseDay(body.remove('date'), 'date')
        : effectiveDay(_clock());
    final ref = GoalPeriodRef.current(period, on);
    final now = _clock();
    final id = _uuid.v4();
    final base = Goal(
      id: id,
      period: period,
      year: ref.year,
      month: ref.month,
      season: ref.season,
      weekStart: ref.weekStart,
      title: _title(body),
      createdAt: now,
      updatedAt: now,
    ).toJson();
    return store.put(
      'goals',
      id,
      _normalize('goals', _apply('goals', base, body)),
    );
  }

  // ── Расписание ────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _createSchedule(
    Map<String, dynamic> body,
  ) async {
    final date = _parseDay(body.remove('date'), 'date');
    final start = _parseHm(body.remove('start'), 'start');
    if (start == null) {
      throw const StoreError(
        400,
        'bad_args',
        'start is required',
        field: 'start',
      );
    }
    final now = _clock();
    final id = _uuid.v4();
    final base = ScheduleItem(
      id: id,
      title: _title(body),
      date: date,
      startMinutes: start,
      createdAt: now,
      updatedAt: now,
    ).toJson();
    return store.put(
      'schedule',
      id,
      _normalize('schedule', _apply('schedule', base, body)),
    );
  }

  /// `scope=day&date=` — как «только этот день» в приложении: день уходит в
  /// исключения серии, а на него создаётся разовый пункт с правками.
  Future<Map<String, dynamic>> _patchSchedule(
    String id,
    Map<String, dynamic> body,
    Map<String, String> q,
  ) async {
    if (q['scope'] != 'day') return _patch('schedule', id, body);
    final cur = _getOr404('schedule', id);
    final item = ScheduleItem.fromJson(cur);
    final day = _parseDay(q['date'], 'date');
    if (!item.isSeries) return _patch('schedule', id, body);
    if (!item.occursOn(day)) throw _notFound('$id@${_ymd(day)}');
    final now = _clock();
    final copyId = _uuid.v4();
    final one = {
      ...cur,
      'id': copyId,
      'date': day.toIso8601String(),
      'repeat': null,
      'weekdays': <int>[],
      'monthDays': <int>[],
      'endDate': null,
      'exceptDates': <String>[],
      'createdAt': now.toIso8601String(),
    };
    final edited = _normalize('schedule', _apply('schedule', one, body));
    await store.putAll({
      ('schedule', id): item.copyWith(
        exceptDates: [...item.exceptDates, day],
        updatedAt: now,
      ).toJson(),
      ('schedule', copyId): edited,
    });
    return edited;
  }

  Future<Map<String, dynamic>> _deleteSchedule(
    String id,
    Map<String, String> q,
  ) async {
    final cur = _getOr404('schedule', id);
    final item = ScheduleItem.fromJson(cur);
    if (q['scope'] == 'day' && item.isSeries) {
      final day = _parseDay(q['date'], 'date');
      await store.put(
        'schedule',
        id,
        item.copyWith(
          exceptDates: [...item.exceptDates, day],
          updatedAt: _clock(),
        ).toJson(),
      );
      return {};
    }
    await store.delete('schedule', id);
    return {};
  }

  // ── Общее ─────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _patch(
    String coll,
    String id,
    Map<String, dynamic> body,
  ) async {
    final cur = _getOr404(coll, id);
    return store.put(coll, id, _normalize(coll, _apply(coll, cur, body)));
  }

  Map<String, dynamic> _getOr404(String coll, String id) =>
      store.get(coll, id) ?? (throw _notFound(id));

  StoreError _notFound(String id) =>
      StoreError(404, 'not_found', 'No record $id');

  /// Правки поверх записи. Понятные поля переводятся в поля записи, прочие
  /// (имена из формата экспорта) записываются как есть. `id` не меняется.
  Map<String, dynamic> _apply(
    String coll,
    Map<String, dynamic> cur,
    Map<String, dynamic> body,
  ) {
    final out = {...cur};
    final now = _clock();
    for (final e in body.entries) {
      final v = e.value;
      switch (e.key) {
        case 'id' || 'createdAt' || 'virtual':
          break;
        case 'title':
          out['title'] = _title(body);
        case 'date':
          out['date'] = _parseDay(v, 'date').toIso8601String();
        case 'start' || 'end':
          out['${e.key}Minutes'] = _parseHm(v, e.key);
        case 'until':
          out['endDate'] =
              v == null ? null : _parseDay(v, 'until').toIso8601String();
        case 'priority':
          out['priority'] = _parsePriority(v);
        case 'done':
          if (v is! bool) {
            throw const StoreError(
              400,
              'bad_args',
              'done must be true or false',
              field: 'done',
            );
          }
          if (coll == 'goals') {
            out['completed'] = v;
            out['completedAt'] =
                v ? (out['completedAt'] ?? now.toIso8601String()) : null;
          } else {
            out['completedAt'] =
                v ? (out['completedAt'] ?? now.toIso8601String()) : null;
          }
        case 'progress':
          if (v is! int || v < 0) {
            throw const StoreError(
              400,
              'bad_args',
              'progress must be a non-negative integer',
              field: 'progress',
            );
          }
          if (coll == 'goals') {
            final linked = (out['linkedProgress'] as int? ?? 0) +
                (out['childProgress'] as int? ?? 0);
            final target = out['targetCount'] as int?;
            out['manualProgress'] = (v - linked).clamp(0, 1 << 30);
            if (target != null) {
              final reached = v >= target;
              out['completed'] = reached;
              out['completedAt'] = reached
                  ? (out['completedAt'] ?? now.toIso8601String())
                  : null;
            }
          } else {
            out['progressCount'] = v;
          }
        default:
          out[e.key] = v;
      }
    }
    out['updatedAt'] = now.toIso8601String();
    return out;
  }

  /// Через модель приложения: неверная запись — 400, а не сломанные
  /// устройства; поля приводятся к тому виду, что пишет приложение.
  Map<String, dynamic> _normalize(String coll, Map<String, dynamic> j) {
    try {
      return switch (coll) {
        'tasks' => Task.fromJson(j).toJson(),
        'goals' => Goal.fromJson(j).toJson(),
        'schedule' => _checkScheduleTimes(ScheduleItem.fromJson(j)).toJson(),
        _ => j,
      };
    } on StoreError {
      rethrow;
    } catch (e) {
      throw StoreError(400, 'bad_record', '$e');
    }
  }

  /// Как в приложении: конец пункта позже начала, через полночь нельзя.
  ScheduleItem _checkScheduleTimes(ScheduleItem i) {
    final end = i.endMinutes;
    if (end != null && end <= i.startMinutes) {
      throw const StoreError(
        400,
        'bad_args',
        'end must be later than start',
        field: 'end',
      );
    }
    return i;
  }

  String _title(Map<String, dynamic> body) {
    final t = body['title'];
    if (t is! String || t.trim().isEmpty) {
      throw const StoreError(
        400,
        'bad_args',
        'title is required',
        field: 'title',
      );
    }
    return t.trim();
  }

  // ── Поток событий ─────────────────────────────────────────────────────────

  Future<void> _events(HttpRequest req) async {
    final res = req.response
      ..bufferOutput = false
      ..headers.contentType =
          ContentType('text', 'event-stream', charset: 'utf-8')
      ..headers.set('Cache-Control', 'no-cache');
    void send(int rev) => res.write('event: changed\ndata: {"rev":$rev}\n\n');
    final done = Completer<void>();
    send(store.rev);
    final sub = store.changes.listen(send);
    // Комментарий раз в 25 с: прокси не закроют «молчащее» соединение.
    final beat = Timer.periodic(
      const Duration(seconds: 25),
      (_) => res.write(': ping\n\n'),
    );
    unawaited(
      res.done.catchError((_) {}).whenComplete(() {
        if (!done.isCompleted) done.complete();
      }),
    );
    await done.future;
    beat.cancel();
    await sub.cancel();
  }

  // ── UnifiedPush ───────────────────────────────────────────────────────────

  /// Пустой сигнал «есть новое» на адреса доставщиков. Данных в нём нет:
  /// доставщик (ntfy и т.п.) их не увидит.
  Future<void> _sendPush() async {
    final body = jsonEncode({'rev': store.rev});
    for (final e in store.pushEndpoints.entries) {
      try {
        final r = await _push
            .post(Uri.parse(e.value), body: body)
            .timeout(const Duration(seconds: 10));
        // 404/410 — устройство отписалось у доставщика.
        if (r.statusCode == 404 || r.statusCode == 410) {
          await store.setPush(e.key, null);
        }
      } catch (_) {}
    }
  }
}

// ── Разбор значений ─────────────────────────────────────────────────────────

DateTime _parseDay(Object? v, String field) {
  if (v is String) {
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(v);
    if (m != null) {
      final d = DateTime(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
      if (d.month == int.parse(m[2]!)) return d;
    }
  }
  throw StoreError(400, 'bad_args', '$field must be YYYY-MM-DD', field: field);
}

int? _parseHm(Object? v, String field) {
  if (v == null) return null;
  if (v is String) {
    final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(v.trim());
    if (m != null) {
      final h = int.parse(m[1]!), min = int.parse(m[2]!);
      if (h < 24 && min < 60) return h * 60 + min;
    }
  }
  throw StoreError(400, 'bad_args', '$field must be HH:MM', field: field);
}

int _parsePriority(Object? v) {
  if (v is int && v >= 0 && v < TaskPriority.values.length) return v;
  final p = TaskPriority.values.where((p) => p.name == v).firstOrNull;
  if (p != null) return p.index;
  throw const StoreError(
    400,
    'bad_args',
    'priority must be none, low, medium or high',
    field: 'priority',
  );
}

bool _sameDay(Object? iso, DateTime d) =>
    iso is String && dateOnly(DateTime.parse(iso)) == d;

String _ymd(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
