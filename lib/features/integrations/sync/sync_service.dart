import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../../../core/utils/date_utils.dart';
import '../../../data/repositories/backlog_repository.dart';
import '../../../data/repositories/goal_repository.dart';
import '../../../data/repositories/rating_repository.dart';
import '../../../data/repositories/recurrence_repository.dart';
import '../../../data/repositories/schedule_repository.dart';
import '../../../data/repositories/stats_repository.dart';
import '../../../data/repositories/task_repository.dart';
import '../../../data/repositories/template_repository.dart';
import '../../../data/sources/local/local_storage.dart';
import '../../../services/backup_service.dart';
import '../core/secret_store.dart';
import 'lan/lan_node.dart';
import 'lan/lan_service.dart';
import 'sync_client.dart';
import 'sync_collections.dart';
import 'sync_engine.dart';

// Ключи «устройство»: у каждого устройства свой адрес, id и журнал.
const kSyncSettingsKey = 'device.sync.settings';
const kSyncLogKey = 'device.sync.log';
const kSyncLogLimit = 50;
const kSyncTabletKey = 'device.sync.tablet';

/// Имя для списка устройств ([syncDeviceName]). Планшет — короткая сторона
/// экрана от 600 dp (порог Material). У фонового движка экрана нет — там
/// берётся то, что запомнило живое приложение.
String deviceSyncName(LocalStorage storage) {
  final displays = PlatformDispatcher.instance.displays;
  bool tablet;
  if (displays.isEmpty) {
    tablet = storage.readMap(kSyncTabletKey)?['tablet'] == true;
  } else {
    final d = displays.first;
    tablet = (d.size / d.devicePixelRatio).shortestSide >= 600;
    unawaited(storage.writeMap(kSyncTabletKey, {'tablet': tablet}));
  }
  return syncDeviceName(tablet: tablet);
}

/// Пауза после своей правки: серия быстрых правок уйдёт одним обменом.
const kSyncDebounce = Duration(seconds: 3);

/// Запасной опрос, если сервер не держит поток событий.
const kSyncPollInterval = Duration(minutes: 5);

class SyncSettings {
  const SyncSettings({
    this.url,
    this.deviceId,
    this.lastSyncAt,
    this.lastErrorCode,
    this.lastError,
  });

  /// Адрес сервера; null — не подключён.
  final String? url;
  final String? deviceId;
  final DateTime? lastSyncAt;
  final String? lastErrorCode;
  final String? lastError;

  bool get connected => url != null;

  SyncSettings copyWith({
    String? url,
    String? deviceId,
    DateTime? lastSyncAt,
    String? lastErrorCode,
    String? lastError,
    bool clearError = false,
  }) =>
      SyncSettings(
        url: url ?? this.url,
        deviceId: deviceId ?? this.deviceId,
        lastSyncAt: lastSyncAt ?? this.lastSyncAt,
        lastErrorCode: clearError ? null : lastErrorCode ?? this.lastErrorCode,
        lastError: clearError ? null : lastError ?? this.lastError,
      );

  Map<String, dynamic> toJson() => {
        'url': url,
        'deviceId': deviceId,
        'lastSyncAt': lastSyncAt?.toIso8601String(),
        'lastErrorCode': lastErrorCode,
        'lastError': lastError,
      };

  factory SyncSettings.fromJson(Map<String, dynamic> j) => SyncSettings(
        url: j['url'] as String?,
        deviceId: j['deviceId'] as String?,
        lastSyncAt: DateTime.tryParse(j['lastSyncAt'] as String? ?? ''),
        lastErrorCode: j['lastErrorCode'] as String?,
        lastError: j['lastError'] as String?,
      );
}

/// Строка журнала: один обмен.
class SyncLogEntry {
  const SyncLogEntry({
    required this.at,
    this.sent = 0,
    this.received = 0,
    this.error,
    this.code,
    this.status,
  });

  final DateTime at;
  final int sent;
  final int received;
  final String? error;

  /// Код [SyncException] — по нему экран пишет ошибку на языке интерфейса;
  /// [error] — исходный текст (для старых записей и неизвестных ошибок).
  final String? code;
  final int? status;

  Map<String, dynamic> toJson() => {
        'at': at.toIso8601String(),
        'sent': sent,
        'received': received,
        if (error != null) 'error': error,
        if (code != null) 'code': code,
        if (status != null) 'status': status,
      };

  factory SyncLogEntry.fromJson(Map<String, dynamic> j) => SyncLogEntry(
        at: DateTime.parse(j['at'] as String),
        sent: j['sent'] as int? ?? 0,
        received: j['received'] as int? ?? 0,
        error: j['error'] as String?,
        code: j['code'] as String?,
        status: j['status'] as int?,
      );
}

/// Синхронизация со своим сервером: когда обмениваться и что делать после.
/// Сам обмен — [SyncEngine], HTTP — [SyncClient].
class SyncService {
  SyncService(this._ref, {http.Client Function()? client})
      : _client = client ?? http.Client.new;

  final Ref _ref;
  final http.Client Function() _client;

  LocalStorage get _storage => _ref.read(localStorageProvider);
  void _bump() => _ref.read(syncRevisionProvider.notifier).state++;

  static final _syncedKeys = {for (final c in kSyncCollections) c.storageKey};

  SyncEngine? _engine;
  Future<void>? _running;
  bool _again = false;
  bool _disposed = false;
  bool _started = false;
  Timer? _debounce;
  Timer? _poll;
  StreamSubscription<String>? _changesSub;
  StreamSubscription<int>? _eventsSub;
  SyncClient? _eventsClient;
  Timer? _eventsRetry;
  Duration _eventsBackoff = const Duration(seconds: 5);
  AppLifecycleListener? _lifecycle;

  /// Включить/выключить фоновую синхронизацию платформы (Android:
  /// WorkManager и UnifiedPush). Задаётся в main, в тестах — нет.
  Future<void> Function(bool on)? onBackground;

  /// Обмен прямо сейчас (для экрана и тестов).
  bool get syncing => _running != null;

  SyncSettings get settings {
    final raw = _storage.readMap(kSyncSettingsKey);
    return raw == null ? const SyncSettings() : SyncSettings.fromJson(raw);
  }

  Future<void> _saveSettings(SyncSettings s) async {
    await _storage.writeMap(kSyncSettingsKey, s.toJson());
    _bump();
  }

  List<SyncLogEntry> get log => [
        for (final e in _storage.readList(kSyncLogKey))
          SyncLogEntry.fromJson(e),
      ];

  Future<void> _addLog(SyncLogEntry e) async {
    final list = [e, ...log].take(kSyncLogLimit).toList();
    await _storage.writeList(kSyncLogKey, [for (final x in list) x.toJson()]);
  }

  Future<void> clearLog() async {
    await _storage.writeList(kSyncLogKey, const []);
    _bump();
  }

  // ── Подключение ───────────────────────────────────────────────────────────

  /// Проверить адрес и токен: `GET /v1/ping`. Бросает [SyncException].
  Future<void> check(String url, String token) async {
    final c = SyncClient(baseUrl: url, token: token, client: _client());
    try {
      await c.ping();
    } finally {
      c.close();
    }
  }

  /// Подключиться. [takeServer] — заменить данные этого устройства данными
  /// сервера (перед этим — авто-бэкап); иначе объединить: свои записи
  /// уходят на сервер, где запись уже есть — остаётся серверная.
  Future<void> connect({
    required String url,
    required String token,
    required bool takeServer,
  }) async {
    await check(url, token);
    _stopListening();
    if (takeServer) {
      // Стирание — замена данных, как восстановление бэкапа: иначе обмен по
      // сети принял бы его за удаления и разослал соседям.
      await _ref.read(lanSyncServiceProvider).replaceData(() async {
        final backup = BackupService(_storage);
        await backup.writeAutoBackup();
        for (final c in kSyncCollections) {
          if (c.isMap) {
            await _storage.writeMap(c.storageKey, const {});
          } else {
            await _storage.writeList(c.storageKey, const []);
          }
        }
        await SyncEngine.reset(_storage);
        await LanNode.resetAfterRestore(_storage);
        _reloadRepositories(kSyncCollections.map((c) => c.name).toSet());
      });
    }
    await SyncEngine.reset(_storage);
    await _ref.read(secretStoreProvider).setServerToken(token);
    await _saveSettings(
      SyncSettings(
        url: normalizeServerUrl(url),
        deviceId: settings.deviceId ?? const Uuid().v4(),
      ),
    );
    _engine = null;
    await syncNow();
    if (_started) _listen();
    await onBackground?.call(true);
  }

  /// Устройства на сервере. null — не подключены или сервер не ответил
  /// (в том числе старый сервер без `/v1/devices`).
  Future<List<SyncDevice>?> devices() => _withClient((c) => c.devices());

  /// Убрать устройство из списка сервера. false — не вышло.
  Future<bool> forgetDevice(String id) async =>
      await _withClient((c) => c.forgetDevice(id).then((_) => true)) ?? false;

  Future<T?> _withClient<T>(Future<T> Function(SyncClient c) f) async {
    final s = settings;
    final token = await _ref.read(secretStoreProvider).serverToken();
    if (s.url == null || token == null) return null;
    final c = SyncClient(baseUrl: s.url!, token: token, client: _client());
    try {
      return await f(c);
    } on SyncException {
      return null;
    } finally {
      c.close();
    }
  }

  /// Отключиться: данные на устройстве остаются, обмен прекращается.
  /// Себя из списка устройств на сервере убираем, если он доступен.
  Future<void> disconnect() async {
    final id = settings.deviceId;
    if (id != null) await forgetDevice(id);
    _stopListening();
    await onBackground?.call(false);
    _engine = null;
    await _ref.read(secretStoreProvider).setServerToken(null);
    await SyncEngine.reset(_storage);
    await _saveSettings(SyncSettings(deviceId: settings.deviceId));
  }

  // ── Обмен ─────────────────────────────────────────────────────────────────

  Future<SyncEngine?> _engineFor(SyncSettings s) async {
    if (_engine != null) return _engine;
    final token = await _ref.read(secretStoreProvider).serverToken();
    if (s.url == null || s.deviceId == null || token == null) return null;
    final engine = SyncEngine(
      _storage,
      deviceId: s.deviceId!,
      deviceName: deviceSyncName(_storage),
      send: (body) async {
        final c = SyncClient(baseUrl: s.url!, token: token, client: _client());
        try {
          return await c.sync(body);
        } finally {
          c.close();
        }
      },
    )..onApplied = _reloadRepositories;
    return _engine = engine;
  }

  /// Один обмен; если уже идёт — ещё один сразу после него.
  Future<void> syncNow() {
    if (_running != null) {
      _again = true;
      return _running!;
    }
    final f = _runLoop();
    _running = f;
    return f.whenComplete(() => _running = null);
  }

  Future<void> _runLoop() async {
    do {
      _again = false;
      await _round();
    } while (_again && !_disposed);
  }

  Future<void> _round() async {
    final s = settings;
    if (!s.connected) return;
    final engine = await _engineFor(s);
    if (engine == null) return;
    final now = DateTime.now();
    try {
      final r = await engine.run();
      await finishPending();
      await _addLog(SyncLogEntry(at: now, sent: r.sent, received: r.received));
      await _saveSettings(settings.copyWith(lastSyncAt: now, clearError: true));
    } on SyncException catch (e) {
      await _addLog(
        SyncLogEntry(at: now, error: e.message, code: e.code, status: e.status),
      );
      await _saveSettings(
        settings.copyWith(lastErrorCode: e.code, lastError: e.message),
      );
    } catch (e) {
      await _addLog(SyncLogEntry(at: now, error: '$e'));
      await _saveSettings(
        settings.copyWith(lastErrorCode: 'error', lastError: '$e'),
      );
    }
  }

  void _reloadRepositories(Set<String> collections) {
    for (final name in collections) {
      switch (name) {
        case 'tasks':
          _ref.read(taskRepositoryProvider).reload();
        case 'goals':
          _ref.read(goalRepositoryProvider).reload();
        case 'schedule':
          _ref.read(scheduleRepositoryProvider).reload();
        case 'recurrence':
          _ref.read(recurrenceRepositoryProvider).reload();
        case 'templates':
          _ref.read(templateRepositoryProvider).reload();
        case 'taskBacklog':
          _ref.read(backlogRepositoryProvider).reload();
        case 'goalBacklog':
          _ref.read(goalBacklogRepositoryProvider).reload();
        case 'dayStats':
          _ref.read(statsRepositoryProvider).reload();
        case 'dayRatings' || 'periodRatings':
          _ref.read(ratingRepositoryProvider).reload();
      }
    }
    if (collections.contains('tasks')) _tasksChanged = true;
  }

  bool _tasksChanged = false;

  /// Чужие правки пришли другим путём (синхронизация по сети): перечитать
  /// репозитории и доделать статистику дней — как после своего обмена.
  void applyRemote(Set<String> collections) {
    _reloadRepositories(collections);
    unawaited(finishPending());
  }

  /// Доделать то, что обмен оставил репозиториям: дубли повторов и
  /// статистику дней, чьи задачи поменялись не на устройстве. Сюда же —
  /// дни, оставленные фоновой синхронизацией.
  Future<void> finishPending() async {
    final days =
        (_storage.readMap(kSyncPendingDaysKey)?['days'] as List? ?? const [])
            .cast<String>();
    if (days.isEmpty && !_tasksChanged) return;
    _tasksChanged = false;
    await _storage.writeMap(kSyncPendingDaysKey, const {'days': <String>[]});
    await _ref.read(taskRepositoryProvider).afterRemoteChanges({
      for (final d in days)
        if (DateTime.tryParse(d) != null) dateOnly(DateTime.parse(d)),
    });
  }

  // ── Когда обмениваться ────────────────────────────────────────────────────

  /// Подписки на правки, возврат в приложение, поток событий сервера.
  /// Вызывается один раз при запуске приложения.
  void start() {
    if (_started) return;
    _started = true;
    _lifecycle = AppLifecycleListener(
      onResume: () => unawaited(_onResume()),
      onPause: () {
        // На телефоне соединение в фоне всё равно оборвут — не держим его.
        if (defaultTargetPlatform == TargetPlatform.android) _stopEvents();
      },
    );
    if (settings.connected) _listen();
    unawaited(finishPending().then((_) => syncNow()));
  }

  Future<void> _onResume() async {
    if (!settings.connected) return;
    if (defaultTargetPlatform == TargetPlatform.android) {
      // Фоновая синхронизация писала хранилище из другого изолята.
      await _storage.reloadFromDisk();
      _engine = null;
      _reloadRepositories(kSyncCollections.map((c) => c.name).toSet());
      _tasksChanged = false;
    }
    _startEvents();
    await syncNow();
  }

  void _listen() {
    _changesSub ??= _storage.changes.listen((key) {
      if (!_syncedKeys.contains(key)) return;
      if (_engine?.writing ?? false) return;
      _debounce?.cancel();
      _debounce = Timer(kSyncDebounce, () => unawaited(syncNow()));
    });
    _poll ??= Timer.periodic(kSyncPollInterval, (_) => unawaited(syncNow()));
    _startEvents();
  }

  void _stopListening() {
    _changesSub?.cancel();
    _changesSub = null;
    _debounce?.cancel();
    _poll?.cancel();
    _poll = null;
    _stopEvents();
  }

  void _startEvents() {
    if (_eventsSub != null || _disposed || !settings.connected) return;
    _eventsRetry?.cancel();
    unawaited(_openEvents());
  }

  Future<void> _openEvents() async {
    final s = settings;
    final token = await _ref.read(secretStoreProvider).serverToken();
    if (s.url == null || token == null || _eventsSub != null) return;
    final c = _eventsClient =
        SyncClient(baseUrl: s.url!, token: token, client: _client());
    void retry() {
      _eventsSub = null;
      _eventsClient = null;
      c.close();
      if (_disposed || !_started || !settings.connected) return;
      _eventsRetry = Timer(_eventsBackoff, _startEvents);
      final next = _eventsBackoff * 2;
      _eventsBackoff =
          next > const Duration(minutes: 1) ? const Duration(minutes: 1) : next;
    }

    _eventsSub = c.events().listen(
      (rev) {
        _eventsBackoff = const Duration(seconds: 5);
        final cursor = _storage.readMap(kSyncCursorKey)?['rev'] as int? ?? 0;
        if (rev > cursor) unawaited(syncNow());
      },
      onError: (_) => retry(),
      onDone: retry,
      cancelOnError: true,
    );
  }

  void _stopEvents() {
    _eventsRetry?.cancel();
    _eventsSub?.cancel();
    _eventsSub = null;
    _eventsClient?.close();
    _eventsClient = null;
  }

  void dispose() {
    _disposed = true;
    _stopListening();
    _lifecycle?.dispose();
  }
}

final syncServiceProvider = Provider<SyncService>((ref) {
  final s = SyncService(ref);
  ref.onDispose(s.dispose);
  return s;
});

/// Счётчик для экрана: растёт после каждого обмена и смены настроек.
final syncRevisionProvider = StateProvider<int>((ref) => 0);

final syncSettingsProvider = Provider<SyncSettings>((ref) {
  ref.watch(syncRevisionProvider);
  return ref.watch(syncServiceProvider).settings;
});

final syncLogProvider = Provider<List<SyncLogEntry>>((ref) {
  ref.watch(syncRevisionProvider);
  return ref.watch(syncServiceProvider).log;
});
