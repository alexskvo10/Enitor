@Tags(['golden'])
library;

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
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'golden_helpers.dart';

// Снимки разделов «Интеграций» и предпросмотра импорта: светлая и тёмная
// тема, 412 и 900, ru; плюс en на 412. Состояния: пустое и заполненное.

const _points = [
  (false, 412.0, Locale('ru')),
  (true, 412.0, Locale('ru')),
  (false, 900.0, Locale('ru')),
  (true, 900.0, Locale('ru')),
  (false, 412.0, Locale('en')),
];

final _plan = [
  PlanEntry(
    title: 'Физика',
    action: PlanAction.create,
    date: DateTime(2026, 10, 26),
    startMinutes: 540,
    endMinutes: 630,
    repeats: true,
    apply: () async {},
  ),
  PlanEntry(
    title: 'История',
    action: PlanAction.update,
    date: DateTime(2026, 10, 30),
    startMinutes: 720,
    apply: () async {},
  ),
  const PlanEntry(
    title: 'День здоровья',
    action: PlanAction.skip,
    skip: PlanSkip.allDay,
  ),
];

void main() {
  late ProviderContainer container;

  setUp(() async {
    await initializeDateFormatting('ru');
    await initializeDateFormatting('en');
    SharedPreferences.setMockInitialValues({});
    final secrets = MemorySecretBackend()
      ..values['tasker_key'] = 'k3Y-ex4mple-NOT-real-5ecret-v4lue-0123456'
      ..values['webhook_secret.w1'] = 'wh-ex4mple-secret';
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

  Future<void> fill() async {
    final hooks = container.read(webhookServiceProvider);
    await hooks.saveEndpoints([
      const WebhookEndpoint(
        id: 'w1',
        url: 'https://n8n.home.lan/webhook/enitor',
        events: {WebhookEvent.taskCompleted, WebhookEvent.dayClosed},
      ),
    ]);
    final at = DateTime(2026, 10, 25, 18, 30);
    await container.read(localStorageProvider).writeList(kWebhookQueueKey, [
      WebhookDelivery(
        id: 'd1',
        endpointId: 'w1',
        eventId: 'e1',
        type: WebhookEvent.taskCompleted,
        body: '{}',
        createdAt: at,
        nextAt: at,
        attempts: 1,
        status: DeliveryStatus.delivered,
        lastCode: 200,
      ).toJson(),
      WebhookDelivery(
        id: 'd2',
        endpointId: 'w1',
        eventId: 'e2',
        type: WebhookEvent.dayClosed,
        body: '{}',
        createdAt: at,
        nextAt: at.add(const Duration(minutes: 5)),
        attempts: 1,
        lastCode: 0,
      ).toJson(),
    ]);
    await container.read(mcpLogProvider.notifier).add(
          McpLogEntry(at: at, command: 'add_task', ok: true, detail: 'Молоко'),
        );
  }

  final screens = <String, Widget Function()>{
    'preview-list': () => ImportPreviewScreen(title: 'Импорт', entries: _plan),
    'preview-empty': () =>
        const ImportPreviewScreen(title: 'Импорт', entries: []),
    'webhooks': () => const SingleChildScrollView(child: WebhooksSection()),
    'tasker': () => const SingleChildScrollView(child: TaskerSection()),
    'windows': () => const SingleChildScrollView(child: WindowsSection()),
    'assistants': () => const SingleChildScrollView(child: AssistantsSection()),
    'calendars': () => const SingleChildScrollView(child: CalendarSection()),
  };

  for (final MapEntry(key: name, value: build) in screens.entries) {
    for (final (dark, width, locale) in _points) {
      testWidgets(name, (tester) async {
        if (name != 'preview-empty') await fill();
        await expectGoldenScreen(
          tester,
          UncontrolledProviderScope(container: container, child: build()),
          name: 'section-$name',
          dark: dark,
          width: width,
          locale: locale,
        );
      });
    }
  }
}
