import 'package:enitor/data/sources/local/local_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// «Пустой старт» для авто-восстановления: данные — не только задачи.
void main() {
  Future<LocalStorage> with_(Map<String, Object> v) async {
    SharedPreferences.setMockInitialValues(v);
    return LocalStorage(await SharedPreferences.getInstance());
  }

  test('пусто или только ключи устройства — данных нет', () async {
    expect((await with_({})).hasData, isFalse);
    expect((await with_({'device.sync.base': 'x'})).hasData, isFalse);
  });

  test('одни цели или расписание — данные есть', () async {
    expect((await with_({'goals': '[]'})).hasData, isTrue);
    expect((await with_({'schedule_items': '[]'})).hasData, isTrue);
  });
}
