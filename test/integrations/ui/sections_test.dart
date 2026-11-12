import 'package:enitor/data/sources/local/local_storage.dart';
import 'package:enitor/features/integrations/core/command_journal.dart';
import 'package:enitor/features/integrations/core/secret_store.dart';
import 'package:enitor/features/integrations/import/import_plan.dart';
import 'package:enitor/features/integrations/import/import_preview_screen.dart';
import 'package:enitor/features/integrations/ui/calendar_section.dart';
import 'package:enitor/features/integrations/ui/tasker_section.dart';
import 'package:enitor/features/integrations/ui/webhooks_section.dart';
import 'package:enitor/features/integrations/ui/windows_section.dart';
import 'package:enitor/features/integrations/webhooks/webhooks.dart';
import 'package:enitor/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ui_matrix.dart';

// Разделы экрана «Интеграции» и предпросмотр импорта: поведение и
// UI-матрица (переполнения, цели касания, подписи, контраст).

void main() {
  late ProviderContainer container;
  late MemorySecretBackend secrets;

  setUp(() async {
    await initializeDateFormatting('ru');
    await initializeDateFormatting('en');
    SharedPreferences.setMockInitialValues({});
    secrets = MemorySecretBackend();
    container = ProviderContainer(
      overrides: [
        localStorageProvider.overrideWithValue(
          LocalStorage(await SharedPreferences.getInstance()),
        ),
        secretStoreProvider.overrideWithValue(SecretStore(secrets)),
      ],
    );
  });
  tearDown(() => container.dispose());

  Widget scoped(Widget child) =>
      UncontrolledProviderScope(container: container, child: child);

  Widget app(Widget child) => scoped(
        MaterialApp(
          locale: const Locale('ru'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: child,
        ),
      );

  final applied = <String>[];
  List<PlanEntry> entries() => [
        PlanEntry(
          title: 'Физика',
          action: PlanAction.create,
          date: DateTime(2026, 10, 26),
          startMinutes: 540,
          endMinutes: 630,
          repeats: true,
          apply: () async => applied.add('Физика'),
        ),
        PlanEntry(
          title: 'История',
          action: PlanAction.update,
          date: DateTime(2026, 10, 30),
          apply: () async => applied.add('История'),
        ),
        const PlanEntry(
          title: 'День здоровья',
          action: PlanAction.skip,
          skip: PlanSkip.allDay,
        ),
      ];

  group('предпросмотр импорта', () {
    setUp(applied.clear);

    testWidgets('снять флажок → импортируется только выбранное',
        (tester) async {
      await tester.pumpWidget(
        app(ImportPreviewScreen(title: 'Импорт', entries: entries())),
      );
      await tester.pumpAndSettle();
      expect(find.text('Импортировать 2'), findsOneWidget);
      expect(find.textContaining('событие на весь день'), findsOneWidget);
      expect(find.textContaining('будет обновлён'), findsOneWidget);
      await tester.tap(find.text('История'));
      await tester.pumpAndSettle();
      expect(find.text('Импортировать 1'), findsOneWidget);
      await tester.tap(find.text('Импортировать 1'));
      await tester.pumpAndSettle();
      expect(applied, ['Физика']);
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('пропущенное не выбирается', (tester) async {
      await tester.pumpWidget(
        app(ImportPreviewScreen(title: 'Импорт', entries: entries())),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('День здоровья'));
      await tester.pumpAndSettle();
      expect(find.text('Импортировать 2'), findsOneWidget);
    });

    testWidgets('пустой и нечитаемый файл — спокойный текст', (tester) async {
      await tester.pumpWidget(
        app(const ImportPreviewScreen(title: 'Импорт', entries: [])),
      );
      await tester.pumpAndSettle();
      expect(find.text('В этом файле нечего импортировать'), findsOneWidget);
      await tester.pumpWidget(
        app(
          const ImportPreviewScreen(
            title: 'Импорт',
            entries: [],
            warningsCount: 3,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('не получилось прочитать'), findsOneWidget);
    });

    uiMatrixTest(
      'UI-матрица: список',
      () => ImportPreviewScreen(title: 'Импорт', entries: entries()),
    );
    uiMatrixTest(
      'UI-матрица: пусто',
      () => const ImportPreviewScreen(title: 'Импорт', entries: []),
    );
  });

  group('вебхуки', () {
    testWidgets('добавить адрес: неверный отклонён, верный сохранён',
        (tester) async {
      await tester.pumpWidget(
        app(const Scaffold(body: SingleChildScrollView(child: WebhooksSection()))),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Добавить адрес'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'not a url');
      await tester.tap(find.text('Сохранить'));
      await tester.pumpAndSettle();
      expect(find.text('Это не похоже на адрес — проверь его'), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
      await tester.enterText(find.byType(TextField), 'https://n8n.local/hook');
      await tester.tap(find.text('Сохранить'));
      await tester.pumpAndSettle();
      final eps = container.read(webhookServiceProvider).endpoints;
      expect(eps.single.url, 'https://n8n.local/hook');
      expect(eps.single.events.length, 3);
      expect(find.text('https://n8n.local/hook'), findsOneWidget);
      // Секрет создан и лежит в защищённом хранилище, не в настройках.
      expect(secrets.values.keys.single, startsWith('webhook_secret.'));
    });

    testWidgets('http:// — только после предупреждения', (tester) async {
      await tester.pumpWidget(
        app(const Scaffold(body: SingleChildScrollView(child: WebhooksSection()))),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Добавить адрес'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'http://192.168.1.5/hook');
      await tester.tap(find.text('Сохранить'));
      await tester.pumpAndSettle();
      expect(find.text('Незащищённая ссылка'), findsOneWidget);
      await tester.tap(find.text('Отмена'));
      await tester.pumpAndSettle();
      expect(container.read(webhookServiceProvider).endpoints, isEmpty);
    });

    testWidgets('удаление стирает адрес и его секрет', (tester) async {
      await container.read(webhookServiceProvider).saveEndpoints([
        const WebhookEndpoint(
          id: 'w1',
          url: 'https://a.example/h',
          events: {WebhookEvent.taskCompleted},
        ),
      ]);
      await container.read(secretStoreProvider).webhookSecret('w1');
      await tester.pumpWidget(
        app(const Scaffold(body: SingleChildScrollView(child: WebhooksSection()))),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('https://a.example/h'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Удалить'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Удалить').last);
      await tester.pumpAndSettle();
      expect(container.read(webhookServiceProvider).endpoints, isEmpty);
      expect(secrets.values, isEmpty);
    });

    uiMatrixTest(
      'UI-матрица: раздел с адресом и журналом',
      () => scoped(const SingleChildScrollView(child: WebhooksSection())),
      allowedEllipsis: {'https://very-long-host.example.com/hooks/enitor/abc'},
    );
  });

  group('Tasker', () {
    testWidgets('ключ скрыт, показывается и перевыпускается', (tester) async {
      await tester.pumpWidget(
        app(const Scaffold(body: SingleChildScrollView(child: TaskerSection()))),
      );
      await tester.pumpAndSettle();
      final key = secrets.values['tasker_key']!;
      expect(find.text(key), findsNothing);
      await tester.tap(find.text('Показать'));
      await tester.pumpAndSettle();
      expect(find.text(key), findsOneWidget);
      await tester.tap(find.text('Новый ключ'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Выпустить'));
      await tester.pumpAndSettle();
      expect(secrets.values['tasker_key'], isNot(key));
      expect(find.text(secrets.values['tasker_key']!), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
    });

    uiMatrixTest(
      'UI-матрица: раздел Tasker',
      () => scoped(const SingleChildScrollView(child: TaskerSection())),
    );
  });

  group('Windows и календари', () {
    uiMatrixTest(
      'UI-матрица: Windows',
      () => scoped(const SingleChildScrollView(child: WindowsSection())),
    );
    testWidgets('журнал ассистента: пусто и с записями', (tester) async {
      await tester.pumpWidget(
        app(
          const Scaffold(body: SingleChildScrollView(child: AssistantsSection())),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Ассистент ещё ничего не вызывал'), findsOneWidget);
      await container.read(mcpLogProvider.notifier).add(
            McpLogEntry(
              at: DateTime(2026, 10, 25, 9),
              command: 'add_task',
              ok: true,
              detail: 'Молоко',
            ),
          );
      await tester.pumpAndSettle();
      expect(find.text('add_task · Молоко'), findsOneWidget);
    });
    uiMatrixTest(
      'UI-матрица: ассистенты',
      () => scoped(const SingleChildScrollView(child: AssistantsSection())),
    );
    uiMatrixTest(
      'UI-матрица: календари',
      () => scoped(const SingleChildScrollView(child: CalendarSection())),
    );
  });
}
