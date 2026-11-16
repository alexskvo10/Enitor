@Tags(['golden'])
library;

// Картинки для заметок к релизу и README: новые экраны на выдуманных данных
// (личные задачи в публичный репозиторий не попадают). Не часть набора
// тестов — запускается руками:
//
//   flutter test tool/release_shots/shots_test.dart --update-goldens
//
// PNG ложатся в tool/release_shots/out/.

import 'package:enitor/core/current_time_provider.dart';
import 'package:enitor/core/theme/app_theme.dart';
import 'package:enitor/core/theme/appearance.dart';
import 'package:enitor/data/sources/local/local_storage.dart';
import 'package:enitor/features/focus/focus_screen.dart';
import 'package:enitor/features/integrations/core/secret_store.dart';
import 'package:enitor/features/integrations/import/import_plan.dart';
import 'package:enitor/features/integrations/import/import_preview_screen.dart';
import 'package:enitor/features/integrations/ui/sync_screen.dart';
import 'package:enitor/features/settings/settings_screen.dart';
import 'package:enitor/features/today/today_screen.dart';
import 'package:enitor/services/backup_service.dart';
import 'dart:io';
import 'package:enitor/l10n/app_localizations.dart';
import 'package:enitor/services/notification_service.dart';
import 'package:enitor/services/pomodoro_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../test/goldens/golden_helpers.dart';

const _size = Size(412, 892);
const _dpr = 2.5;

final _calendar = [
  PlanEntry(
    title: 'Calculus (lecture)',
    action: PlanAction.create,
    date: DateTime(2026, 11, 16),
    startMinutes: 9 * 60,
    endMinutes: 10 * 60 + 30,
    repeats: true,
    apply: () async {},
  ),
  PlanEntry(
    title: 'English (every other week)',
    action: PlanAction.create,
    date: DateTime(2026, 11, 17),
    startMinutes: 14 * 60,
    endMinutes: 15 * 60 + 30,
    repeats: true,
    apply: () async {},
  ),
  PlanEntry(
    title: 'Physics lab',
    action: PlanAction.update,
    date: DateTime(2026, 11, 18),
    startMinutes: 11 * 60,
    endMinutes: 12 * 60 + 30,
    apply: () async {},
  ),
  PlanEntry(
    title: 'Training',
    action: PlanAction.create,
    date: DateTime(2026, 11, 19),
    startMinutes: 18 * 60,
    endMinutes: 19 * 60,
    repeats: true,
    apply: () async {},
  ),
  PlanEntry(
    title: 'Meeting with my advisor',
    action: PlanAction.create,
    date: DateTime(2026, 11, 20),
    startMinutes: 12 * 60,
    endMinutes: 13 * 60,
    apply: () async {},
  ),
  const PlanEntry(
    title: 'Open day',
    action: PlanAction.skip,
    date: null,
    skip: PlanSkip.allDay,
  ),
];

void main() {
  late ProviderContainer c;

  setUp(() async {
    await initializeDateFormatting('en');
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    c = ProviderContainer(
      overrides: [
        localStorageProvider.overrideWithValue(
          LocalStorage(await SharedPreferences.getInstance()),
        ),
        secretStoreProvider
            .overrideWithValue(SecretStore(MemorySecretBackend())),
        notificationServiceProvider.overrideWithValue(NotificationService()),
        // Утро демо-дня: по реальным часам вечером дневные задачи уже
        // «просрочены», а на картинке нужен обычный день.
        currentTimeProvider.overrideWith((ref) {
          final now = DateTime.now();
          return Stream.value(DateTime(now.year, now.month, now.day, 10, 40));
        }),
      ],
    );
    await c.read(appearanceProvider).setStyle(BackgroundStyle.paper);
    await c.read(appearanceProvider).setThemeMode(ThemeMode.dark);
  });

  Future<void> shot(
    WidgetTester tester,
    String name,
    Widget screen, {
    Duration settle = const Duration(milliseconds: 1600),
    Size size = _size,
    double dpr = _dpr,
    double scroll = 0,
  }) async {
    await loadAppFonts();
    // flutter_test по умолчанию рисует вместо теней чёрные рамки.
    debugDisableShadows = false;
    tester.view.physicalSize = size * dpr;
    tester.view.devicePixelRatio = dpr;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: ThemeMode.dark,
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          // Как в app.dart: на широком окне контент — колонкой по центру.
          builder: (_, child) => AppBackground(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: child,
              ),
            ),
          ),
          home: screen,
        ),
      ),
    );
    if (scroll > 0) {
      await tester.pump(const Duration(milliseconds: 300));
      // Главный вертикальный список экрана — самый высокий из прокручиваемых.
      final lists = tester
          .stateList<ScrollableState>(find.byType(Scrollable))
          .where((s) => s.axisDirection == AxisDirection.down)
          .toList()
        ..sort(
          (a, b) => b.position.maxScrollExtent
              .compareTo(a.position.maxScrollExtent),
        );
      lists.first.position.jumpTo(scroll);
    }
    // Кольца, полосы и плитки заполняются при входе — даём им дойти.
    for (var t = Duration.zero; t < settle; t += const Duration(milliseconds: 100)) {
      await tester.pump(const Duration(milliseconds: 100));
    }
try {
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('out/$name.png'),
      );
    } finally {
      debugDisableShadows = true;
      // Экраны заводят таймеры (часы, напоминания) — даём им отработать.
      await tester.pumpWidget(const SizedBox());
      // Периодические таймеры живут в провайдерах — гасим контейнер здесь,
      // до проверки «таймеров не осталось».
      c.dispose();
      await tester.pump(const Duration(hours: 25));
    }
  }

  testWidgets('focus', (tester) async {
    c.read(pomodoroProvider)
      ..phase = PomodoroPhase.focus
      ..taskTitle = 'Quarterly report draft'
      ..totalSeconds = 25 * 60
      ..remainingSeconds = 17 * 60 + 37
      ..sessionNumber = 2
      ..sessionMinutes = 25;
    await shot(tester, 'focus', const FocusScreen());
  });

  testWidgets('summary', (tester) async {
    await c.read(appearanceProvider).setSummaryBars(true);
    await shot(tester, 'summary', const SettingsScreen());
  });

  testWidgets('sync', (tester) async {
    await shot(tester, 'sync', const SyncScreen());
  });

  testWidgets('import', (tester) async {
    await shot(
      tester,
      'import',
      ImportPreviewScreen(title: 'Calendar import', entries: _calendar),
    );
  });

  // «Задачи» на демо-данных (dart run scripts/generate_demo_backup.dart —
  // «сегодня» в нём то, когда скрипт запущен): телефон и окно ноутбука.
  Widget tasks() => Scaffold(
        body: const TodayScreen(),
        bottomNavigationBar: Builder(
          builder: (context) => NavigationBar(
            selectedIndex: 0,
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.check_circle_outline),
                selectedIcon: Icon(Icons.check_circle),
                label: 'Tasks',
              ),
              NavigationDestination(icon: Icon(Icons.flag_outlined), label: 'Goals'),
              NavigationDestination(
                icon: Icon(Icons.show_chart_outlined),
                label: 'Stats',
              ),
              NavigationDestination(icon: Icon(Icons.person_outline), label: 'Profile'),
            ],
          ),
        ),
      );

  Future<void> seed() async {
    await BackupService(c.read(localStorageProvider))
        .restoreFromJson(File('dist/enitor-demo-seed.json').readAsStringSync());
    await c.read(appearanceProvider).setStyle(BackgroundStyle.paper);
    await c.read(appearanceProvider).setThemeMode(ThemeMode.dark);
    c.listen(currentTimeProvider, (_, __) {});
    await c.read(currentTimeProvider.future);
  }

  testWidgets('today-phone', (tester) async {
    await tester.runAsync(seed);
    await shot(
      tester,
      'today-phone',
      tasks(),
      settle: const Duration(seconds: 2),
      scroll: 420,
    );
  });

  testWidgets('today-desktop', (tester) async {
    await tester.runAsync(seed);
    // На низком экране 16:10 полосы оставляют место под список задач.
    await c.read(appearanceProvider).setSummaryBars(true);
    await shot(
      tester,
      'today-desktop',
      tasks(),
      size: const Size(1152, 720), // 16:10, как экран ноутбука
      dpr: 2,
      settle: const Duration(seconds: 2),
    );
  });
}
