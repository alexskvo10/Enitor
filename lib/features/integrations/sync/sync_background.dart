import 'dart:isolate';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unifiedpush/unifiedpush.dart';
import 'package:workmanager/workmanager.dart';

import '../../../data/sources/local/local_storage.dart';
import '../core/secret_store.dart';
import 'sync_client.dart';
import 'sync_engine.dart';
import 'sync_service.dart';

// Синхронизация на Android, когда приложение не на экране:
// - UnifiedPush: сервер шлёт пустой сигнал на адрес доставщика (ntfy и т.п.),
//   система будит Enitor за секунды;
// - WorkManager раз в 15 минут — запасной путь, если доставщика нет.

/// Адрес и время регистрации UnifiedPush — для экрана «Сервер».
const kSyncPushKey = 'device.sync.push';

/// Через этот порт фоновый вызов отдаёт обмен живому приложению: два
/// изолята с разными копиями хранилища в памяти затёрли бы правки друг друга.
const _syncPortName = 'enitor.sync';
const _kTaskName = 'enitor-sync';

bool get _android => defaultTargetPlatform == TargetPlatform.android;

ReceivePort? _port;

/// Приложение на экране или свёрнуто, но живо: обмены идут через [service].
void attachForegroundSync(SyncService service) {
  if (!_android) return;
  _port?.close();
  IsolateNameServer.removePortNameMapping(_syncPortName);
  final port = _port = ReceivePort();
  IsolateNameServer.registerPortWithName(port.sendPort, _syncPortName);
  port.listen((_) => service.syncNow());
}

/// Обмен без интерфейса — из WorkManager или фонового движка UnifiedPush.
/// Чужие правки только записываются в хранилище; дубли повторов и
/// статистику дней приложение доделает при следующем открытии.
Future<bool> runBackgroundSync() async {
  final live = IsolateNameServer.lookupPortByName(_syncPortName);
  if (live != null) {
    live.send(null);
    return true;
  }
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();
  final storage = LocalStorage(prefs);
  final raw = storage.readMap(kSyncSettingsKey);
  final settings = raw == null ? null : SyncSettings.fromJson(raw);
  final token = await SecretStore(SecureSecretBackend()).serverToken();
  if (settings?.url == null || settings?.deviceId == null || token == null) {
    return true;
  }
  final client = SyncClient(baseUrl: settings!.url!, token: token);
  final now = DateTime.now();
  try {
    final r = await SyncEngine(
      storage,
      deviceId: settings.deviceId!,
      deviceName: deviceSyncName(storage),
      send: client.sync,
    ).run();
    await storage.writeMap(
      kSyncSettingsKey,
      settings.copyWith(lastSyncAt: now, clearError: true).toJson(),
    );
    await _log(
      storage,
      SyncLogEntry(at: now, sent: r.sent, received: r.received),
    );
    return true;
  } on SyncException catch (e) {
    await _log(
      storage,
      SyncLogEntry(at: now, error: e.message, code: e.code, status: e.status),
    );
    return false;
  } catch (e) {
    await _log(storage, SyncLogEntry(at: now, error: '$e'));
    // false — WorkManager повторит позже по своему графику.
    return false;
  } finally {
    client.close();
  }
}

Future<void> _log(LocalStorage storage, SyncLogEntry e) => storage.writeList(
      kSyncLogKey,
      [e.toJson(), ...storage.readList(kSyncLogKey)]
          .take(kSyncLogLimit)
          .toList(),
    );

@pragma('vm:entry-point')
void syncCallbackDispatcher() {
  Workmanager().executeTask((_, __) {
    DartPluginRegistrant.ensureInitialized();
    return runBackgroundSync();
  });
}

/// Включить или выключить фоновую синхронизацию (подключение/отключение
/// сервера). [service] — живое приложение; null — фоновый движок.
Future<void> setBackgroundSync(bool on, {SyncService? service}) async {
  if (!_android) return;
  await Workmanager().initialize(syncCallbackDispatcher);
  if (on) {
    await Workmanager().registerPeriodicTask(
      _kTaskName,
      _kTaskName,
      frequency: const Duration(minutes: 15),
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    );
    await initPush(service);
    if (await UnifiedPush.tryUseCurrentOrDefaultDistributor()) {
      await UnifiedPush.register();
    }
  } else {
    await Workmanager().cancelByUniqueName(_kTaskName);
    await UnifiedPush.unregister();
  }
}

/// Обработчики UnifiedPush. Регистрацию нужно повторять при каждом запуске —
/// так требует библиотека.
Future<void> initPush(SyncService? service) async {
  if (!_android) return;
  final hasDistributor = await UnifiedPush.initialize(
    onNewEndpoint: (endpoint, _) => _sendEndpoint(endpoint.url),
    onUnregistered: (_) => _sendEndpoint(null),
    onMessage: (_, __) {
      if (service != null) {
        service.syncNow();
      } else {
        runBackgroundSync();
      }
    },
  );
  if (hasDistributor && service != null) await UnifiedPush.register();
}

Future<void> _sendEndpoint(String? url) async {
  final prefs = await SharedPreferences.getInstance();
  final storage = LocalStorage(prefs);
  final raw = storage.readMap(kSyncSettingsKey);
  final settings = raw == null ? null : SyncSettings.fromJson(raw);
  final token = await SecretStore(SecureSecretBackend()).serverToken();
  await storage.writeMap(kSyncPushKey, {
    'endpoint': url,
    'at': DateTime.now().toIso8601String(),
  });
  if (settings?.url == null || settings?.deviceId == null || token == null) {
    return;
  }
  final client = SyncClient(baseUrl: settings!.url!, token: token);
  try {
    await client.setPushEndpoint(settings.deviceId!, url);
  } catch (_) {
    // Сервер недоступен — адрес уйдёт при следующей регистрации (каждый запуск).
  } finally {
    client.close();
  }
}

/// Точка входа фонового движка UnifiedPush (`main` с `--unifiedpush-bg`):
/// без интерфейса, только приём сигнала.
Future<void> runPushBackground() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initPush(null);
}
