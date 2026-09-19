import 'package:enitor/data/sources/local/local_storage.dart';
import 'package:enitor/l10n/app_localizations.dart';
import 'package:enitor/services/pomodoro_controller.dart';
import 'package:enitor/widgets/pomodoro_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// В фазе «Готово» кнопки («Ещё фокус» и «Закрыть») обязаны стоять у правого
// края карточки. Раньше пилюля «Ещё фокус» лежала во Flexible: гибкий ребёнок
// с loose-подгонкой забирал половину свободной ширины, а отдавал обратно
// только фактическую — остаток свободного места повисал справа, и обе кнопки
// липли к тексту слева.
//
// ⚠️ Ширина окна тут — часть условия, а не декорация. На узкой карточке
// половина свободного места МЕНЬШЕ пилюли, её зажимало по максимуму, слот
// заполнялся целиком — и раскладка выглядела правильной. Перекос вылезал
// только там, где места много: на десктопе. Первый замер поэтому широкий.

Future<ProviderContainer> _container() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return ProviderContainer(
    overrides: [localStorageProvider.overrideWithValue(LocalStorage(prefs))],
  );
}

/// Ставит таймер в фазу «Готово» без прокрутки 25 минут отсчёта. Задача
/// намеренно не привязывается (`taskId` остаётся пустым): проверяем раскладку,
/// а не переходы, и без привязки контроллер не выключит себя, не найдя задачу.
void _finish(PomodoroController timer, {String title = 'Написать письмо'}) {
  timer.phase = PomodoroPhase.finished;
  timer.taskTitle = title;
  timer.sessionNumber = 2;
  timer.sessionMinutes = 50;
}

Future<void> _pumpBanner(
  WidgetTester tester,
  ProviderContainer container, {
  Locale locale = const Locale('ru'),
  Size size = const Size(900, 700),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(
          body: Padding(
            padding: EdgeInsets.all(12),
            child: Align(
              alignment: Alignment.topCenter,
              child: PomodoroBanner(),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('«Готово»: кнопки прижаты к правому краю карточки',
      (tester) async {
    final container = await _container();
    addTearDown(container.dispose);
    _finish(container.read(pomodoroProvider));

    await _pumpBanner(tester, container);

    final card = tester.getRect(find.byType(Card));
    final close = tester.getRect(find.byTooltip('Закрыть'));
    final another = tester.getRect(find.text('Ещё фокус'));

    // Внутренний отступ карточки справа — 12. Кнопка «Закрыть» последняя в
    // ряду, значит её правый край и есть край содержимого.
    expect(card.right - close.right, closeTo(12, 1));
    // «Ещё фокус» — прямо перед ней, а не у текста слева.
    expect(another.right, lessThan(close.left));
    expect(close.left - another.right, lessThan(40));
    // И весь блок кнопок — в правой четверти карточки: на широком окне
    // сломанная раскладка ставила их сразу за серединой.
    expect(another.left, greaterThan(card.left + card.width * 0.75));
  });

  testWidgets('«Готово» на узком экране: без переполнения', (tester) async {
    final container = await _container();
    addTearDown(container.dispose);
    // Длинный заголовок — тот случай, ради которого пилюля и была гибкой:
    // ужиматься должен заголовок (у него Expanded и многоточие), а не кнопки.
    _finish(
      container.read(pomodoroProvider),
      title: 'Разобрать почту, ответить всем и закрыть длинный тред',
    );

    await _pumpBanner(tester, container, size: const Size(320, 568));

    expect(tester.takeException(), isNull);
    final card = tester.getRect(find.byType(Card));
    final close = tester.getRect(find.byTooltip('Закрыть'));
    expect(card.right - close.right, closeTo(12, 1));
  });

  testWidgets('идущий фокус: кнопки тоже справа', (tester) async {
    // Контрольный замер: в остальных фазах кнопки всегда стояли правильно,
    // и правка не должна была их сдвинуть.
    final container = await _container();
    addTearDown(container.dispose);
    final timer = container.read(pomodoroProvider);
    timer.phase = PomodoroPhase.focus;
    timer.taskTitle = 'Написать письмо';
    timer.totalSeconds = 1500;
    timer.remainingSeconds = 1500;

    await _pumpBanner(tester, container);

    final card = tester.getRect(find.byType(Card));
    final stop = tester.getRect(find.byTooltip('Остановить'));
    expect(card.right - stop.right, closeTo(12, 1));
  });
}
