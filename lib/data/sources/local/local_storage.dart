import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Простое JSON-хранилище поверх SharedPreferences.
/// MVP: хранит задачи, цели и профиль как JSON-строки.
/// Будет заменено на Drift в Этапе 1.
class LocalStorage {
  LocalStorage(this._prefs);

  final SharedPreferences _prefs;

  // ── Сырые операции ──────────────────────────────────────────────────────────

  List<Map<String, dynamic>> readList(String key) {
    final raw = _prefs.getString(key);
    if (raw == null) return [];
    return (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
  }

  Future<void> writeList(String key, List<Map<String, dynamic>> data) =>
      _prefs.setString(key, jsonEncode(data));

  Map<String, dynamic>? readMap(String key) {
    final raw = _prefs.getString(key);
    if (raw == null) return null;
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  Future<void> writeMap(String key, Map<String, dynamic> data) =>
      _prefs.setString(key, jsonEncode(data));

  Future<void> remove(String key) => _prefs.remove(key);

  /// Стирает ВСЁ хранилище — и данные, и настройки. Репозитории держат свои
  /// кэши в памяти и перезапишут их при первом же изменении, поэтому после
  /// вызова приложение нужно перезапустить (так же, как после импорта).
  Future<void> clearAll() => _prefs.clear();

  // ── Бэкап (этап 6-lite) ─────────────────────────────────────────────────

  /// Есть ли вообще задачи (для авто-восстановления при «пустом» старте).
  bool get hasData => _prefs.getString('tasks') != null;

  /// Полный слепок всех ключей хранилища (для экспорта).
  Map<String, Object?> snapshot() {
    final out = <String, Object?>{};
    for (final k in _prefs.getKeys()) {
      out[k] = _prefs.get(k);
    }
    return out;
  }

  /// Восстанавливает ключи из слепка. [clear] — стереть текущее перед записью
  /// (полная замена, а не слияние).
  Future<void> restore(Map<String, Object?> data, {bool clear = true}) async {
    if (clear) await _prefs.clear();
    for (final entry in data.entries) {
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
