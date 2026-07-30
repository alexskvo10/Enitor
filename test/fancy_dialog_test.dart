import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:enitor/core/theme/app_colors.dart';
import 'package:enitor/data/models/goal.dart';
import 'package:enitor/data/models/task.dart';
import 'package:enitor/l10n/app_localizations.dart';
import 'package:enitor/widgets/fancy_dialog.dart';
import 'package:enitor/widgets/transfer_catchup_sheet.dart';

// FancyDialogCard общий для всех диалогов приложения, и его содержимое теперь
// живёт во Flexible (иначе прокручиваемые диалоги вылезали за экран). Здесь —
// страховка, что от этого не поехали обычные, непрокручиваемые диалоги.

Future<void> _pump(WidgetTester tester, VoidCallback Function(BuildContext) go) {
  return tester.pumpWidget(
    MaterialApp(
      locale: const Locale('ru'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: go(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
}

Task _task(int i) {
  final d = DateTime(2026, 1, 5);
  return Task(
    id: 't$i',
    title: 'Задача с достаточно длинным названием номер $i',
    date: d,
    createdAt: d,
    updatedAt: d,
  );
}

Goal _goal(int i) {
  final d = DateTime(2026, 1, 5);
  return Goal(
    id: 'g$i',
    period: GoalPeriod.week,
    year: 2026,
    weekStart: d,
    title: 'Цель номер $i',
    createdAt: d,
    updatedAt: d,
  );
}

void main() {
  testWidgets('обычный диалог с текстом и кнопками', (tester) async {
    await _pump(
      tester,
      (context) => () => showFancyDialog<bool>(
            context: context,
            icon: Icons.delete_outline,
            iconColor: AppColors.danger,
            title: 'Удалить задачу?',
            content: 'Это действие нельзя отменить. Задача исчезнет насовсем.',
            actions: (ctx) => [
              TextButton(onPressed: () {}, child: const Text('Отмена')),
              FilledButton(onPressed: () {}, child: const Text('Удалить')),
            ],
          ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Удалить задачу?'), findsOneWidget);
    expect(find.text('Удалить'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('диалог без контента и кнопок не схлопывается', (tester) async {
    await _pump(
      tester,
      (context) => () => showFancyDialog<void>(
            context: context,
            icon: Icons.info_outline,
            iconColor: AppColors.primary,
            title: 'Просто сообщение',
          ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Просто сообщение'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('прокручиваемый контент сжимается под низкий экран',
      (tester) async {
    // Форма пикера дня недели из настроек: семь строк под потолком 340 —
    // сами по себе они в 400-пиксельный экран не влезают.
    tester.view.physicalSize = const Size(400, 400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await _pump(
      tester,
      (context) => () => showFancyDialog<int>(
            context: context,
            icon: Icons.event_outlined,
            iconColor: AppColors.primary,
            title: 'День разбора',
            contentBuilder: (ctx) => ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 340),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var d = 1; d <= 7; d++)
                      const Padding(
                        padding: EdgeInsets.all(10),
                        child: SizedBox(height: 24, child: Text('день')),
                      ),
                  ],
                ),
              ),
            ),
            actions: (ctx) => [
              TextButton(onPressed: () {}, child: const Text('Отмена')),
            ],
          ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('День разбора'), findsOneWidget);
    expect(find.text('Отмена'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('догоняющий список переноса на узком экране прокручивается',
      (tester) async {
    // 360x640 — самый маленький реальный телефон. В ландшафте (высота ~360)
    // у этого диалога не помещается уже сама «шапка» с кнопками, независимо
    // от списка, — это отдельная старая история, не про прокрутку.
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await _pump(
      tester,
      (context) => () => showTransferCatchupSheet(
            context,
            tasks: [for (var i = 0; i < 20; i++) _task(i)],
            goals: [for (var i = 0; i < 5; i++) _goal(i)],
          ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Перенести невыполненное?'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
