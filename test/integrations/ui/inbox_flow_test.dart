import 'package:enitor/core/current_time_provider.dart';
import 'package:enitor/data/repositories/schedule_repository.dart';
import 'package:enitor/data/repositories/task_repository.dart';
import 'package:enitor/data/sources/local/local_storage.dart';
import 'package:enitor/features/integrations/core/command_handler.dart';
import 'package:enitor/features/integrations/core/integration_command.dart';
import 'package:enitor/features/integrations/core/integration_gateway.dart';
import 'package:enitor/features/integrations/core/integration_settings.dart';
import 'package:enitor/features/integrations/inbox/command_inbox.dart';
import 'package:enitor/features/integrations/inbox/inbox_host.dart';
import 'package:enitor/features/today/today_screen.dart';
import 'package:enitor/l10n/app_localizations.dart';
import 'package:enitor/services/notification_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ui_matrix.dart';

// Сквозные тесты этапа 1: вход → приёмная → анкета «Добавить?» (или
// обработчик) → данные → экран.

void main() {
  late ProviderContainer container;

  setUp(() async {
    await initializeDateFormatting('ru');
    await initializeDateFormatting('en');
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    container = ProviderContainer(
      overrides: [
        localStorageProvider.overrideWithValue(LocalStorage(prefs)),
        notificationServiceProvider.overrideWithValue(NotificationService()),
        currentTimeProvider.overrideWith((ref) => Stream.value(DateTime.now())),
      ],
    );
  });
  tearDown(() => container.dispose());

  Future<void> pumpHost(WidgetTester tester, {Widget? body}) async {
    tester.view.physicalSize = const Size(420, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: const Locale('ru'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: InboxHost(child: body ?? const Scaffold()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  IntegrationGateway gateway() => container.read(integrationGatewayProvider);
  List<String> titles() =>
      container.read(taskRepositoryProvider).allTasks.map((t) => t.title).toList();

  testWidgets('ссылка → анкета заполнена → «Добавить» → задача и тост',
      (tester) async {
    await pumpHost(tester);
    gateway().receiveLink(
      'enitor://add?title=Позвонить%20маме&desc=Про%20выходные'
      '&start=18:00&end=18:30&priority=high&tags=семья&utm_source=x',
    );
    await tester.pumpAndSettle();

    expect(find.text('из ссылки'), findsOneWidget);
    expect(find.text('Незнакомые поля пропущены: utm_source'), findsOneWidget);
    expect(find.text('Позвонить маме'), findsOneWidget);
    expect(find.text('Про выходные'), findsOneWidget);
    expect(find.textContaining('18:00'), findsOneWidget);
    expect(titles(), isEmpty, reason: 'до «Добавить» ничего не создано');

    await tester.tap(find.text('Добавить'));
    await tester.pumpAndSettle();
    final t = container.read(taskRepositoryProvider).allTasks.single;
    expect(t.title, 'Позвонить маме');
    expect(t.description, 'Про выходные');
    expect(t.startMinutes, 18 * 60);
    expect(t.endMinutes, 18 * 60 + 30);
    expect(t.tags, ['семья']);
    expect(find.text('Добавлено'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  });

  testWidgets('отмена — ничего не создано', (tester) async {
    await pumpHost(tester);
    gateway().receiveLink('enitor://add?title=Молоко');
    await tester.pumpAndSettle();
    expect(find.text('Молоко'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Молоко'), findsNothing);
    expect(titles(), isEmpty);
    expect(container.read(commandInboxProvider), isEmpty);
  });

  testWidgets('три ссылки подряд — по одной анкете, «ещё N ждут»',
      (tester) async {
    await pumpHost(tester);
    gateway()
      ..receiveLink('enitor://add?title=Первая')
      ..receiveLink('enitor://add?title=Вторая')
      ..receiveLink('enitor://add?title=Третья');
    await tester.pumpAndSettle();
    expect(find.text('Первая'), findsOneWidget);
    expect(find.text('Вторая'), findsNothing);
    expect(find.text('ещё 2 ждут'), findsOneWidget);

    await tester.tap(find.text('Добавить'));
    await tester.pumpAndSettle();
    expect(find.text('Вторая'), findsOneWidget);
    expect(find.text('ещё 1 ждёт'), findsOneWidget);

    // Пока открыта вторая, приходит четвёртая — набранное во второй не
    // теряется.
    await tester.enterText(find.byType(TextField).first, 'Вторая правка');
    gateway().receiveLink('enitor://add?title=Четвёртая');
    await tester.pumpAndSettle();
    expect(find.text('Вторая правка'), findsOneWidget);
    expect(find.text('ещё 2 ждут'), findsOneWidget);

    await tester.tap(find.text('Добавить'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Добавить'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Добавить'));
    await tester.pumpAndSettle();
    expect(titles(), ['Первая', 'Вторая правка', 'Третья', 'Четвёртая']);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  });

  testWidgets('«Поделиться» → анкета с пометкой и описанием', (tester) async {
    await pumpHost(tester);
    gateway().receiveShare('Статья про сон\nhttps://example.com/sleep');
    await tester.pumpAndSettle();
    expect(find.text('из «Поделиться»'), findsOneWidget);
    expect(find.text('https://example.com/sleep'), findsOneWidget);
    await tester.tap(find.text('Добавить'));
    await tester.pumpAndSettle();
    final t = container.read(taskRepositoryProvider).allTasks.single;
    expect(t.description, 'https://example.com/sleep');
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  });

  testWidgets('ссылка на расписание → анкета пункта → пункт', (tester) async {
    await pumpHost(tester);
    gateway().receiveLink(
      'enitor://schedule?title=Физика&start=09:00&end=10:30&location=214',
    );
    await tester.pumpAndSettle();
    expect(find.text('Физика'), findsOneWidget);
    expect(find.text('214'), findsOneWidget);
    await tester.tap(find.text('Добавить'));
    await tester.pumpAndSettle();
    final item = container.read(scheduleRepositoryProvider).all.single;
    expect(item.startMinutes, 9 * 60);
    expect(item.endMinutes, 10 * 60 + 30);
    expect(item.location, '214');
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  });

  testWidgets('битая ссылка и пустой «Поделиться» — спокойный тост',
      (tester) async {
    await pumpHost(tester);
    gateway().receiveLink('enitor://launch-missiles');
    await tester.pump();
    expect(find.text('Ссылка не распознана — проверь адрес'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    gateway().receiveShare('   ');
    await tester.pump();
    expect(find.text('Нечего добавить — пришёл пустой текст'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(titles(), isEmpty);
  });

  testWidgets('команда из JSON → обработчик → задача видна на «Сегодня»',
      (tester) async {
    await container
        .read(integrationSettingsProvider.notifier)
        .setPermission(CommandSource.cli, const SourcePermission(add: true));
    final reply = await container.read(commandHandlerProvider).execute(
          parseJsonCommand(
            '{"command":"add_task","args":{"title":"Из консоли"}}',
            source: CommandSource.cli,
            now: DateTime.now(),
          ).command!,
        );
    expect(reply.ok, isTrue);
    await pumpHost(tester, body: const TodayScreen());
    expect(find.text('Из консоли'), findsOneWidget);
  });

  group('шапка анкеты', () {
    final cmd = parseLink(
      'enitor://add?title=Очень%20длинное%20название&ref=a&utm_campaign=b',
      now: DateTime(2026, 10, 25, 12),
    ).command!;

    uiMatrixTest(
      'UI-матрица: шапка с предупреждением',
      () => UncontrolledProviderScope(
        container: ProviderContainer(),
        child: ConfirmHeader(command: cmd),
      ),
    );
  });
}
