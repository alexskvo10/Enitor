import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:enitor/core/utils/date_utils.dart';
import 'package:enitor/data/models/day_stats.dart';
import 'package:enitor/data/models/goal.dart';
import 'package:enitor/data/models/task.dart';
import 'package:enitor/l10n/app_localizations.dart';
import 'package:enitor/widgets/fancy_dialog.dart';
import 'package:enitor/widgets/weekly_retro_sheet.dart';

// Прошлая неделя относительно «сегодня» теста не годится: computeWeekStats
// отбрасывает дни ПОСЛЕ сегодняшнего. Берём заведомо прошедшую неделю.
final _week = DateTime(2026, 1, 5); // пн 5 — вс 11 января 2026
final _prevWeek = DateTime(2025, 12, 29);

DayStats _day(DateTime date, int total, int done, {int onTime = 0}) => DayStats(
      date: date,
      totalTasks: total,
      completedTasks: done,
      onTimeCount: onTime,
      lateCount: done - onTime,
      updatedAt: date,
    );

Task _task(DateTime date, int estimate, int actual) {
  final id = '$date-$estimate-$actual';
  return Task(
    id: id,
    title: id,
    date: date,
    createdAt: date,
    updatedAt: date,
    completedAt: date,
    estimatedMinutes: estimate,
    actualMinutes: actual,
  );
}

Goal _weekGoal(String title, DateTime weekStart, {bool completed = false}) =>
    Goal(
      id: title,
      period: GoalPeriod.week,
      year: weekStart.year,
      weekStart: weekStart,
      title: title,
      createdAt: weekStart,
      updatedAt: weekStart,
      completed: completed,
      completedAt: completed ? weekStart.add(const Duration(days: 2)) : null,
    );

/// Максимально «полная» неделя: есть каждый блок окна.
WeeklyRetroData _fullData() {
  final stats = <DayStats>[
    for (var i = 0; i < 6; i++)
      _day(_week.add(Duration(days: i)), 5, 4 + (i % 2), onTime: 3),
    for (var i = 0; i < 6; i++)
      _day(_prevWeek.add(Duration(days: i)), 5, 3, onTime: 2),
  ];
  final tasks = <Task>[
    for (var i = 0; i < 4; i++) _task(_week.add(Duration(days: i)), 60, 70),
    for (var i = 0; i < 4; i++) _task(_prevWeek.add(Duration(days: i)), 60, 95),
  ];
  return WeeklyRetroData.build(
    weekStart: _week,
    allStats: stats,
    goals: [
      _weekGoal('Спорт трижды', _week, completed: true),
      _weekGoal('Дочитать «Дюну»', _week),
      _weekGoal('Сдать отчёт с очень длинным названием цели', _week),
      Goal(
        id: 'месячная',
        period: GoalPeriod.month,
        year: 2026,
        month: 1,
        title: 'Закрыть месячную цель',
        createdAt: _week,
        updatedAt: _week,
        completed: true,
        completedAt: _week.add(const Duration(days: 3)),
      ),
    ],
    ratings: {
      for (var i = 0; i < 5; i++)
        DateTime(_week.year, _week.month, _week.day + i).toIso8601String(): 8,
    },
    tasks: tasks,
  );
}

Future<void> _pumpSheet(
  WidgetTester tester,
  WeeklyRetroData data, {
  Locale locale = const Locale('ru'),
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showWeeklyRetroSheet(context, data: data),
              child: const Text('open'),
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
  // Любое исключение раскладки (overflow, unbounded constraints) валит тест —
  // ровно то, что нужно проверить у диалога, который нельзя открыть руками
  // до понедельника.
  setUp(() {
    // размер по умолчанию у тестов — 800x600
  });

  testWidgets('полная неделя — все блоки рисуются без ошибок раскладки',
      (tester) async {
    await _pumpSheet(tester, _fullData());
    expect(find.text('Итоги недели'), findsOneWidget);
    expect(find.text('5–11 января 2026'), findsOneWidget);
    expect(find.textContaining('Цели на неделю: 1 из 3'), findsOneWidget);
    expect(find.textContaining('Точность оценок'), findsOneWidget);
    expect(find.text('Закрыть'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('узкий и низкий экран — влезает без переполнения',
      (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await _pumpSheet(tester, _fullData());
    expect(tester.takeException(), isNull);
  });

  testWidgets('ландшафт — прокручиваемая часть ограничена высотой экрана',
      (tester) async {
    tester.view.physicalSize = const Size(720, 360);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await _pumpSheet(tester, _fullData());
    expect(tester.takeException(), isNull);
  });

  testWidgets('английская локаль — тоже без переполнения', (tester) async {
    await _pumpSheet(tester, _fullData(), locale: const Locale('en'));
    expect(find.text('Week summary'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('только цели, без задач — окно всё равно осмысленное',
      (tester) async {
    final data = WeeklyRetroData.build(
      weekStart: _week,
      allStats: const [],
      goals: [_weekGoal('Одна цель', _week)],
      ratings: const {},
      tasks: const [],
    );
    expect(data.isEmpty, isFalse);
    await _pumpSheet(tester, data);
    expect(find.textContaining('Цели на неделю: 0 из 1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('неделя без целей — про это сказано прямо', (tester) async {
    final data = WeeklyRetroData.build(
      weekStart: _week,
      allStats: [_day(_week, 3, 3, onTime: 3)],
      goals: const [],
      ratings: const {},
      tasks: const [],
    );
    await _pumpSheet(tester, data);
    expect(find.text('Целей на эту неделю не было'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('нет предыдущей недели — сравнение не выдумывается',
      (tester) async {
    final data = WeeklyRetroData.build(
      weekStart: _week,
      allStats: [_day(_week, 4, 2, onTime: 2)],
      goals: const [],
      ratings: const {},
      tasks: [
        for (var i = 0; i < 3; i++) _task(_week.add(Duration(days: i)), 30, 45),
      ],
    );
    await _pumpSheet(tester, data);
    // Дельта продуктивности — прочерк, а не «0.0%».
    expect(find.text('—'), findsWidgets);
    expect(
      find.text('Сравнить не с чем: неделей раньше оценок не хватало'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('ничего не вылезает за края карточки', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await _pumpSheet(tester, _fullData());

    // Внутренняя область карточки: колонка под медальоном и заголовком.
    final card = tester.getRect(
      find
          .descendant(
            of: find.byType(FancyDialogCard),
            matching: find.byType(Column),
          )
          .first,
    );

    // По горизонтали ничего не обрезается прокруткой, поэтому любой выход за
    // край — настоящий баг. Проверяем все карточки и кнопку.
    for (final f in [find.byType(Card), find.byType(FilledButton)]) {
      for (var i = 0; i < tester.widgetList(f).length; i++) {
        final r = tester.getRect(f.at(i));
        expect(
          r.left,
          greaterThanOrEqualTo(card.left - 0.5),
          reason: 'элемент $i выходит за левый край',
        );
        expect(
          r.right,
          lessThanOrEqualTo(card.right + 0.5),
          reason: 'элемент $i выходит за правый край',
        );
      }
    }

    // По вертикали неподвижная часть (подпись недели и кнопка «Закрыть»)
    // обязана лежать внутри карточки — её прокрутка не спасает.
    for (final f in [find.text('5–11 января 2026'), find.text('Закрыть')]) {
      final r = tester.getRect(f);
      expect(r.top, greaterThanOrEqualTo(card.top - 0.5));
      expect(r.bottom, lessThanOrEqualTo(card.bottom + 0.5));
    }

    // И вся карточка целиком — внутри экрана.
    expect(card.top, greaterThanOrEqualTo(0));
    expect(card.bottom, lessThanOrEqualTo(640));
    expect(tester.takeException(), isNull);
  });

  testWidgets('пока grace-окно открыто — про это сказано, счёт не финальный',
      (tester) async {
    // Текущая неделя: её grace-окно заведомо ещё не истекло.
    final thisWeek = startOfWeek(today());
    final data = WeeklyRetroData.build(
      weekStart: thisWeek,
      allStats: [_day(thisWeek, 3, 2, onTime: 2)],
      goals: [
        _weekGoal('Сделана', thisWeek, completed: true),
        _weekGoal('Ещё не сделана', thisWeek),
      ],
      ratings: const {},
      tasks: const [],
    );
    await _pumpSheet(tester, data);
    expect(find.textContaining('Цели на неделю: 1 из 2'), findsOneWidget);
    expect(find.textContaining('Их ещё можно закрыть'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('grace-окно истекло — лишней приписки нет', (tester) async {
    final data = WeeklyRetroData.build(
      weekStart: _week,
      allStats: [_day(_week, 3, 2, onTime: 2)],
      goals: [_weekGoal('Не сделана', _week)],
      ratings: const {},
      tasks: const [],
    );
    await _pumpSheet(tester, data);
    expect(find.textContaining('Цели на неделю: 0 из 1'), findsOneWidget);
    expect(find.textContaining('Их ещё можно закрыть'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
