import 'package:enitor/data/models/backlog_item.dart';
import 'package:enitor/data/repositories/backlog_repository.dart';
import 'package:enitor/data/repositories/task_repository.dart';
import 'package:enitor/data/sources/local/local_storage.dart';
import 'package:enitor/features/backlog/backlog_screen.dart';
import 'package:enitor/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'integrations/sync/memory_storage.dart';

BacklogItem _item() => BacklogItem(
      id: 'b1',
      title: 'Купить молоко',
      originalDate: DateTime(2026, 1, 5),
      addedAt: DateTime(2026, 1, 5),
    );

/// Экран бэклога задач с одним элементом в хранилище.
Future<ProviderContainer> _pump(WidgetTester tester) async {
  final storage = (await tester.runAsync(MemoryStorage.create))!;
  final container = ProviderContainer(
    overrides: [localStorageProvider.overrideWithValue(storage)],
  );
  addTearDown(container.dispose);
  await container.read(backlogRepositoryProvider).add(_item());

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        locale: Locale('ru'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: TaskBacklogScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  testWidgets('двойной тап по «Выполнить» создаёт ровно одну задачу',
      (tester) async {
    final container = await _pump(tester);

    await tester.tap(find.text('Выполнить'));
    await tester.tap(find.text('Выполнить'));
    await tester.pumpAndSettle();

    expect(container.read(taskRepositoryProvider).allTasks, hasLength(1));
    expect(container.read(backlogRepositoryProvider).all, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('удаление спрашивает подтверждение, «Отмена» оставляет задачу',
      (tester) async {
    final container = await _pump(tester);

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    expect(find.text('Удалить задачу из бэклога?'), findsOneWidget);

    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();

    expect(find.text('Удалить задачу из бэклога?'), findsNothing);
    expect(find.text('Купить молоко'), findsOneWidget);
    expect(container.read(backlogRepositoryProvider).all, hasLength(1));
    expect(tester.takeException(), isNull);
  });
}
