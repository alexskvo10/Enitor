import '../../../data/sources/local/local_storage.dart';
import 'sync_collections.dart';

/// Хэш и ревизия каждой записи на момент прошлого обмена.
/// Удалённая запись остаётся с хэшем null — так устройство помнит, что
/// сервер про неё знает, и новая запись с тем же id уйдёт правкой, а не
/// созданием (создание поверх чужого удаления сервер отвергает).
const kSyncBaseKey = 'device.sync.base';
const kSyncCursorKey = 'device.sync.cursor';

/// Дни, у которых после чужих правок задач нужно пересчитать статистику.
/// Отдельным ключом: фоновая синхронизация пишет его без репозиториев, а
/// приложение доделывает при следующем запуске.
const kSyncPendingDaysKey = 'device.sync.pendingDays';

/// Отправить запрос `/v1/sync` и вернуть его `result`.
typedef SyncTransport = Future<Map<String, dynamic>> Function(
  Map<String, dynamic> body,
);

class SyncRoundResult {
  const SyncRoundResult({
    required this.sent,
    required this.received,
    required this.rejected,
    required this.collections,
  });

  final int sent;
  final int received;

  /// Чужие записи, которые не прошли проверку формата и не применены.
  final int rejected;

  /// Коллекции, в которые записаны чужие правки.
  final Set<String> collections;
}

class _BaseEntry {
  const _BaseEntry(this.hash, this.rev);
  final String? hash;
  final int rev;
}

/// Один обмен с сервером: отправить своё, забрать чужое.
///
/// Свои правки находит сравнением с базой (хэши прошлого обмена), поэтому
/// репозиториям не нужно ничего отмечать. Всё, что после ответа сервера
/// читает и пишет хранилище, выполняется синхронно — между чтением и
/// записью не вклинится правка человека.
class SyncEngine {
  SyncEngine(
    this._storage, {
    required this.deviceId,
    required this.send,
    this.deviceName,
    this.baseKey = kSyncBaseKey,
    this.cursorKey = kSyncCursorKey,
  });

  /// Где лежат база и курсор: у каждого собеседника (сервер, соседи по
  /// сети) свои — обмен с одним не сбивает обмен с другим.
  final String baseKey;
  final String cursorKey;

  final LocalStorage _storage;
  final String deviceId;

  /// Имя для списка устройств на сервере ([syncDeviceName]).
  final String? deviceName;
  final SyncTransport send;

  /// Чужие правки записаны в хранилище (вызывается синхронно, сразу после
  /// записи): перечитать репозитории.
  void Function(Set<String> collections)? onApplied;

  /// Идёт запись чужих правок — хранилище сообщает о ней как о любой другой,
  /// но отправлять это обратно не нужно.
  bool get writing => _writing;
  bool _writing = false;

  static int _generation = 0;
  static int _replacing = 0;
  static const _skipped =
      SyncRoundResult(sent: 0, received: 0, rejected: 0, collections: {});

  /// Заменить данные устройства ([f]: восстановление бэкапа, «взять данные
  /// сервера»). Пока идёт [f], обмены не начинаются, а начатые раньше не
  /// записывают ответ: их база — от прежних данных, и следующий обмен
  /// разослал бы по ней удаления.
  static Future<T> replacing<T>(Future<T> Function() f) async {
    _replacing++;
    _generation++;
    try {
      return await f();
    } finally {
      _replacing--;
      _generation++;
    }
  }

  Future<SyncRoundResult> run() async {
    if (_replacing > 0) return _skipped;
    final generation = _generation;
    final base = _readBase();
    final cursorRaw = _storage.readMap(cursorKey);
    final cursor = cursorRaw?['rev'] as int? ?? 0;
    final epoch = cursorRaw?['epoch'] as String?;
    final snapshot = _readLocal();

    final changes = <Map<String, dynamic>>[];
    final sentHash = <String, Map<String, String?>>{};
    for (final c in kSyncCollections) {
      final mine = snapshot[c.name]!;
      final known = base[c.name] ?? const {};
      final out = sentHash[c.name] = {};
      mine.forEach((id, data) {
        final h = recordHash(data);
        final b = known[id];
        if (b != null && b.hash == h) return;
        out[id] = h;
        changes.add({
          'coll': c.name,
          'id': id,
          'baseRev': b?.rev ?? 0,
          'data': data,
        });
      });
      known.forEach((id, b) {
        if (b.hash == null || mine.containsKey(id)) return;
        out[id] = null;
        changes.add({
          'coll': c.name,
          'id': id,
          'baseRev': b.rev,
          'deleted': true,
        });
      });
    }

    final result = await send({
      'v': 1,
      'deviceId': deviceId,
      if (deviceName != null) 'deviceName': deviceName,
      'cursor': cursor,
      if (epoch != null) 'epoch': epoch,
      'changes': changes,
    });
    if (_replacing > 0 || generation != _generation) return _skipped;

    // Копию сервера создали заново (восстановление на соседе, битый файл):
    // она прислала всё с начала, а записей прежней базы, которых в ответе
    // нет, у неё больше нет. Их забываем — следующий обмен отправит их как
    // новые. Сервер без метки (старый) её не присылает.
    final newEpoch = result['epoch'] as String?;
    final storeChanged = epoch != null && newEpoch != null && newEpoch != epoch;
    final confirmed = <String>{};

    // ── Дальше без await до записи: хранилище читается заново и пишется
    // одним куском.
    final current = _readLocal();
    final touched = <String>{};
    final taskDays = <String>{};
    final statsDays = <String>{};

    for (final a in (result['applied'] as List? ?? const [])) {
      final m = a as Map<String, dynamic>;
      final coll = m['coll'] as String, id = m['id'] as String;
      final sent = sentHash[coll];
      if (sent == null || !sent.containsKey(id)) continue;
      (base[coll] ??= {})[id] = _BaseEntry(sent[id], m['rev'] as int);
      confirmed.add('$coll/$id');
    }

    var received = 0, rejected = 0;
    for (final r in (result['changes'] as List? ?? const [])) {
      final m = r as Map<String, dynamic>;
      final c = syncCollection(m['coll'] as String? ?? '');
      final id = m['id'] as String?;
      final rev = m['rev'] as int?;
      if (c == null || id == null || rev == null) {
        rejected++;
        continue;
      }
      final deleted = m['deleted'] == true;
      final data = deleted ? null : m['data'];
      if (!deleted && validateRecord(c, data) != null) {
        rejected++;
        continue;
      }
      confirmed.add('${c.name}/$id');
      final remoteHash = deleted ? null : recordHash(data);
      final mine = current[c.name]!;
      final before = mine[id];
      // Человек поправил запись, пока шёл запрос: его правка новее. Ревизию
      // запоминаем — следующий обмен отправит её как правку чужой версии.
      if (recordHash(before) != recordHash(snapshot[c.name]![id])) {
        (base[c.name] ??= {})[id] = _BaseEntry(remoteHash, rev);
        continue;
      }
      if (recordHash(before) == recordHash(data)) {
        (base[c.name] ??= {})[id] = _BaseEntry(remoteHash, rev);
        continue;
      }
      if (deleted) {
        mine.remove(id);
      } else {
        mine[id] = data as Map<String, dynamic>;
      }
      (base[c.name] ??= {})[id] = _BaseEntry(remoteHash, rev);
      touched.add(c.name);
      received++;
      if (c.name == 'tasks') {
        for (final t in [before, data]) {
          final d = (t as Map?)?['date'];
          if (d is String) taskDays.add(_dayKey(d));
        }
      } else if (c.name == 'dayStats') {
        statsDays.add(_dayKey(id));
      }
    }

    if (storeChanged) {
      base.forEach(
        (coll, m) => m.removeWhere((id, _) => !confirmed.contains('$coll/$id')),
      );
    }

    _writing = true;
    final writes = <Future<void>>[];
    for (final c in kSyncCollections) {
      if (!touched.contains(c.name)) continue;
      final mine = current[c.name]!;
      writes.add(
        c.isMap
            ? _storage.writeMap(
                c.storageKey,
                {for (final e in mine.entries) e.key: e.value['value']},
              )
            : _storage.writeList(c.storageKey, mine.values.toList()),
      );
    }
    final pending = {
      ...(_storage.readMap(kSyncPendingDaysKey)?['days'] as List? ?? const [])
          .cast<String>(),
      ...taskDays.difference(statsDays),
    };
    writes
      ..add(_storage.writeMap(kSyncPendingDaysKey, {'days': pending.toList()}))
      ..add(_writeBase(base))
      ..add(
        _storage.writeMap(cursorKey, {
          'rev': result['cursor'] as int? ?? cursor,
          if ((newEpoch ?? epoch) != null) 'epoch': newEpoch ?? epoch,
        }),
      );
    _writing = false;
    if (touched.isNotEmpty) onApplied?.call(touched);
    await Future.wait(writes);
    // Забытое — сразу на новую копию, не дожидаясь следующего повода.
    if (storeChanged) return run();

    return SyncRoundResult(
      sent: changes.length,
      received: received,
      rejected: rejected,
      collections: touched,
    );
  }

  /// Забыть базу и курсор: следующий обмен отправит все записи как новые
  /// (сервер оставит свои версии там, где они есть) и заберёт всё с начала.
  /// После восстановления бэкапа и при подключении к другому серверу —
  /// иначе отсутствие записей ушло бы на сервер удалениями.
  static Future<void> reset(LocalStorage storage) async {
    // Идущий обмен не должен записать старую базу поверх сброшенной.
    _generation++;
    await storage.remove(kSyncBaseKey);
    await storage.remove(kSyncCursorKey);
  }

  Map<String, Map<String, Map<String, dynamic>>> _readLocal() => {
        for (final c in kSyncCollections) c.name: _readCollection(c),
      };

  Map<String, Map<String, dynamic>> _readCollection(SyncCollection c) {
    if (c.isMap) {
      final m = _storage.readMap(c.storageKey) ?? const {};
      return {
        for (final e in m.entries) e.key: {'value': e.value},
      };
    }
    return {
      for (final r in _storage.readList(c.storageKey))
        if (r[c.idField] is String) r[c.idField] as String: r,
    };
  }

  Map<String, Map<String, _BaseEntry>> _readBase() {
    final raw = _storage.readMap(baseKey) ?? const {};
    return {
      for (final e in raw.entries)
        e.key: {
          for (final r in (e.value as Map).entries)
            r.key as String: _BaseEntry(
              (r.value as List)[0] as String?,
              (r.value as List)[1] as int,
            ),
        },
    };
  }

  Future<void> _writeBase(Map<String, Map<String, _BaseEntry>> base) =>
      _storage.writeMap(baseKey, {
        for (final e in base.entries)
          e.key: {
            for (final r in e.value.entries) r.key: [r.value.hash, r.value.rev],
          },
      });
}

/// «2026-10-28T00:00:00.000» → «2026-10-28».
String _dayKey(String iso) => iso.length >= 10 ? iso.substring(0, 10) : iso;
