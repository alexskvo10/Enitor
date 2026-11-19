import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../core/utils/secrets.dart';
import '../sync/lan/lan_crypto.dart';

export '../../../core/utils/secrets.dart';

/// Где физически лежат секреты. В приложении — системное защищённое
/// хранилище (Android Keystore, Windows DPAPI), в тестах — память.
abstract interface class SecretBackend {
  Future<String?> read(String name);
  Future<void> write(String name, String value);
  Future<void> delete(String name);
  Future<void> deleteAll();
}

/// Системное хранилище; открыто для фоновой синхронизации (без Riverpod).
class SecureSecretBackend implements SecretBackend {
  static const _storage = FlutterSecureStorage();

  @override
  Future<String?> read(String name) => _storage.read(key: name);

  @override
  Future<void> write(String name, String value) =>
      _storage.write(key: name, value: value);

  @override
  Future<void> delete(String name) => _storage.delete(key: name);

  @override
  Future<void> deleteAll() => _storage.deleteAll();
}

class MemorySecretBackend implements SecretBackend {
  final values = <String, String>{};

  @override
  Future<String?> read(String name) async => values[name];

  @override
  Future<void> write(String name, String value) async => values[name] = value;

  @override
  Future<void> delete(String name) async => values.remove(name);

  @override
  Future<void> deleteAll() async => values.clear();
}

/// Секреты интеграций: ключ Tasker и секреты вебхуков. Никогда не лежат в
/// SharedPreferences — значит, не попадают ни в бэкап, ни в авто-бэкап, ни в
/// экспорт. При удалении приложения на Android стираются вместе с ним.
class SecretStore {
  SecretStore(this._backend);

  final SecretBackend _backend;

  static const _taskerKey = 'tasker_key';
  static String _webhookKey(String id) => 'webhook_secret.$id';

  /// 32 случайных байта, base64url без «=» — удобно копировать в Tasker.
  static String generate() => generateSecretToken();

  /// Ключ Tasker; создаётся при первом обращении.
  Future<String> taskerKey() async {
    final existing = await _backend.read(_taskerKey);
    if (existing != null && existing.isNotEmpty) return existing;
    return rotateTaskerKey();
  }

  /// Новый ключ: старый перестаёт работать сразу.
  Future<String> rotateTaskerKey() async {
    final key = generate();
    await _backend.write(_taskerKey, key);
    return key;
  }

  /// Сравнение за постоянное время: по времени ответа нельзя подбирать ключ
  /// побайтно. Пустой ключ и ещё не созданный — всегда «неверно».
  Future<bool> checkTaskerKey(String? given) async {
    final key = await _backend.read(_taskerKey);
    if (key == null || key.isEmpty || given == null || given.isEmpty) {
      return false;
    }
    return constantTimeEquals(key, given);
  }

  Future<String> webhookSecret(String id) async {
    final existing = await _backend.read(_webhookKey(id));
    if (existing != null && existing.isNotEmpty) return existing;
    return rotateWebhookSecret(id);
  }

  /// Секрет вебхука, если он уже есть, — без создания. Доставка без секрета
  /// не уходит: подпись новым, которого приёмник не знает, молча ломала бы
  /// проверку на его стороне.
  Future<String?> readWebhookSecret(String id) async {
    final s = await _backend.read(_webhookKey(id));
    return s == null || s.isEmpty ? null : s;
  }

  Future<void> setWebhookSecret(String id, String secret) =>
      _backend.write(_webhookKey(id), secret);

  Future<String> rotateWebhookSecret(String id) async {
    final secret = generate();
    await _backend.write(_webhookKey(id), secret);
    return secret;
  }

  Future<void> deleteWebhookSecret(String id) =>
      _backend.delete(_webhookKey(id));

  static const _serverTokenKey = 'server_token';

  /// Токен своего сервера (синхронизация). null — сервер не подключён.
  Future<String?> serverToken() => _backend.read(_serverTokenKey);

  Future<void> setServerToken(String? token) => token == null
      ? _backend.delete(_serverTokenKey)
      : _backend.write(_serverTokenKey, token);

  static const _lanCertKey = 'lan_cert';
  static const _lanKeyKey = 'lan_key';
  static const _lanTokenKey = 'lan_token';

  /// Ключи устройства для синхронизации по сети; создаются при первом
  /// обращении.
  Future<LanIdentity> lanIdentity() async {
    final cert = await _backend.read(_lanCertKey);
    final key = await _backend.read(_lanKeyKey);
    final token = await _backend.read(_lanTokenKey);
    if (cert != null && key != null && token != null) {
      return LanIdentity(certPem: cert, keyPem: key, token: token);
    }
    final id = LanIdentity.generate();
    await _backend.write(_lanCertKey, id.certPem);
    await _backend.write(_lanKeyKey, id.keyPem);
    await _backend.write(_lanTokenKey, id.token);
    return id;
  }

  /// После выхода из группы: следующее знакомство — с новыми ключами.
  Future<void> deleteLanIdentity() async {
    await _backend.delete(_lanCertKey);
    await _backend.delete(_lanKeyKey);
    await _backend.delete(_lanTokenKey);
  }

  /// Часть «удалить все данные»: секреты лежат не в хранилище данных, и
  /// без этого ключ Tasker пережил бы полное удаление.
  Future<void> deleteAll() => _backend.deleteAll();
}

final secretStoreProvider =
    Provider<SecretStore>((ref) => SecretStore(SecureSecretBackend()));
