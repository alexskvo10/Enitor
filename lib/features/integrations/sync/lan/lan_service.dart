import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../../../data/sources/local/local_storage.dart';
import '../../core/integration_gateway.dart';
import '../../core/secret_store.dart';
import '../sync_collections.dart';
import '../sync_engine.dart';
import '../sync_service.dart';
import 'lan_group.dart';
import 'lan_node.dart';

/// Синхронизация по сети в приложении: когда запускать узел, что делать с
/// чужими правками, что показать на экране. Сам обмен — [LanNode].
class LanSyncService {
  LanSyncService(this._ref, {Future<File> Function()? storeFile})
      : _storeFile = storeFile ?? _defaultStoreFile;

  final Ref _ref;
  final Future<File> Function() _storeFile;

  static Future<File> _defaultStoreFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}${Platform.pathSeparator}lan-store.json');
  }

  LocalStorage get _storage => _ref.read(localStorageProvider);
  void _bump() => _ref.read(lanRevisionProvider.notifier).state++;

  static final _syncedKeys = {for (final c in kSyncCollections) c.storageKey};

  LanNode? _node;
  Future<LanNode>? _creating;
  StreamSubscription<String>? _changesSub;
  Timer? _debounce;
  AppLifecycleListener? _lifecycle;

  /// Устройство с кодом спрашивает «Подключить …?» через это (ставит экран
  /// знакомства, пока он открыт).
  Future<bool> Function(String name)? confirmJoin;

  /// Это устройство отключили с другого — сказать человеку.
  void Function()? onRevoked;

  LanNode? get node => _node;

  /// Устройства группы; пока узел запускается — из хранилища.
  List<LanMember> get members =>
      _node?.members ??
      lanMembersFromWire(_storage.readMap(kLanGroupKey)?['members']);

  String? get deviceId =>
      _node?.deviceId ?? _storage.readMap(kLanGroupKey)?['deviceId'] as String?;

  /// Есть ли группа (хоть одно другое устройство) — без запуска узла.
  bool get hasGroup {
    final n = _node;
    if (n != null) return n.inGroup;
    final raw = _storage.readMap(kLanGroupKey);
    final self = raw?['deviceId'];
    return lanMembersFromWire(raw?['members'])
        .any((m) => m.id != self && !m.revoked);
  }

  Future<LanNode> _ensureNode() async {
    if (_node != null) return _node!;
    return _creating ??= () async {
      final node = LanNode(
        storage: _storage,
        identity: await _ref.read(secretStoreProvider).lanIdentity(),
        storeFile: await _storeFile(),
        deviceName: deviceSyncName(_storage),
      )
        ..onApplied = ((c) => _ref.read(syncServiceProvider).applyRemote(c))
        ..onChanged = _bump
        ..confirmJoin =
            ((String name) => confirmJoin?.call(name) ?? Future.value(false))
        ..onRevoked = () {
          _node = null;
          unawaited(_ref.read(secretStoreProvider).deleteLanIdentity());
          _bump();
          onRevoked?.call();
        };
      try {
        await node.start();
      } finally {
        _creating = null;
      }
      _node = node;
      await _multicast(true);
      _bump();
      return node;
    }();
  }

  // ── Запуск ────────────────────────────────────────────────────────────────

  /// При старте приложения: узел работает, только если есть группа.
  void start() {
    _lifecycle ??= AppLifecycleListener(
      onResume: () {
        unawaited(_multicast(true));
        unawaited(_node?.tick());
      },
      onPause: () => unawaited(_multicast(false)),
    );
    _changesSub ??= _storage.changes.listen((key) {
      if (!_syncedKeys.contains(key)) return;
      final n = _node;
      if (n == null || n.writing) return;
      _debounce?.cancel();
      _debounce =
          Timer(const Duration(seconds: 2), () => unawaited(n.syncAll()));
    });
    if (hasGroup) unawaited(_ensureNode().then((_) {}, onError: (Object _) {}));
  }

  Future<void> syncNow() async {
    final n = await _ensureNode();
    await n.tick(sweep: true);
  }

  // ── Знакомство ────────────────────────────────────────────────────────────

  Future<LanPairing> openPairing() async => (await _ensureNode()).openPairing();

  Future<String> pairingLink() async => (await _ensureNode()).pairingLink();

  void closePairing() {
    _node?.closePairing();
    _stopIfAlone();
  }

  Future<LanMember> join(
    String code, {
    List<String> hosts = const [],
    int? port,
    String? fingerprint,
  }) async {
    final n = await _ensureNode();
    try {
      return await n.join(
        code,
        hosts: hosts,
        port: port,
        fingerprint: fingerprint,
      );
    } finally {
      _stopIfAlone();
    }
  }

  /// Знакомство не состоялось и группы нет — сеть не слушаем зря.
  void _stopIfAlone() {
    final n = _node;
    if (n == null || n.inGroup || n.pairing != null) return;
    _node = null;
    unawaited(n.stop());
    unawaited(_multicast(false));
    _bump();
  }

  // ── Группа ────────────────────────────────────────────────────────────────

  Future<void> revoke(String id) async {
    await (await _ensureNode()).revoke(id);
    _stopIfAlone();
  }

  /// Выйти из группы: данные остаются, обмен прекращается; следующее
  /// знакомство — с новыми ключами.
  Future<void> leave() async {
    final n = await _ensureNode();
    _node = null;
    await n.leave();
    await _ref.read(secretStoreProvider).deleteLanIdentity();
    await _multicast(false);
    _bump();
  }

  /// Заменить данные устройства (восстановление бэкапа, «взять данные
  /// сервера»). Пока [replace] пишет, узел стоит и обмены не идут: иначе
  /// обмен принял бы недописанные данные за правки человека и разослал
  /// бы соседям удаления. Базы обменов сбрасывает [replace] (см.
  /// [LanNode.resetAfterRestore]); свою копию сервера сотрёт запуск.
  Future<T> replaceData<T>(Future<T> Function() replace) async {
    final n = _node;
    _node = null;
    await n?.stop();
    try {
      return await SyncEngine.replacing(replace);
    } finally {
      if (hasGroup) {
        await _ensureNode().then((_) {}, onError: (Object _) {});
      }
      _bump();
    }
  }

  /// Перед «Удалить все данные»: группа и своя копия сервера — тоже данные.
  Future<void> forgetForWipe() async {
    final n = _node;
    _node = null;
    await n?.stop();
    try {
      final f = await _storeFile();
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  /// Android: без этого телефон не слышит широковещательные пакеты соседей
  /// (свои вопросы шлёт и ответы получает и так).
  Future<void> _multicast(bool on) async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    if (on && _node == null && _creating == null) return;
    try {
      await kCommandsChannel.invokeMethod<void>('multicastLock', {'on': on});
    } catch (_) {}
  }

  void dispose() {
    _debounce?.cancel();
    _changesSub?.cancel();
    _lifecycle?.dispose();
    unawaited(_node?.stop());
  }
}

final lanSyncServiceProvider = Provider<LanSyncService>((ref) {
  final s = LanSyncService(ref);
  ref.onDispose(s.dispose);
  return s;
});

/// Счётчик для экрана: растёт при каждом изменении в группе и обмене.
final lanRevisionProvider = StateProvider<int>((ref) => 0);

/// Ссылка `enitor://pair…`, открытая камерой: экран синхронизации заберёт
/// её и предложит подключиться.
final lanPairLinkProvider = StateProvider<Uri?>((ref) => null);
