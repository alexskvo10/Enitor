import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Префикс ключей «устройство»: состояние именно этого устройства (настройки
/// интеграций, очередь вебхуков, снимок для виджета). В бэкап не попадает и
/// при восстановлении бэкапа не стирается — иначе копия с телефона включила
/// бы на ноутбуке чужие интеграции, а восстановление заново отправило бы
/// старые события.
const kDeviceKeyPrefix = 'device.';

/// Простое JSON-хранилище поверх SharedPreferences.
/// MVP: хранит задачи, цели и профиль как JSON-строки.
/// Будет заменено на Drift в Этапе 1.
class LocalStorage {
  LocalStorage(this._prefs);

  final SharedPreferences _prefs;

  final _changes = StreamController<String>.broadcast(sync: true);

  /// Ключи данных (не «устройство»), записанные через это хранилище, — по
  /// ним синхронизация понимает, что пора отправить правки.
  Stream<String> get changes => _changes.stream;

  void _changed(String key) {
    if (!key.startsWith(kDeviceKeyPrefix)) _changes.add(key);
  }

  /// Перечитать ключи с диска: их мог записать фоновый изолят (синхронизация
  /// на Android в фоне), а у этого изолята в памяти старые значения.
  Future<void> reloadFromDisk() => _prefs.reload();

  // ── Сырые операции ──────────────────────────────────────────────────────────

  List<Map<String, dynamic>> readList(String key) {
    final raw = _prefs.getString(key);
    if (raw == null) return [];
    return (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
  }

  Future<void> writeList(String key, List<Map<String, dynamic>> data) {
    final f = _prefs.setString(key, jsonEncode(data));
    _changed(key);
    return f;
  }

  Map<String, dynamic>? readMap(String key) {
    final raw = _prefs.getString(key);
    if (raw == null) return null;
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  Future<void> writeMap(String key, Map<String, dynamic> data) {
    final f = _prefs.setString(key, jsonEncode(data));
    _changed(key);
    return f;
  }

  Future<void> remove(String key) => _prefs.remove(key);

  /// Стирает ВСЁ хранилище — и данные, и настройки. Репозитории держат свои
  /// кэши в памяти и перезапишут их при первом же изменении, поэтому после
  /// вызова приложение нужно перезапустить (так же, как после импорта).
  Future<void> clearAll() => _prefs.clear();

  // ── Бэкап (этап 6-lite) ─────────────────────────────────────────────────

  /// Есть ли в хранилище хоть что-то, кроме ключей «устройство» (для
  /// авто-восстановления при «пустом» старте). Не только задачи: у кого одни
  /// цели или расписание, старт иначе каждый раз откатывался бы к бэкапу.
  bool get hasData =>
      _prefs.getKeys().any((k) => !k.startsWith(kDeviceKeyPrefix));

  /// Слепок всех ключей хранилища для бэкапа — кроме ключей «устройство».
  Map<String, Object?> snapshot() {
    final out = <String, Object?>{};
    for (final k in _prefs.getKeys()) {
      if (k.startsWith(kDeviceKeyPrefix)) continue;
      out[k] = _prefs.get(k);
    }
    return out;
  }

  /// Восстанавливает ключи из слепка. [clear] — стереть текущее перед записью
  /// (полная замена, а не слияние). Ключи «устройство» не трогает ни при
  /// очистке, ни при записи.
  Future<void> restore(Map<String, Object?> data, {bool clear = true}) async {
    if (clear) {
      for (final k in _prefs.getKeys().toList()) {
        if (!k.startsWith(kDeviceKeyPrefix)) await _prefs.remove(k);
      }
    }
    for (final entry in data.entries) {
      if (entry.key.startsWith(kDeviceKeyPrefix)) continue;
      final v = entry.value;
      if (v is String) {
        await _prefs.setString(entry.key, v);
      } else if (v is bool) {
        await _prefs.setBool(entry.key, v);
      } else if (v is int) {
        await _prefs.setInt(entry.key, v);
      } else if (v is double) {
        await _prefs.setDouble(entry.key, v);
      } else if (v is List) {
        await _prefs.setStringList(
            entry.key, v.map((e) => e.toString()).toList());
      }
    }
  }
}

final localStorageProvider = Provider<LocalStorage>(
  (ref) => throw UnimplementedError('Override in main()'),
);
