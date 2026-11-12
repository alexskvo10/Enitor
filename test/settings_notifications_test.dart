import 'package:enitor/data/sources/local/local_storage.dart';
import 'package:enitor/features/integrations/core/secret_store.dart';
import 'package:enitor/features/settings/settings_screen.dart';
import 'package:enitor/l10n/app_localizations.dart';
import 'package:enitor/services/notification_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Уведомления вынесены из настроек на свой экран: в настройках — одна
// строка со сводкой, по нажатию — экран со всеми видами и тихими часами.

void main() {
  testWidgets('строка «Уведомления» ведёт на свой экран', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer(
      overrides: [
        localStorageProvider.overrideWithValue(
          LocalStorage(await SharedPreferences.getInstance()),
        ),
        secretStoreProvider
            .overrideWithValue(SecretStore(MemorySecretBackend())),
        notificationServiceProvider.overrideWithValue(NotificationService()),
      ],
    );
    addTearDown(container.dispose);
    final router = GoRouter(
      initialLocation: '/settings',
      routes: [
        GoRoute(
          path: '/settings',
          builder: (_, __) => const SettingsScreen(),
          routes: [
            GoRoute(
              path: 'notifications',
              builder: (_, __) => const NotificationSettingsScreen(),
            ),
          ],
        ),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          locale: const Locale('ru'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // В самих настройках переключателей уведомлений больше нет.
    expect(find.text('Тихие часы'), findsNothing);
    final summary =
        find.textContaining(RegExp(r'^(Включено \d+ из 15|Выключены)$'));
    await tester.scrollUntilVisible(summary, 200);
    expect(summary, findsOneWidget);

    await tester.tap(summary);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Уведомления'), findsOneWidget);
    expect(find.text('Напоминать о задачах'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Тихие часы'), 300);
    expect(find.text('Тихие часы'), findsOneWidget);
  });
}
