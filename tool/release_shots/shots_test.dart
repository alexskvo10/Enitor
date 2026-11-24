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
import 'package:enitor/features/stats/stats_screen.dart';
import 'package:enitor/features/goals/goals_screen.dart';
import 'package:enitor/features/profile/profile_screen.dart';
import 'package:enitor/features/retro/retrospective_screen.dart';
import 'package:enitor/features/stats/tag_stats_screen.dart';
import 'package:enitor/features/achievements/achievements_screen.dart';
import 'package:enitor/services/backup_service.dart';
import 'dart:io';
import 'package:enitor/l10n/app_localizations.dart';
import 'package:enitor/services/notification_service.dart';
import 'package:enitor/services/pomodoro_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../test/goldens/golden_helpers.dart';

const _size = Size(412, 892);
const _dpr = 2.5;
var _emojiLoaded = false;

ThemeData _withEmoji(ThemeData t) => t.copyWith(
      textTheme: t.textTheme.apply(fontFamilyFallback: const ['ShotEmoji']),
      primaryTextTheme:
          t.primaryTextTheme.apply(fontFamilyFallback: const ['ShotEmoji']),
    );

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
    ThemeMode mode = ThemeMode.dark,
  }) async {
    await c.read(appearanceProvider).setThemeMode(mode);
    await loadAppFonts();
    // Эмодзи (достижения, профиль, итоги недели): в тестах их шрифта нет,
    // и вместо них чёрные полосы. Берём Segoe UI Emoji из Windows и подключаем
    // запасным шрифтом темы (_withEmoji).
    if (!_emojiLoaded) {
      final bytes = File(r'C:\Windows\Fonts\seguiemj.ttf').readAsBytesSync();
      await (FontLoader('ShotEmoji')
            ..addFont(Future.value(ByteData.sublistView(bytes))))
          .load();
      _emojiLoaded = true;
    }
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
          theme: _withEmoji(AppTheme.light()),
          darkTheme: _withEmoji(AppTheme.dark()),
          themeMode: mode,
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
  Widget tasks([Widget body = const TodayScreen(), int tab = 0]) => Scaffold(
        body: body,
        bottomNavigationBar: Builder(
          builder: (context) => NavigationBar(
            selectedIndex: tab,
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

  // Галерея сайта (docs/): окно ноутбука и телефон, тоже на демо-данных.
  // PNG — в out/site/, на сайт их кладёт scripts/site_shots.py.
  const win = Size(706, 1073);
  const phone = Size(412, 892);
  final siteShots = <String, ({Widget Function() screen, Size size, ThemeMode mode, double scroll})>{
    'windows/today': (screen: () => tasks(), size: win, mode: ThemeMode.light, scroll: 0),
    'windows/today_dark': (screen: () => tasks(), size: win, mode: ThemeMode.dark, scroll: 0),
    'windows/today_2': (screen: () => tasks(), size: win, mode: ThemeMode.light, scroll: 520),
    'windows/week_summary': (screen: () => const RetrospectiveScreen(), size: win, mode: ThemeMode.light, scroll: 0),
    'windows/stats': (screen: () => tasks(const StatsScreen(), 2), size: win, mode: ThemeMode.light, scroll: 0),
    'windows/goals': (screen: () => tasks(const GoalsScreen(), 1), size: win, mode: ThemeMode.light, scroll: 0),
    'windows/profile': (screen: () => tasks(const ProfileScreen(), 3), size: win, mode: ThemeMode.light, scroll: 0),
    'windows/tag_stats': (screen: () => const TagStatsScreen(), size: win, mode: ThemeMode.light, scroll: 0),
    'windows/achievements': (screen: () => const AchievementsScreen(), size: win, mode: ThemeMode.light, scroll: 0),
    'windows/settings': (screen: () => const SettingsScreen(), size: win, mode: ThemeMode.light, scroll: 0),
    'windows/focus': (screen: () => const FocusScreen(), size: win, mode: ThemeMode.light, scroll: 0),
    'android/today': (screen: () => tasks(), size: phone, mode: ThemeMode.light, scroll: 0),
    'android/today_done': (screen: () => tasks(), size: phone, mode: ThemeMode.light, scroll: 900),
    'android/today_dark': (screen: () => tasks(), size: phone, mode: ThemeMode.dark, scroll: 0),
    'android/stats': (screen: () => tasks(const StatsScreen(), 2), size: phone, mode: ThemeMode.light, scroll: 0),
    'android/goals': (screen: () => tasks(const GoalsScreen(), 1), size: phone, mode: ThemeMode.light, scroll: 0),
    'android/profile': (screen: () => tasks(const ProfileScreen(), 3), size: phone, mode: ThemeMode.light, scroll: 0),
    'android/achievements': (screen: () => const AchievementsScreen(), size: phone, mode: ThemeMode.light, scroll: 0),
    'android/settings': (screen: () => const SettingsScreen(), size: phone, mode: ThemeMode.light, scroll: 0),
    'android/focus': (screen: () => const FocusScreen(), size: phone, mode: ThemeMode.light, scroll: 0),
  };
  for (final e in siteShots.entries) {
    testWidgets('site ${e.key}', (tester) async {
      await tester.runAsync(seed);
      if (e.key.endsWith('focus')) {
        c.read(pomodoroProvider)
          ..phase = PomodoroPhase.focus
          ..taskTitle = 'Quarterly report draft'
          ..totalSeconds = 25 * 60
          ..remainingSeconds = 17 * 60 + 37
          ..sessionNumber = 2
          ..sessionMinutes = 25;
      }
      final v = e.value;
      await shot(
        tester,
        'site/${e.key}',
        v.screen(),
        size: v.size,
        dpr: v.size == win ? 2 : _dpr,
        mode: v.mode,
        scroll: v.scroll,
        settle: const Duration(seconds: 2),
      );
    });
  }
}
