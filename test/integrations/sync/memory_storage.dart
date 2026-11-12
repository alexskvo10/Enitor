import 'dart:convert';

import 'package:enitor/data/sources/local/local_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Хранилище «отдельного устройства»: SharedPreferences в тестах один на
/// процесс, а для синхронизации нужно два независимых.
class MemoryStorage extends LocalStorage {
  MemoryStorage._(super.prefs);

  static Future<MemoryStorage> create() async {
    SharedPreferences.setMockInitialValues({});
    return MemoryStorage._(await SharedPreferences.getInstance());
  }

  final values = <String, String>{};

  @override
  List<Map<String, dynamic>> readList(String key) {
    final raw = values[key];
    return raw == null
        ? []
        : (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
  }

  @override
  Map<String, dynamic>? readMap(String key) {
    final raw = values[key];
    return raw == null ? null : jsonDecode(raw) as Map<String, dynamic>;
  }

  @override
  Future<void> writeList(String key, List<Map<String, dynamic>> data) async =>
      values[key] = jsonEncode(data);

  @override
  Future<void> writeMap(String key, Map<String, dynamic> data) async =>
      values[key] = jsonEncode(data);

  @override
  Future<void> remove(String key) async => values.remove(key);
}
