import 'package:enitor/data/sources/local/local_storage.dart';
import 'package:enitor/features/help/pomodoro_guide_sheet.dart';
import 'package:enitor/l10n/app_localizations.dart';
import 'package:enitor/services/pomodoro_prefs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Гайд «как выбрать длину» — длинный текст в шторке, и открыть его руками на
// каждом размере экрана невозможно. Любое исключение раскладки (overflow,
// неограниченные констрейнты) валит тест.

Future<ProviderContainer> _container() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return ProviderContainer(
    overrides: [localStorageProvider.overrideWithValue(LocalStorage(prefs))],
  );
}

Future<void> _pumpGuide(
  WidgetTester tester,
  ProviderContainer container, {
  Locale locale = const Locale('ru'),
}) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showPomodoroGuideSheet(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('открывается и рисуется без ошибок раскладки', (tester) async {
    final container = await _container();
    addTearDown(container.dispose);

    await _pumpGuide(tester, container);

    expect(find.text('Как выбрать длину'), findsOneWidget);
    expect(find.text('45 / 10'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('узкий и низкий экран — влезает без переполнения',
      (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final container = await _container();
    addTearDown(container.dispose);

    await _pumpGuide(tester, container);

    expect(find.text('Как выбрать длину'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('английская локаль — тоже без переполнения', (tester) async {
    final container = await _container();
    addTearDown(container.dispose);

    await _pumpGuide(tester, container, locale: const Locale('en'));

    expect(find.text('Choosing your lengths'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('нажатие на стартовую точку ставит обе длины сразу',
      (tester) async {
    final container = await _container();
    addTearDown(container.dispose);
    final prefs = container.read(pomodoroPrefsProvider);
    // Дефолт 25/5 — значит отмечена третья строка, а не та, куда жмём.
    expect(find.text('Сейчас'), findsNothing);

    await _pumpGuide(tester, container);
    // Строка 25/5 отмечена как текущая ещё до нажатия.
    expect(find.text('Сейчас'), findsOneWidget);

    // Строка может оказаться ниже сгиба — шторка прокручиваемая.
    await tester.ensureVisible(find.text('45 / 10'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('45 / 10'));
    await tester.pumpAndSettle();

    expect(prefs.focusMinutes, 45);
    expect(prefs.breakMinutes, 10);
    // Отметка «Сейчас» переехала на нажатую строку и осталась одна.
    expect(find.text('Сейчас'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
