import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:enitor/data/repositories/task_repository.dart';
import 'package:enitor/data/sources/local/local_storage.dart';
import 'package:enitor/services/notification_prefs.dart';
import 'package:enitor/services/notification_service.dart';

/// Когда уведомление может прийти: тихие часы и задачи только с «До».
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('время, выбранное приложением, обходит тихие часы', () {
    const prefs = NotificationPrefs(); // 23:00–08:00
    tz.TZDateTime at(int d, int h, [int m = 0]) =>
        tz.TZDateTime(tz.UTC, 2026, 3, d, h, m);

    test('вне тихих часов — без сдвига', () {
      expect(shiftOutOfQuiet(at(10, 22, 59), prefs), at(10, 22, 59));
      expect(shiftOutOfQuiet(at(10, 9), prefs), at(10, 9));
    });

    test('23:00 и полночь — на 8:00 следующего утра', () {
      expect(shiftOutOfQuiet(at(10, 23), prefs), at(11, 8));
      expect(shiftOutOfQuiet(at(11, 0), prefs), at(11, 8));
      expect(shiftOutOfQuiet(at(11, 7, 59), prefs), at(11, 8));
    });

    test('выключенные тихие часы ничего не сдвигают', () {
      const off = NotificationPrefs(quietHoursEnabled: false);
      expect(shiftOutOfQuiet(at(10, 23), off), at(10, 23));
    });

    test('окно внутри суток (13:00–15:00)', () {
      const day = NotificationPrefs(quietStart: 13 * 60, quietEnd: 15 * 60);
      expect(shiftOutOfQuiet(at(10, 14), day), at(10, 15));
      expect(shiftOutOfQuiet(at(10, 15), day), at(10, 15));
    });
  });

  test('задача только с «До» попадает в напоминания', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final c = ProviderContainer(overrides: [
      localStorageProvider.overrideWithValue(LocalStorage(prefs)),
    ],);
    addTearDown(c.dispose);
    final tasks = c.read(taskRepositoryProvider);
    final today = DateTime.now();
    await tasks.createAndAdd(title: 'до', date: today, endMinutes: 18 * 60);
    await tasks.createAndAdd(title: 'без времени', date: today);
    await tasks.createAndAdd(
      title: 'от',
      date: today,
      startMinutes: 9 * 60,
    );

    expect(
      tasks.timedTasks().map((t) => t.title),
      ['от', 'до'],
    );
  });
}
