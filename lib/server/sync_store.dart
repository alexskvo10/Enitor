import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../features/integrations/sync/sync_collections.dart';

// Чистый Dart: хранилище `enitor-server`. Логика протокола — здесь, HTTP —
// в server_app.dart.

/// Пометки удалённых записей старше этого срока стираются при загрузке.
/// Устройство, молчавшее дольше, отправит правку удалённой записи — и она
/// вернётся. Это редкость и не потеря данных.
const kTombstoneTtl = Duration(days: 90);

class ServerRecord {
  ServerRecord({
    required this.coll,
    required this.id,
    required this.rev,
    required this.at,
    this.data,
  });

  final String coll;
  final String id;
  final int rev;

  /// Время сервера, когда запись получила эту ревизию.
  final DateTime at;

  /// null — запись удалена (пометка).
  final Map<String, dynamic>? data;

  bool get deleted => data == null;

  Map<String, dynamic> toWire() => {
        'coll': coll,
        'id': id,
        'rev': rev,
        if (deleted) 'deleted': true else 'data': data,
      };
}

/// Ошибка запроса к хранилищу: уходит клиенту как `{ok:false, error}`.
class StoreError implements Exception {
  const StoreError(this.status, this.code, this.message, {this.field});

  final int status;
  final String code;
  final String message;
  final String? field;

  Map<String, dynamic> toJson() => {
        'code': code,
        'message': message,
        if (field != null) 'field': field,
      };

  @override
  String toString() => '$code: $message';
}

/// Все записи пользователя с ревизиями. Одна ревизия — один счётчик на весь
/// сервер, поэтому «что изменилось после N» — простой отбор.
class SyncStore {
  SyncStore._(this._file);

  /// В памяти, без файла (тесты).
  SyncStore.memory() : _file = null;

  final File? _file;
  int _rev = 0;

  /// Метка этого экземпляра хранилища. Создали заново (восстановление
  /// бэкапа, битый файл) — метка новая, и устройства, чей курсор от прежнего,
  /// забирают всё с начала, а не «после N» по чужому счётчику.
  String _epoch = _newEpoch();
  String get epoch => _epoch;

  static String _newEpoch() {
    final r = Random.secure();
    return [
      for (var i = 0; i < 8; i++) r.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ].join();
  }

  Future<void> _saving = Future.value();
  final _records = <String, Map<String, ServerRecord>>{};

  /// Устройство → адрес UnifiedPush.
  final _push = <String, String>{};

  /// Устройство → {name, seen}: кто подключён и когда последний раз
  /// приходил обмен (`seen` — UTC, ISO 8601).
  final _devices = <String, Map<String, String>>{};
  final _changes = StreamController<int>.broadcast();

  int get rev => _rev;

  /// Новая ревизия после каждой принятой правки (SSE и push).
  Stream<int> get changes => _changes.stream;

  Map<String, String> get pushEndpoints => Map.unmodifiable(_push);

  /// Подключённые устройства, недавние первыми.
  List<Map<String, dynamic>> get devices => [
        for (final e in _devices.entries)
          {
            'id': e.key,
            'name': e.value['name'],
            'lastSeen': e.value['seen'],
            'push': _push.containsKey(e.key),
          },
      ]..sort(
          (a, b) =>
              (b['lastSeen'] as String).compareTo(a['lastSeen'] as String),
        );

  static Future<SyncStore> open(File file) async {
    final s = SyncStore._(file);
    if (await file.exists()) {
      // Файл без метки — от прежней версии: сразу сохранить новую, иначе
      // каждый перезапуск давал бы новую и устройства тянули бы всё заново.
      if (!s._load(jsonDecode(await file.readAsString()))) await s._save();
    }
    return s;
  }

  /// false — в файле не было метки.
  bool _load(Object? raw) {
    if (raw is! Map) return false;
    _rev = raw['rev'] as int? ?? 0;
    final epoch = raw['epoch'];
    if (epoch is String && epoch.isNotEmpty) _epoch = epoch;
    final cutoff = DateTime.now().subtract(kTombstoneTtl);
    final recs = raw['records'] as Map? ?? const {};
    recs.forEach((coll, m) {
      final out = _records[coll as String] = {};
      (m as Map).forEach((id, r) {
        final rec = ServerRecord(
          coll: coll,
          id: id as String,
          rev: (r as Map)['rev'] as int,
          at: DateTime.parse(r['at'] as String),
          data: (r['data'] as Map?)?.cast<String, dynamic>(),
        );
        if (rec.deleted && rec.at.isBefore(cutoff)) return;
        out[id] = rec;
      });
    });
    (raw['push'] as Map? ?? const {})
        .forEach((k, v) => _push[k as String] = v as String);
    (raw['devices'] as Map? ?? const {}).forEach(
      (k, v) => _devices[k as String] = (v as Map).cast<String, String>(),
    );
    return epoch is String && epoch.isNotEmpty;
  }

  /// Сохранения по очереди: два обмена сразу писали бы один временный файл.
  Future<void> _save() {
    final next = _saving.then((_) => _write());
    _saving = next.then((_) {}, onError: (_) {});
    return next;
  }

  Future<void> _write() async {
    final f = _file;
    if (f == null) return;
    final json = jsonEncode({
      'rev': _rev,
      'epoch': _epoch,
      'records': {
        for (final e in _records.entries)
          e.key: {
            for (final r in e.value.values)
              r.id: {
                'rev': r.rev,
                'at': r.at.toIso8601String(),
                if (!r.deleted) 'data': r.data,
              },
          },
      },
      'push': _push,
      'devices': _devices,
    });
    // Через временный файл: оборванная запись не испортит данные.
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(json, flush: true);
    await tmp.rename(f.path);
  }

  // Записи с одинаковым временем сохраняют порядок: запись, затем событие.
  Future<void> _commit() async {
    await _save();
    _changes.add(_rev);
  }

  ServerRecord _put(String coll, String id, Map<String, dynamic>? data) {
    final rec = ServerRecord(
      coll: coll,
      id: id,
      rev: ++_rev,
      at: DateTime.now(),
      data: data,
    );
    (_records[coll] ??= {})[id] = rec;
    return rec;
  }

  // ── Синхронизация (POST /v1/sync) ─────────────────────────────────────────

  /// Принять правки устройства и вернуть чужие. Правило конфликта: правка
  /// записи, о которой устройство уже знало (`baseRev` > 0), побеждает —
  /// она дошла позже. Создание (`baseRev` = 0) поверх существующей или
  /// удалённой записи отвергается: значит, два устройства независимо
  /// создали одно и то же (экземпляр повтора) или запись уже удалили.
  ///
  /// Курсор от другого экземпляра хранилища (`epoch` не тот) считается
  /// нулём: отдаём всё.
  Future<Map<String, dynamic>> sync(Map<String, dynamic> body) async {
    final sent = body['cursor'];
    final changes = body['changes'];
    if (sent is! int || changes is! List) {
      throw const StoreError(400, 'bad_request', 'cursor and changes required');
    }
    final epoch = body['epoch'];
    // Курсор впереди нашей ревизии — папку сервера восстановили из старой
    // копии (epoch в том же файле, его не сменить): тоже отдаём всё, иначе
    // устройство ждало бы ревизий, которые здесь уже никогда не наступят.
    final cursor = (epoch != null && epoch != _epoch) || sent > _rev ? 0 : sent;
    final newDevice = _seen(body['deviceId'], body['deviceName']);
    final applied = <Map<String, dynamic>>[];
    final mineRevs = <int>{};
    final rejected = <ServerRecord>[];
    final errors = <Map<String, dynamic>>[];
    for (final ch in changes) {
      if (ch is! Map) continue;
      final rawColl = ch['coll'];
      final coll = rawColl is String ? syncCollection(rawColl) : null;
      final id = ch['id'];
      if (coll == null || id is! String || id.isEmpty) {
        errors.add({'coll': rawColl, 'id': id, 'message': 'unknown record'});
        continue;
      }
      final cur = _records[coll.name]?[id];
      final rawBase = ch['baseRev'] ?? 0;
      if (rawBase is! int) {
        errors.add({'coll': coll.name, 'id': id, 'message': 'bad baseRev'});
        continue;
      }
      final baseRev = rawBase;
      if (baseRev == 0 && cur != null) {
        rejected.add(cur);
        continue;
      }
      final deleted = ch['deleted'] == true;
      if (!deleted) {
        final err = validateRecord(coll, ch['data']);
        if (err != null) {
          errors.add({'coll': coll.name, 'id': id, 'message': err});
          continue;
        }
      }
      final rec = _put(
        coll.name,
        id,
        deleted ? null : (ch['data'] as Map).cast<String, dynamic>(),
      );
      mineRevs.add(rec.rev);
      applied.add({'coll': coll.name, 'id': id, 'rev': rec.rev});
    }
    if (applied.isNotEmpty) {
      await _commit();
    } else if (newDevice) {
      await _save();
    }

    final out = <ServerRecord>[
      for (final m in _records.values)
        for (final r in m.values)
          if (r.rev > cursor && !mineRevs.contains(r.rev)) r,
    ];
    for (final r in rejected) {
      if (r.rev <= cursor) out.add(r);
    }
    out.sort((a, b) => a.rev.compareTo(b.rev));
    return {
      'cursor': _rev,
      'epoch': _epoch,
      'applied': applied,
      'changes': [for (final r in out) r.toWire()],
      if (errors.isNotEmpty) 'errors': errors,
    };
  }

  // ── Записи для REST ───────────────────────────────────────────────────────

  Map<String, dynamic>? get(String coll, String id) =>
      _records[coll]?[id]?.data;

  /// Живые записи коллекции.
  Iterable<Map<String, dynamic>> all(String coll) => [
        for (final r in (_records[coll] ?? const {}).values)
          if (!r.deleted) r.data!,
      ];

  /// Записать запись целиком (после проверки формата).
  Future<Map<String, dynamic>> put(
    String coll,
    String id,
    Map<String, dynamic> data,
  ) async {
    final c = syncCollection(coll)!;
    final err = validateRecord(c, data);
    if (err != null) throw StoreError(400, 'bad_record', err);
    _put(coll, id, data);
    await _commit();
    return data;
  }

  /// Записать несколько записей одной ревизией-пачкой (одно сохранение).
  Future<void> putAll(Map<(String, String), Map<String, dynamic>?> recs) async {
    for (final e in recs.entries) {
      final v = e.value;
      if (v != null) {
        final err = validateRecord(syncCollection(e.key.$1)!, v);
        if (err != null) throw StoreError(400, 'bad_record', err);
      }
    }
    for (final e in recs.entries) {
      _put(e.key.$1, e.key.$2, e.value);
    }
    if (recs.isNotEmpty) await _commit();
  }

  Future<bool> delete(String coll, String id) async {
    final cur = _records[coll]?[id];
    if (cur == null || cur.deleted) return false;
    _put(coll, id, null);
    await _commit();
    return true;
  }

  /// Отметить обмен устройства. true — устройство новое или сменило имя
  /// (стоит сохранить сразу); иначе время дойдёт до файла со следующей
  /// записью — не писать файл на каждый пустой обмен.
  bool _seen(Object? id, Object? name) {
    if (id is! String || id.isEmpty || id.length > 64) return false;
    var n = name is String ? name.trim() : '';
    if (n.length > 60) n = n.substring(0, 60);
    final changed = _devices[id]?['name'] != n;
    _devices[id] = {
      'name': n,
      'seen': DateTime.now().toUtc().toIso8601String(),
    };
    return changed;
  }

  /// Забыть устройство (и его адрес push). false — такого нет.
  Future<bool> forgetDevice(String id) async {
    final had = _devices.remove(id) != null;
    if (_push.remove(id) == null && !had) return false;
    await _save();
    return true;
  }

  Future<void> setPush(String deviceId, String? endpoint) async {
    if (endpoint == null) {
      _push.remove(deviceId);
    } else {
      _push[deviceId] = endpoint;
    }
    await _save();
  }

  Future<void> close() => _changes.close();
}
