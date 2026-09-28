import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:enitor/core/current_time_provider.dart';
import 'package:enitor/core/utils/date_utils.dart';
import 'package:enitor/data/models/recurrence_rule.dart';
import 'package:enitor/data/repositories/schedule_repository.dart';
import 'package:enitor/data/repositories/task_repository.dart';
import 'package:enitor/data/sources/local/local_storage.dart';
import 'package:enitor/features/today/today_screen.dart';
import 'package:enitor/l10n/app_localizations.dart';
import 'package:enitor/services/notification_service.dart';

void main() {
  late ProviderContainer container;

  Future<void> pumpToday(WidgetTester tester) async {
    tester.view.physicalSize = const Size(420, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          locale: Locale('ru'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: TodayScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  setUp(() async {
    await initializeDateFormatting('ru');
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    container = ProviderContainer(
      overrides: [
        localStorageProvider.overrideWithValue(LocalStorage(prefs)),
        notificationServiceProvider.overrideWithValue(NotificationService()),
        // Настоящие часы тикают периодическим таймером, который тестовый
        // биндинг считает утёкшим; экрану хватает одного «сейчас».
        currentTimeProvider.overrideWith((ref) => Stream.value(DateTime.now())),
      ],
    );
  });
  tearDown(() => container.dispose());

  testWidgets('пустая вкладка, анкета не сохраняется без времени',
      (tester) async {
    await pumpToday(tester);

    await tester.tap(find.text('Расписание'));
    await tester.pumpAndSettle();
    expect(
      find.text('В расписании на этот день ничего нет.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Пункт'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Английский');
    await tester.tap(find.text('Добавить'));
    await tester.pumpAndSettle();
    expect(
      find.text('Укажите начало; конец, если есть, — позже начала'),
      findsOneWidget,
    );
    expect(container.read(scheduleRepositoryProvider).all, isEmpty);
  });

  testWidgets('пункт виден на обеих вкладках и превращается в задачу',
      (tester) async {
    final day = effectiveDay(DateTime.now());
    await container.read(scheduleRepositoryProvider).create(
      title: 'Английский',
      date: day,
      startMinutes: 23 * 60 + 20, // после 23:00 — бюджет дня не трогает
      endMinutes: 23 * 60 + 50,
      weekdays: [day.weekday],
    );
    await pumpToday(tester);

    // Вкладка «Задачи»: сводка расписания над списком.
    expect(find.text('Расписание · 1'), findsOneWidget);

    // Нажатие на сводку открывает вкладку «Расписание».
    await tester.tap(find.text('Расписание · 1'));
    await tester.pumpAndSettle();
    expect(find.text('23:20'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Сделать задачей'));
    await tester.pumpAndSettle();
    // У серии — вопрос; выбираем один день.
    await tester.tap(find.text('Только этот день'));
    await tester.pumpAndSettle();

    final tasks = container.read(taskRepositoryProvider).tasksForDay(day);
    expect(tasks.single.title, 'Английский');
    expect(tasks.single.startMinutes, 23 * 60 + 20);
    expect(tasks.single.estimatedMinutes, isNull);
    // Пункт остался в расписании.
    expect(container.read(scheduleRepositoryProvider).all, hasLength(1));
  });

  testWidgets('пункт без конца сохраняется, свайп удаляет разовый пункт',
      (tester) async {
    final day = effectiveDay(DateTime.now());
    final repo = container.read(scheduleRepositoryProvider);
    await pumpToday(tester);
    await tester.tap(find.text('Расписание'));
    await tester.pumpAndSettle();

    // Без конца: начало задаём прямо в репозитории — системный выбор
    // времени в тесте не покрутить; анкета должна принять пустой конец.
    final item = await repo.create(
      title: 'Созвон',
      date: day,
      startMinutes: 23 * 60 + 30,
      location: 'Zoom',
      note: 'Показать макет',
    );
    await tester.pumpAndSettle();
    expect(find.text('Созвон'), findsOneWidget);
    expect(find.text('Zoom'), findsOneWidget);
    expect(find.text('Показать макет'), findsOneWidget);

    // Анкета существующего пункта без конца сохраняется.
    await tester.tap(find.text('Созвон'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();
    expect(repo.all.single.endMinutes, isNull);
    expect(repo.all.single.id, item.id);

    await tester.drag(find.text('Созвон'), const Offset(-600, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Удалить'));
    await tester.pumpAndSettle();
    expect(repo.all, isEmpty);
    expect(find.text('Созвон'), findsNothing);
  });

  testWidgets('правка «только этот день» выносит день из серии',
      (tester) async {
    final day = effectiveDay(DateTime.now());
    final repo = container.read(scheduleRepositoryProvider);
    final series = await repo.create(
      title: 'Матан',
      date: day,
      startMinutes: 23 * 60 + 10,
      endMinutes: 23 * 60 + 40,
      repeat: RecurrenceKind.interval,
      intervalDays: 1,
    );
    await pumpToday(tester);
    await tester.tap(find.text('Расписание'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Матан'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Матан (замена)');
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Только этот день'));
    await tester.pumpAndSettle();

    final tomorrow = DateTime(day.year, day.month, day.day + 1);
    expect(repo.forDay(day).single.title, 'Матан (замена)');
    expect(repo.forDay(day).single.isSeries, isFalse);
    expect(repo.forDay(tomorrow).single.id, series.id);
    expect(repo.forDay(tomorrow).single.title, 'Матан');
  });

  testWidgets('неделя: семь дней, нажатие открывает день', (tester) async {
    final day = effectiveDay(DateTime.now());
    await container.read(scheduleRepositoryProvider).create(
      title: 'Английский',
      date: day,
      startMinutes: 23 * 60 + 20,
      repeat: RecurrenceKind.interval,
      intervalDays: 1,
    );
    await pumpToday(tester);
    await tester.tap(find.text('Расписание'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Неделя'));
    await tester.pumpAndSettle();
    // Каждый день недели, начиная с дня серии, — по строке.
    expect(find.text('Английский'), findsNWidgets(8 - day.weekday));

    await tester.tap(find.text('Английский').last);
    await tester.pumpAndSettle();
    expect(find.text('Английский'), findsOneWidget);
    expect(find.text('23:20'), findsOneWidget);
    // Сводка дня: пункт без конца времени не занимает.
    expect(find.text('1 пункт'), findsOneWidget);
    expect(find.text('Неделя'), findsOneWidget);
  });
}
