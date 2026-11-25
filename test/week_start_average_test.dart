import 'package:enitor/core/utils/date_utils.dart';
import 'package:enitor/data/models/day_stats.dart';
import 'package:enitor/data/repositories/stats_repository.dart';
import 'package:enitor/data/sources/local/local_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

DayStats _day(DateTime d, int done, int total) => DayStats(
      date: d,
      totalTasks: total,
      completedTasks: done,
      onTimeCount: done,
      updatedAt: d,
    );

void main() {
  // База «за неделю» — средние по дням до понедельника. Считается из
  // статистики дней (она синхронизируется), а не запоминается при запуске:
  // иначе у каждого устройства своя база и свой процент.
  test('база недели — только дни до понедельника', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = LocalStorage(await SharedPreferences.getInstance());
    final monday = startOfWeek(today());
    await storage.writeList('day_stats', [
      _day(addDays(monday, -2), 1, 1).toJson(), // 100 %
      _day(addDays(monday, -1), 0, 2).toJson(), // 0 %
      _day(today(), 1, 4).toJson(), // эта неделя: 25 %
    ]);
    final repo = StatsRepository(storage);

    expect(await repo.watchAverageBeforeThisWeek().first, 0.5);
    expect(await repo.watchAverageAllTime().first, closeTo(1.25 / 3, 1e-9));
    // Своевременность: в воскресенье выполненных нет — день не считается.
    expect(await repo.watchOnTimeAverageBeforeThisWeek().first, 1.0);
  });

  test('до этой недели данных нет — базы нет', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = LocalStorage(await SharedPreferences.getInstance());
    await storage.writeList('day_stats', [_day(today(), 1, 2).toJson()]);
    final repo = StatsRepository(storage);
    expect(await repo.watchAverageBeforeThisWeek().first, isNull);
  });
}
