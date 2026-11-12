import 'dart:convert';

import 'package:enitor/core/utils/date_utils.dart';
import 'package:enitor/data/models/task.dart';
import 'package:enitor/data/repositories/task_repository.dart';
import 'package:enitor/data/sources/local/local_storage.dart';
import 'package:enitor/features/integrations/core/integration_command.dart';
import 'package:enitor/features/integrations/core/integration_gateway.dart';
import 'package:enitor/features/integrations/widget/day_snapshot.dart';
import 'package:enitor/l10n/app_localizations.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Снимок для виджета «Сегодня»: верен для пустого дня, полного, после 00:00
// и после 4:00; галочка на виджете (команда источника widget) отмечает задачу
// и обновляет снимок.

Task _task(String id, DateTime day, {bool done = false, int? start}) {
  final at = DateTime(2026, 10, 25);
  return Task(
    id: id,
    title: 'Задача $id',
    date: day,
    createdAt: at,
    updatedAt: at,
    completedAt: done ? at : null,
    startMinutes: start,
  );
}

void main() {
  setUpAll(() => initializeDateFormatting('ru'));
  final l10n = lookupAppLocalizations(const Locale('ru'));
  final d25 = DateTime(2026, 10, 25);
  final d26 = DateTime(2026, 10, 26);

  Map<String, Object?> snap(List<Task> tasks, DateTime now) =>
      buildWidgetSnapshot(
        tasksForDay: (d) => tasks.where((t) => t.date == d).toList(),
        now: now,
        l10n: l10n,
      );

  Map<String, Object?> day(Map<String, Object?> s, String ymd) =>
      ((s['days']! as Map)[ymd]! as Map).cast<String, Object?>();

  test('пустой день — пустой список и подписи на языке приложения', () {
    final s = snap(const [], DateTime(2026, 10, 25, 12));
    expect(s['title'], 'Сегодня');
    expect(s['empty'], l10n.widgetEmpty);
    expect(day(s, '2026-10-25')['tasks'], isEmpty);
    expect(day(s, '2026-10-25')['counter'], '');
  });

  test('полный день: невыполненные первыми, не больше шести, счётчик', () {
    final tasks = [
      _task('a', d25, done: true),
      for (var i = 0; i < 7; i++) _task('b$i', d25, start: 9 * 60 + i),
    ];
    final today = day(snap(tasks, DateTime(2026, 10, 25, 12)), '2026-10-25');
    final list = today['tasks']! as List;
    expect(list.length, kWidgetMaxTasks);
    expect((list.first as Map)['done'], isFalse);
    expect((list.first as Map)['time'], '09:00');
    expect(today['counter'], '1/8');
    expect(today['done'], 1);
    expect(today['total'], 8);
    expect(today['date'], 'вс, 25 октября');
    expect((list.first as Map)['priority'], 'none');
  });

  test('подписи «всё сделано» и «ещё N» — на языке приложения', () {
    final s = snap(const [], DateTime(2026, 10, 25, 12));
    expect(s['allDone'], 'Всё сделано');
    expect((s['more']! as String).replaceAll('%d', '3'), 'ещё 3');
  });

  test('после 00:00 — ещё вчерашний день, после 4:00 — новый', () {
    final tasks = [_task('y', d25), _task('t', d26)];
    final night = snap(tasks, DateTime(2026, 10, 26, 0, 30));
    expect((night['days']! as Map).keys, ['2026-10-25', '2026-10-26']);
    final morning = snap(tasks, DateTime(2026, 10, 26, 4, 0));
    expect((morning['days']! as Map).keys, ['2026-10-26', '2026-10-27']);
    expect(
      ((day(morning, '2026-10-26')['tasks']! as List).single as Map)['id'],
      't',
    );
  });

  test('галочка на виджете → задача выполнена → снимок обновлён', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    final storage = LocalStorage(await SharedPreferences.getInstance());
    final container = ProviderContainer(
      overrides: [localStorageProvider.overrideWithValue(storage)],
    );
    addTearDown(container.dispose);
    // День приложения: до 4:00 виджет показывает ещё вчерашний.
    final now = effectiveDay(DateTime.now());
    final t = await container
        .read(taskRepositoryProvider)
        .createAndAdd(title: 'Полить цветы', date: now);
    final writer = WidgetSnapshotWriter(container);
    await writer.write();

    final out = await container.read(integrationGatewayProvider).receiveCommand(
          jsonEncode({
            'command': 'complete_task',
            'args': {'id': t.id},
          }),
          source: CommandSource.widget,
        );
    expect((jsonDecode(out['reply']! as String) as Map)['ok'], isTrue);
    await writer.write();

    final saved = storage.readMap(kWidgetSnapshotKey)!;
    final days = saved['days'] as Map;
    final today = days.values.first as Map;
    expect(((today['tasks'] as List).single as Map)['done'], isTrue);
    expect(today['counter'], '1/1');
    // Снимок — ключ «устройство»: в бэкап не попадает.
    expect(storage.snapshot().containsKey(kWidgetSnapshotKey), isFalse);
    writer.dispose();
  });
}
