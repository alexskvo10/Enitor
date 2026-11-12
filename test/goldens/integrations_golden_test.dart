@Tags(['golden'])
library;

import 'package:enitor/data/sources/local/local_storage.dart';
import 'package:enitor/features/integrations/core/integration_command.dart';
import 'package:enitor/features/integrations/inbox/command_inbox.dart';
import 'package:enitor/features/integrations/inbox/inbox_host.dart';
import 'package:enitor/features/integrations/ui/integrations_screen.dart';
import 'package:enitor/features/integrations/ui/sync_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'golden_helpers.dart';

// Снимки новых экранов интеграций: светлая и тёмная тема, 412 и 900, ru;
// плюс en на 412. Запуск: flutter test --tags golden.

/// Сочетания из плана (A.5).
const _points = [
  (false, 412.0, Locale('ru')),
  (true, 412.0, Locale('ru')),
  (false, 900.0, Locale('ru')),
  (true, 900.0, Locale('ru')),
  (false, 412.0, Locale('en')),
];

void main() {
  late ProviderContainer container;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    container = ProviderContainer(
      overrides: [localStorageProvider.overrideWithValue(LocalStorage(prefs))],
    );
  });
  tearDown(() => container.dispose());

  for (final platform in [TargetPlatform.android, TargetPlatform.windows]) {
    for (final (dark, width, locale) in _points) {
      testWidgets('integrations-${platform.name}', (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        try {
          await expectGoldenScreen(
            tester,
            UncontrolledProviderScope(
              container: container,
              child: const IntegrationsScreen(),
            ),
            name: 'integrations-${platform.name}',
            dark: dark,
            width: width,
            locale: locale,
          );
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });
    }
  }

  // Экран «Синхронизация» без группы и без сервера — каким его видят впервые.
  for (final (dark, width, locale) in _points) {
    testWidgets('sync-screen', (tester) async {
      await expectGoldenScreen(
        tester,
        UncontrolledProviderScope(
          container: container,
          child: const SyncScreen(),
        ),
        name: 'sync-screen',
        dark: dark,
        width: width,
        locale: locale,
      );
    });
  }

  final link = parseLink(
    'enitor://add?title=Позвонить&utm_source=site',
    now: DateTime(2026, 10, 25, 12),
  ).command!;
  final share = parseSharedText('Статья', now: DateTime(2026, 10, 25, 12))
      .command!;
  for (final (name, cmd) in [('confirm-link', link), ('confirm-share', share)]) {
    for (final (dark, width, locale) in _points) {
      testWidgets(name, (tester) async {
        await expectGoldenScreen(
          tester,
          UncontrolledProviderScope(
            container: container,
            child: Card(child: ConfirmHeader(command: cmd)),
          ),
          name: name,
          dark: dark,
          width: width,
          locale: locale,
        );
      });
    }
  }
}
