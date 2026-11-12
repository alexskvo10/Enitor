import 'dart:convert';

import 'package:enitor/data/sources/local/local_storage.dart';
import 'package:enitor/features/integrations/core/secret_store.dart';
import 'package:enitor/services/backup_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Приватность бэкапа: состояние устройства (`device.*`) и секреты интеграций
// не уходят в JSON и не стираются при восстановлении.

const _deviceState = {
  'device.integrations': '{"enabled":true,"tasker":true}',
  'device.integrations.idempotency': '{"evt-1":1700000000}',
  'device.webhooks.queue': '[{"id":"evt-2"}]',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('JSON бэкапа не содержит ни ключа device.*, ни строк секретов',
      () async {
    SharedPreferences.setMockInitialValues({
      'tasks': jsonEncode([
        {'id': '1', 'title': 'Купить хлеб'},
      ]),
      'goals': jsonEncode([]),
      ..._deviceState,
    });
    final prefs = await SharedPreferences.getInstance();
    final secrets = SecretStore(MemorySecretBackend());
    final tasker = await secrets.taskerKey();
    final webhook = await secrets.webhookSecret('w1');
    expect(tasker, isNotEmpty);
    expect(webhook, isNotEmpty);

    final json = BackupService(LocalStorage(prefs)).buildJson();

    final data = (jsonDecode(json) as Map)['data'] as Map;
    expect(data.keys, containsAll(['tasks', 'goals']));
    expect(
      data.keys.where((k) => k.toString().startsWith(kDeviceKeyPrefix)),
      isEmpty,
    );
    expect(json, isNot(contains('"device.')));
    expect(json, isNot(contains(tasker)));
    expect(json, isNot(contains(webhook)));
  });

  test('restore(clear: true) не трогает device.*, обычные восстанавливает',
      () async {
    SharedPreferences.setMockInitialValues({
      'tasks': jsonEncode([
        {'id': '1', 'title': 'Исходная задача'},
      ]),
      'goals': jsonEncode([]),
    });
    final prefs = await SharedPreferences.getInstance();
    final storage = LocalStorage(prefs);
    final backup = BackupService(storage);
    final json = backup.buildJson();

    // После снятия бэкапа на устройстве меняется и обычное, и «устройство».
    await prefs.setString('tasks', '[]');
    await prefs.setString(
      'goals',
      jsonEncode([
        {'id': 'g2'},
      ]),
    );
    for (final e in _deviceState.entries) {
      await prefs.setString(e.key, e.value);
    }
    await prefs.setString('device.integrations', '{"enabled":false}');
    await prefs.setString('device.webhooks.queue', '[{"id":"evt-3"}]');

    await backup.restoreFromJson(json);

    expect(storage.readList('tasks').first['title'], 'Исходная задача');
    expect(storage.readList('goals'), isEmpty);
    expect(prefs.getString('device.integrations'), '{"enabled":false}');
    expect(prefs.getString('device.webhooks.queue'), '[{"id":"evt-3"}]');
    expect(
      prefs.getString('device.integrations.idempotency'),
      _deviceState['device.integrations.idempotency'],
    );
  });

  test('бэкап с подложенным device.integrations не перезаписывает его',
      () async {
    const local = '{"enabled":true,"local":1}';
    SharedPreferences.setMockInitialValues({
      'tasks': '[]',
      'device.integrations': local,
    });
    final prefs = await SharedPreferences.getInstance();
    final backup = BackupService(LocalStorage(prefs));

    final forged = jsonEncode({
      'app': 'todo',
      'format': 1,
      'data': {
        'tasks': jsonEncode([
          {'id': '9', 'title': 'Из подложенной копии'},
        ]),
        'device.integrations': '{"enabled":false,"tasker":true}',
      },
    });

    await backup.restoreFromJson(forged);
    expect(prefs.getString('device.integrations'), local);
    expect(prefs.getString('tasks'), contains('Из подложенной копии'));

    await backup.restoreFromJson(forged, clear: false);
    expect(prefs.getString('device.integrations'), local);
  });
}
