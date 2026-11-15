import 'package:enitor/core/theme/app_theme.dart';
import 'package:enitor/data/sources/local/local_storage.dart';
import 'package:enitor/features/focus/focus_screen.dart';
import 'package:enitor/features/tour/tour.dart';
import 'package:enitor/l10n/app_localizations.dart';
import 'package:enitor/services/pomodoro_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<LocalStorage> _storage() async {
  SharedPreferences.setMockInitialValues({});
  return LocalStorage(await SharedPreferences.getInstance());
}

Widget _app(ProviderContainer c, Widget home) => UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        locale: const Locale('ru'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: home,
      ),
    );

/// На экранах бесконечные мягкие анимации (дыхание, пульс) — pumpAndSettle
/// их не дождётся; прокручиваем время с запасом на переходы.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

void main() {
  group('экскурсия: когда предлагать', () {
    test('чистая установка → «В первый раз?», потом молчит', () async {
      final p = TourPrefs(await _storage());
      expect(p.offer('0.4.0', firstDay: true), TourOffer.first);
      await p.markSeen('0.4.0');
      expect(p.offer('0.4.0', firstDay: true), isNull);
    });

    test('обновление → «Что нового»; выключено — молчит', () async {
      final s = await _storage();
      final p = TourPrefs(s);
      // Старый пользователь, у которого экскурсии ещё не было.
      expect(p.offer('0.4.0', firstDay: false), TourOffer.update);
      await p.markSeen('0.4.0');
      expect(p.offer('0.5.0', firstDay: false), TourOffer.update);
      await p.setOnUpdate(false);
      expect(TourPrefs(s).offer('0.5.0', firstDay: false), isNull);
    });
  });

  group('таймер на весь экран', () {
    for (final size in const [Size(360, 640), Size(1200, 800)]) {
      testWidgets('все фазы без переполнения, ${size.width}', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final c = ProviderContainer(
          overrides: [localStorageProvider.overrideWithValue(await _storage())],
        );
        addTearDown(c.dispose);
        final t = c.read(pomodoroProvider)
          ..taskTitle = 'Очень длинное название задачи, которое не влезает '
              'в одну строку ни на телефоне, ни на ноутбуке'
          ..totalSeconds = 1500
          ..remainingSeconds = 1122
          ..sessionNumber = 2
          ..sessionMinutes = 25;
        for (final phase in [
          PomodoroPhase.focus,
          PomodoroPhase.paused,
          PomodoroPhase.breakTime,
          PomodoroPhase.finished,
        ]) {
          t.phase = phase;
          await tester.pumpWidget(_app(c, FocusScreen(key: ValueKey(phase))));
          await tester.pump(const Duration(milliseconds: 300));
          expect(tester.takeException(), isNull, reason: '$phase');
          expect(find.textContaining('Сессия 2'), findsOneWidget);
        }
        expect(find.textContaining('Ещё фокус'), findsOneWidget);
      });
    }

    testWidgets('«Свернуть» закрывает экран, таймер идёт дальше',
        (tester) async {
      final c = ProviderContainer(
        overrides: [localStorageProvider.overrideWithValue(await _storage())],
      );
      addTearDown(c.dispose);
      c.read(pomodoroProvider)
        ..phase = PomodoroPhase.focus
        ..taskTitle = 'Письмо'
        ..totalSeconds = 1500
        ..remainingSeconds = 1500;
      await tester.pumpWidget(
        _app(
          c,
          Builder(
            builder: (ctx) => TextButton(
              onPressed: () => showFocusScreen(ctx),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await _settle(tester);
      expect(find.byType(FocusScreen), findsOneWidget);
      await tester.tap(find.text('Свернуть'));
      await _settle(tester);
      expect(find.byType(FocusScreen), findsNothing);
      expect(c.read(pomodoroProvider).phase, PomodoroPhase.focus);
    });
  });

  testWidgets('экскурсия проходит все шаги и закрывается', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    Widget page(String name, List<(GlobalKey, double)> keyed) => Scaffold(
          appBar: AppBar(title: Text(name)),
          body: ListView(
            children: [
              for (final (k, h) in keyed)
                SizedBox(key: k, height: h, child: Text(k.toString())),
            ],
          ),
        );

    final router = GoRouter(
      initialLocation: '/today',
      routes: [
        // Нижняя панель — одна на все вкладки, как в приложении.
        ShellRoute(
          builder: (_, __, child) => Scaffold(
            body: child,
            bottomNavigationBar: SizedBox(key: TourKeys.navBar, height: 64),
          ),
          routes: [
            GoRoute(
              path: '/today',
              builder: (_, __) => page('today', [
                (TourKeys.dayToggle, 40),
                (TourKeys.calendar, 300),
                (TourKeys.templates, 60),
                (TourKeys.summary, 160),
                (TourKeys.tasks, 400),
                (TourKeys.addTask, 56),
              ]),
            ),
            GoRoute(
              path: '/goals',
              builder: (_, __) => page('goals', [(TourKeys.goalPeriods, 40)]),
            ),
            GoRoute(path: '/stats', builder: (_, __) => page('stats', [])),
            GoRoute(path: '/profile', builder: (_, __) => page('profile', [])),
          ],
        ),
        GoRoute(
          path: '/settings',
          builder: (_, __) => Scaffold(
            body: ListView(
              children: [
                SizedBox(key: TourKeys.connections, height: 200),
                const SizedBox(height: 1200),
                SizedBox(key: TourKeys.tourRow, height: 120),
              ],
            ),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp.router(
          locale: const Locale('ru'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
          builder: (_, child) => Stack(
            children: [child!, const Positioned.fill(child: TourLayer())],
          ),
        ),
      ),
    );
    startTour(router);
    await _settle(tester);
    expect(find.text('Шаг 1 из 12'), findsOneWidget);

    // Шаг вперёд и назад — без ошибок.
    await tester.tap(find.text('Далее'));
    await _settle(tester);
    await tester.tap(find.text('Назад'));
    await _settle(tester);
    expect(find.text('Шаг 1 из 12'), findsOneWidget);

    for (var i = 1; i < 12; i++) {
      await tester.tap(find.text('Далее'));
      await _settle(tester);
      expect(find.text('Шаг ${i + 1} из 12'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    expect(
      router.routerDelegate.currentConfiguration.last.matchedLocation,
      '/settings',
    );
    // Назад с последнего шага на «Настройки» не кладёт их второй раз.
    await tester.tap(find.text('Назад'));
    await _settle(tester);
    expect(find.text('Шаг 11 из 12'), findsOneWidget);
    expect(router.routerDelegate.currentConfiguration.matches.length, 2);
    await tester.tap(find.text('Далее'));
    await _settle(tester);
    await tester.tap(find.text('Готово'));
    await _settle(tester);
    expect(tourRunning.value, isNull);
    expect(find.textContaining('из 12'), findsNothing);
  });

  testWidgets('таймер открывается без наложения на «Задачи» и нижнюю панель',
      (tester) async {
    final c = ProviderContainer(
      overrides: [localStorageProvider.overrideWithValue(await _storage())],
    );
    addTearDown(c.dispose);
    c.read(pomodoroProvider)
      ..phase = PomodoroPhase.focus
      ..taskTitle = 'Письмо'
      ..totalSeconds = 1500
      ..remainingSeconds = 1500;
    // Как в приложении: вкладка без перехода внутри ShellRoute с панелью.
    final router = GoRouter(
      initialLocation: '/today',
      routes: [
        ShellRoute(
          builder: (_, __, child) => Scaffold(
            body: child,
            bottomNavigationBar: const SizedBox(height: 64, child: Text('панель')),
          ),
          routes: [
            GoRoute(
              path: '/today',
              pageBuilder: (_, __) => NoTransitionPage(
                child: Builder(
                  builder: (ctx) => TextButton(
                    onPressed: () => showFocusScreen(ctx),
                    child: const Text('вкладка'),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp.router(
          theme: AppTheme.light(),
          locale: const Locale('ru'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );

    // Итоговая видимость виджета: произведение всех FadeTransition над ним.
    double opacity(Finder f) {
      if (f.evaluate().isEmpty) return 0;
      var o = 1.0;
      f.evaluate().first.visitAncestorElements((e) {
        final w = e.widget;
        if (w is FadeTransition) o *= w.opacity.value;
        if (w is Opacity) o *= w.opacity;
        return true;
      });
      return o;
    }

    void checkFrames(String dir) {
      final tab = opacity(find.text('вкладка'));
      final bar = opacity(find.text('панель'));
      final focus = opacity(find.text('Свернуть'));
      expect(
        focus > 0.01 && (tab > 0.01 || bar > 0.01),
        isFalse,
        reason: '$dir: таймер $focus, вкладка $tab, панель $bar',
      );
    }

    await tester.tap(find.text('вкладка'));
    for (var i = 0; i < 25; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      checkFrames('открытие');
    }
    await _settle(tester);
    expect(opacity(find.text('Свернуть')), closeTo(1, 0.01));
    await tester.tap(find.text('Свернуть'));
    for (var i = 0; i < 25; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      checkFrames('сворачивание');
    }
    await _settle(tester);
    expect(find.byType(FocusScreen), findsNothing);
    expect(opacity(find.text('панель')), closeTo(1, 0.01));
  });
}
