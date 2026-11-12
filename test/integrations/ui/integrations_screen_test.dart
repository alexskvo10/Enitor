import 'package:enitor/data/sources/local/local_storage.dart';
import 'package:enitor/features/integrations/core/integration_command.dart';
import 'package:enitor/features/integrations/core/integration_settings.dart';
import 'package:enitor/features/integrations/core/secret_store.dart';
import 'package:enitor/features/integrations/ui/integrations_screen.dart';
import 'package:enitor/features/integrations/ui/permissions_section.dart';
import 'package:enitor/l10n/app_localizations.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ui_matrix.dart';

// Экран «Интеграции» и раздел «Права»: переключатели сохраняются, чтение
// включается только через диалог, отмена диалога оставляет выключенным.

void main() {
  late ProviderContainer container;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    container = ProviderContainer(
      overrides: [
        localStorageProvider.overrideWithValue(LocalStorage(prefs)),
        secretStoreProvider
            .overrideWithValue(SecretStore(MemorySecretBackend())),
      ],
    );
  });
  tearDown(() {
    container.dispose();
    debugDefaultTargetPlatformOverride = null;
  });

  Widget wrap(Widget child) => UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: const Locale('ru'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: child,
        ),
      );

  // Экран длинный, «Права» — ниже первого экрана: высокое окно, чтобы
  // ListView построил все разделы.
  void tall(WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 6000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  SourcePermission perm(CommandSource s) =>
      container.read(integrationSettingsProvider).of(s);

  testWidgets('Windows: переключатель «добавлять» сохраняется в хранилище',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    tall(tester);
    await tester.pumpWidget(wrap(const IntegrationsScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Консоль'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(PermissionsSection),
        matching: find.text('ИИ-ассистенты'),
      ),
      findsOneWidget,
    );
    expect(find.text('Tasker'), findsNothing);

    await tester.tap(find.text('Консоль'));
    await tester.pumpAndSettle();
    expect(perm(CommandSource.cli).add, isTrue);
    final saved = container
        .read(localStorageProvider)
        .readMap(kIntegrationSettingsKey)!;
    expect((saved['permissions'] as Map)['cli'], {'add': true, 'read': false});
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('чтение — только через диалог; отмена оставляет выключенным',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    tall(tester);
    await tester.pumpWidget(wrap(const IntegrationsScreen()));
    await tester.pumpAndSettle();
    final readSwitches = find.text('Читать план на день');
    // Вторая строка «читать» — у ИИ-ассистентов.
    await tester.ensureVisible(readSwitches.last);
    await tester.tap(readSwitches.last);
    await tester.pumpAndSettle();
    expect(find.textContaining('уйдут в модель'), findsOneWidget);
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
    expect(perm(CommandSource.mcp).read, isFalse);

    await tester.tap(readSwitches.last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Разрешить чтение'));
    await tester.pumpAndSettle();
    expect(perm(CommandSource.mcp).read, isTrue);

    // Выключение — без вопросов.
    await tester.tap(readSwitches.last);
    await tester.pumpAndSettle();
    expect(perm(CommandSource.mcp).read, isFalse);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Android: ссылки и «Поделиться» включены, Tasker выключен',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    tall(tester);
    await tester.pumpWidget(wrap(const IntegrationsScreen()));
    await tester.pumpAndSettle();
    final switches = tester
        .widgetList<SwitchListTile>(
          find.descendant(
            of: find.byType(PermissionsSection),
            matching: find.byType(SwitchListTile),
          ),
        )
        .toList();
    expect(switches.map((s) => s.value), [true, true, false, false]);
    debugDefaultTargetPlatformOverride = null;
  });

  group('UI-матрица', () {
    for (final platform in [TargetPlatform.android, TargetPlatform.windows]) {
      testWidgets('раздел «Права» (${platform.name})', (tester) async {
        // Переопределение платформы снимаем внутри теста: биндинг проверяет
        // отладочные переменные до tearDown.
        debugDefaultTargetPlatformOverride = platform;
        try {
          await runUiMatrix(
            tester,
            () => UncontrolledProviderScope(
              container: container,
              child: const SingleChildScrollView(child: PermissionsSection()),
            ),
          );
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });
    }
  });

  test('SecretStore: ключ создаётся один раз, перевыпуск меняет, сравнение',
      () async {
    final backend = MemorySecretBackend();
    final store = SecretStore(backend);
    final a = await store.taskerKey();
    expect(await store.taskerKey(), a);
    expect(a.length, greaterThanOrEqualTo(43));
    expect(await store.checkTaskerKey(a), isTrue);
    expect(await store.checkTaskerKey('${a}x'), isFalse);
    final b = await store.rotateTaskerKey();
    expect(b, isNot(a));
    expect(await store.checkTaskerKey(a), isFalse);
    await store.deleteAll();
    expect(backend.values, isEmpty);
    expect(await store.checkTaskerKey(b), isFalse);
    expect(constantTimeEquals('abc', 'abc'), isTrue);
    expect(constantTimeEquals('abc', 'abd'), isFalse);
    expect(constantTimeEquals('abc', 'ab'), isFalse);
    expect(constantTimeEquals('', ''), isTrue);
  });
}
