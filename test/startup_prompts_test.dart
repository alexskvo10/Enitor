import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:enitor/data/models/day_stats.dart';
import 'package:enitor/data/models/goal.dart';
import 'package:enitor/data/models/task.dart';
import 'package:enitor/l10n/app_localizations.dart';
import 'package:enitor/widgets/transfer_catchup_sheet.dart';
import 'package:enitor/widgets/weekly_retro_sheet.dart';

// В понедельник может совпасть всё сразу: догоняющий перенос (граница 4:00
// прошла без приложения), разбор недели и авто-проверка обновлений. В роутере
// они выстроены в очередь через await — здесь проверяем, что очередь и правда
// очередь, а не стопка диалогов друг на друге.

final _week = DateTime(2026, 1, 5);

WeeklyRetroData _data() => WeeklyRetroData.build(
      weekStart: _week,
      allStats: [
        for (var i = 0; i < 5; i++)
          DayStats(
            date: _week.add(Duration(days: i)),
            totalTasks: 4,
            completedTasks: 3,
            onTimeCount: 3,
            updatedAt: _week,
          ),
      ],
      goals: const [],
      ratings: const {},
      tasks: const [],
    );

Task _task(int i) => Task(
      id: 't$i',
      title: 'Вчерашняя задача $i',
      date: _week,
      createdAt: _week,
      updatedAt: _week,
    );

void main() {
  testWidgets('перенос и разбор недели идут по очереди, а не стопкой',
      (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    var updateChecked = false;

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ru'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                // Та же последовательность, что в _runStartupPrompts.
                onPressed: () async {
                  await showTransferCatchupSheet(
                    context,
                    tasks: [for (var i = 0; i < 3; i++) _task(i)],
                    goals: const <Goal>[],
                  );
                  if (!context.mounted) return;
                  await showWeeklyRetroSheet(context, data: _data());
                  updateChecked = true;
                },
                child: const Text('start'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('start'));
    await tester.pumpAndSettle();

    // Первый — перенос. Разбора недели ещё нет, диалоги не наложились.
    expect(find.text('Перенести невыполненное?'), findsOneWidget);
    expect(find.text('Итоги недели'), findsNothing);
    expect(updateChecked, isFalse);

    // Закрываем перенос отказом — второй диалог обязан появиться сам.
    await tester.tap(find.text('Не переносить'));
    await tester.pumpAndSettle();
    expect(find.text('Перенести невыполненное?'), findsNothing);
    expect(find.text('Итоги недели'), findsOneWidget);
    expect(updateChecked, isFalse);

    // И только после закрытия разбора очередь идёт дальше (обновления).
    await tester.tap(find.text('Закрыть'));
    await tester.pumpAndSettle();
    expect(find.text('Итоги недели'), findsNothing);
    expect(updateChecked, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('закрытие переноса по Esc не проглатывает разбор недели',
      (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ru'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  await showTransferCatchupSheet(
                    context,
                    tasks: [_task(0)],
                    goals: const <Goal>[],
                  );
                  if (!context.mounted) return;
                  await showWeeklyRetroSheet(context, data: _data());
                },
                child: const Text('start'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('start'));
    await tester.pumpAndSettle();
    expect(find.text('Перенести невыполненное?'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Итоги недели'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
