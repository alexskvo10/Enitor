import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:enitor/data/sources/local/local_storage.dart';
import 'package:enitor/services/backup_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('round-trip: snapshot → JSON → restore сохраняет данные и типы',
      () async {
    SharedPreferences.setMockInitialValues({
      'tasks': jsonEncode([
        {'id': '1', 'title': 'Купить хлеб'},
      ]),
      'appearance': jsonEncode({'style': 1, 'vignette': true}),
      'some_bool': true,
      'some_int': 42,
    });
    final prefs = await SharedPreferences.getInstance();
    final storage = LocalStorage(prefs);
    final backup = BackupService(storage);

    final json = backup.buildJson();
    expect(json, contains('Купить хлеб'));

    // Затираем всё другими данными.
    await prefs.clear();
    await prefs.setString('tasks', jsonEncode([]));
    expect(storage.readList('tasks'), isEmpty);

    // Восстанавливаем из бэкапа.
    await backup.restoreFromJson(json);

    expect(storage.readList('tasks').first['title'], 'Купить хлеб');
    expect(storage.readMap('appearance')!['vignette'], true);
    expect(prefs.getBool('some_bool'), true);
    expect(prefs.getInt('some_int'), 42);
  });

  test('restoreFromJson отвергает чужой файл', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final backup = BackupService(LocalStorage(prefs));

    expect(
      () => backup.restoreFromJson('{"app":"other","data":{}}'),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => backup.restoreFromJson('не json вовсе'),
      throwsA(anything),
    );
  });
}
