import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:enitor/core/current_time_provider.dart';
import 'package:enitor/data/models/goal.dart';
import 'package:enitor/data/repositories/goal_repository.dart';
import 'package:enitor/data/repositories/task_repository.dart';
import 'package:enitor/data/sources/local/local_storage.dart';
import 'package:enitor/features/goals/goals_screen.dart';
import 'package:enitor/l10n/app_localizations.dart';
import 'package:enitor/services/notification_service.dart';

/// «−» у цели-счётчика убавляет только ручную часть.
void main() {
  late ProviderContainer c;
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final week = GoalPeriodRef.current(GoalPeriod.week, now);

  setUp(() async {
    await initializeDateFormatting('ru');
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    c = ProviderContainer(
      overrides: [
        localStorageProvider.overrideWithValue(LocalStorage(prefs)),
        notificationServiceProvider.overrideWithValue(NotificationService()),
        currentTimeProvider.overrideWith((ref) => Stream.value(now)),
      ],
    );
  });
  tearDown(() => c.dispose());

  Future<Goal> goalWithTaskProgress() async {
    final goals = c.read(goalRepositoryProvider);
    final tasks = c.read(taskRepositoryProvider);
    final g = await goals.addGoal(
      title: 'Бег',
      period: week.period,
      year: week.year,
      weekStart: week.weekStart,
      targetCount: 5,
    );
    final t = await tasks.createAndAdd(
      title: 'Пробежка',
      date: today,
      goalId: g.id,
    );
    await tasks.toggleCompleted(t);
    return goals.goalById(g.id)!;
  }

  Future<void> pumpGoals(WidgetTester tester) async {
    tester.view.physicalSize = const Size(420, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: const MaterialApp(
          locale: Locale('ru'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: GoalsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('весь прогресс от задач: «−» объясняет, а не убавляет',
      (tester) async {
    final g = await goalWithTaskProgress();
    expect(g.linkedProgress, 1);
    expect(g.manualProgress, 0);
    await pumpGoals(tester);

    await tester.tap(find.byIcon(Icons.remove_circle_outline));
    await tester.pump();
    expect(find.textContaining('сними отметку или измени фактическое время'), findsOneWidget);
    expect(c.read(goalRepositoryProvider).goalById(g.id)!.progressCount, 1);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('ручная часть есть: «−» убавляет её', (tester) async {
    final g = await goalWithTaskProgress();
    await c.read(goalRepositoryProvider).incrementGoalCounter(g, 1);
    await pumpGoals(tester);

    await tester.tap(find.byIcon(Icons.remove_circle_outline));
    await tester.pumpAndSettle();
    final after = c.read(goalRepositoryProvider).goalById(g.id)!;
    expect(after.manualProgress, 0);
    expect(after.progressCount, 1);
  });
}
