import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../theme/app_colors.dart';
import '../../data/models/achievement.dart';
import '../../data/repositories/achievements_repository.dart';
import '../../data/repositories/goal_repository.dart';
import '../../data/repositories/rating_repository.dart';
import '../../data/repositories/stats_repository.dart';
import '../../data/repositories/task_repository.dart';
import '../../features/about/about_screen.dart';
import '../../features/goals/goals_screen.dart';
import '../../features/help/faq_screen.dart';
import '../../features/profile/profile_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../../features/stats/stats_screen.dart';
import '../../features/today/today_screen.dart';
import '../../l10n/l10n_extensions.dart';
import '../../services/transfer_prompt_controller.dart';
import '../../services/weekly_retro_controller.dart';
import '../../widgets/achievement_popup.dart';
import '../../widgets/transfer_catchup_sheet.dart';
import '../../widgets/transfer_prompt_banner.dart';
import '../../widgets/update_dialog.dart';
import '../../widgets/weekly_retro_sheet.dart';

/// Главный роутер. Использует ShellRoute с нижней навигацией для пяти
/// основных разделов. Настройки и «О приложении» — на отдельных страницах поверх.
final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/today',
    routes: [
      ShellRoute(
        builder: (context, state, child) => _RootScaffold(child: child),
        routes: [
          GoRoute(
            path: '/today',
            pageBuilder: (_, state) => NoTransitionPage(
                key: state.pageKey, child: const TodayScreen()),
          ),
          GoRoute(
            path: '/stats',
            pageBuilder: (_, state) => NoTransitionPage(
                key: state.pageKey, child: const StatsScreen()),
          ),
          GoRoute(
            path: '/goals',
            pageBuilder: (_, state) => NoTransitionPage(
                key: state.pageKey, child: const GoalsScreen()),
          ),
          GoRoute(
            path: '/profile',
            pageBuilder: (_, state) => NoTransitionPage(
              key: state.pageKey,
              child: const ProfileScreen(),
            ),
          ),
        ],
      ),
      GoRoute(
        path: '/settings',
        builder: (_, __) => const SettingsScreen(),
      ),
      GoRoute(
        path: '/about',
        builder: (_, __) => const AboutScreen(),
      ),
      GoRoute(
        path: '/faq',
        builder: (_, __) => const FaqScreen(),
      ),
    ],
  );
});

class _RootScaffold extends ConsumerStatefulWidget {
  const _RootScaffold({required this.child});
  final Widget child;

  static const _tabs = <_TabSpec>[
    _TabSpec('/today', Icons.check_circle_outline, Icons.check_circle),
    _TabSpec('/stats', Icons.show_chart_outlined, Icons.show_chart),
    _TabSpec('/goals', Icons.flag_outlined, Icons.flag),
    _TabSpec('/profile', Icons.person_outline, Icons.person),
  ];

  @override
  ConsumerState<_RootScaffold> createState() => _RootScaffoldState();
}

class _RootScaffoldState extends ConsumerState<_RootScaffold> {
  // Запоминаем прошлый индекс, чтобы «бумажный сдвиг» шёл в сторону движения:
  // вправо при переходе на дальнюю вкладку, влево — на ближнюю.
  int _prevIndex = 0;

  Timer? _transferTimer;

  @override
  void initState() {
    super.initState();
    _scheduleTransferPrompt();
    // Всё, что может встретить пользователя при запуске, — строго по очереди,
    // а не тремя параллельными колбэками: иначе диалоги наслаиваются друг на
    // друга. Порядок по срочности: сначала перенос (это про данные), потом
    // итоги недели, потом обновление. После первого кадра — нужен готовый
    // Navigator.
    WidgetsBinding.instance.addPostFrameCallback((_) => _runStartupPrompts());
  }

  Future<void> _runStartupPrompts() async {
    // Догоняющий список — если пропустили границу 4:00, пока приложения не
    // было открыто.
    await _maybeShowCatchup();
    if (!mounted) return;
    await _maybeShowWeeklyRetro();
    if (!mounted) return;
    // Тихая автопроверка обновлений (не чаще раза в сутки, см.
    // UpdateService._throttle) — молчит, если обновления нет или сети нет.
    await checkAndShowUpdateDialog(context, ref, manual: false);
  }

  /// Окно с разбором прошедшей недели — при первом открытии приложения после
  /// настроенного момента (по умолчанию понедельник, 19:00).
  Future<void> _maybeShowWeeklyRetro() async {
    final controller = ref.read(weeklyRetroControllerProvider);
    // Один снимок времени на обе проверки: иначе запуск ровно на границе
    // 4:00 мог бы решить «пора» про одну неделю, а показать другую.
    final now = DateTime.now();
    if (!controller.shouldShow(now)) return;
    final weekStart = controller.reviewWeekStart(now);

    // Данные могли ещё не подняться из хранилища — ждём первое значение
    // каждого потока, иначе неделя выглядела бы пустой на холодном старте.
    final allStats = await ref.read(allDayStatsProvider.future);
    final goals = await ref.read(allGoalsProvider.future);
    final ratings = await ref.read(dayRatingsMapProvider.future);
    final tasks = await ref.read(allTasksProvider.future);
    if (!mounted) return;

    final data = WeeklyRetroData.build(
      weekStart: weekStart,
      allStats: allStats,
      goals: goals,
      ratings: ratings,
      tasks: tasks,
    );
    // Неделя прошла мимо приложения — показывать нечего. Отметку НЕ ставим:
    // если данные за ту неделю появятся позже на этой же неделе, разбор
    // всё-таки покажется.
    if (data.isEmpty) return;

    await showWeeklyRetroSheet(context, data: data);
    // Отмечаем показанным в любом случае — даже если закрыли по Esc: это
    // сводка, а не вопрос, и повторять её при каждом запуске незачем.
    await controller.markShown(weekStart);
  }

  @override
  void dispose() {
    _transferTimer?.cancel();
    super.dispose();
  }

  Future<void> _maybeShowCatchup() async {
    final controller = ref.read(transferPromptControllerProvider);
    final now = DateTime.now();
    if (!controller.missedBoundary(now)) return;
    final taskCandidates = controller.collectTaskCandidates(now);
    final goalCandidates = controller.collectGoalCandidates(now);
    if (taskCandidates.isEmpty && goalCandidates.isEmpty) {
      await controller.markChecked(now);
      return;
    }
    if (!mounted) return;
    final selection = await showTransferCatchupSheet(
      context,
      tasks: taskCandidates,
      goals: goalCandidates,
    );
    if (selection != null) {
      final taskRepo = ref.read(taskRepositoryProvider);
      final goalRepo = ref.read(goalRepositoryProvider);
      final chosenTasks = taskCandidates
          .where((t) => selection.taskIds.contains(t.id))
          .toList();
      final declinedTasks = taskCandidates
          .where((t) => !selection.taskIds.contains(t.id))
          .toList();
      final chosenGoals = goalCandidates
          .where((g) => selection.goalIds.contains(g.id))
          .toList();
      final declinedGoals = goalCandidates
          .where((g) => !selection.goalIds.contains(g.id))
          .toList();
      await taskRepo.transferSelected(chosenTasks, now: DateTime.now());
      for (final t in declinedTasks) {
        await taskRepo.declineTransfer(t);
      }
      await goalRepo.transferSelected(chosenGoals, now: DateTime.now());
      for (final g in declinedGoals) {
        await goalRepo.declineTransfer(g);
      }
    }
    await controller.markChecked(DateTime.now());
  }

  DateTime _nextFourAm() {
    final now = DateTime.now();
    final candidate = DateTime(now.year, now.month, now.day, 4);
    return now.isBefore(candidate)
        ? candidate
        : candidate.add(const Duration(days: 1));
  }

  /// Живой момент переноса (приложение открыто, наступило 4:00): плашки
  /// «перенести или нет» по очереди — следующая ждёт, пока предыдущая не
  /// исчезнет (см. showTransferPromptBanner). Самоперепланируется на
  /// следующий день, как и ночной таймер в main.dart.
  void _scheduleTransferPrompt() {
    final delay = _nextFourAm().difference(DateTime.now());
    _transferTimer = Timer(delay, () async {
      await _runTransferPrompt();
      if (mounted) _scheduleTransferPrompt();
    });
  }

  Future<void> _runTransferPrompt() async {
    final controller = ref.read(transferPromptControllerProvider);
    final now = DateTime.now();
    final taskCandidates = controller.collectTaskCandidates(now);
    final goalCandidates = controller.collectGoalCandidates(now);
    if (taskCandidates.isEmpty && goalCandidates.isEmpty) {
      await controller.markChecked(now);
      return;
    }
    final taskRepo = ref.read(taskRepositoryProvider);
    final goalRepo = ref.read(goalRepositoryProvider);
    for (final t in taskCandidates) {
      if (!mounted) return;
      final result = await showTransferPromptBanner(
        context,
        title: t.title,
        icon: Icons.east,
      );
      if (result == true) {
        await taskRepo.transferSelected([t], now: DateTime.now());
      } else if (result == false) {
        await taskRepo.declineTransfer(t);
      }
    }
    for (final g in goalCandidates) {
      if (!mounted) return;
      final result = await showTransferPromptBanner(
        context,
        title: g.title,
        icon: Icons.east,
      );
      if (result == true) {
        await goalRepo.transferSelected([g], now: DateTime.now());
      } else if (result == false) {
        await goalRepo.declineTransfer(g);
      }
    }
    await controller.markChecked(DateTime.now());
  }

  @override
  Widget build(BuildContext context) {
    final tabs = _RootScaffold._tabs;
    // Слушаем агрегат ачивок: при разблокировке новых — показываем плашку.
    // Первый «посев» (после установки) проходит молча внутри repo.sync.
    ref.listen<AchievementStats?>(achievementStatsProvider, (prev, next) async {
      if (next == null) return;
      final unlocked = evaluateAchievements(next)
          .where((a) => a.unlocked)
          .map((a) => a.def.id)
          .toSet();
      final newly =
          await ref.read(achievementsRepositoryProvider).sync(unlocked);
      // Показываем по очереди — следующая плашка выезжает только после того,
      // как предыдущая ушла, иначе они наслаиваются друг на друга.
      for (final id in newly) {
        if (!context.mounted) return;
        final def = kAchievements.firstWhere((d) => d.id == id);
        await showAchievementPopup(context, def);
      }
    });

    final location = GoRouterState.of(context).uri.path;
    final selected = tabs
        .indexWhere((t) => location.startsWith(t.path))
        .clamp(0, tabs.length - 1);

    // Направление сдвига: +1 двигаемся вправо (на дальнюю вкладку), −1 влево.
    final dir = selected >= _prevIndex ? 1.0 : -1.0;
    _prevIndex = selected;

    return Scaffold(
      // «Бумажный сдвиг» (220 мс): новая страница въезжает с лёгким смещением
      // в сторону движения и проявляется, старая — уезжает и гаснет. Ключ по
      // пути вкладки, чтобы AnimatedSwitcher распознал смену.
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        switchInCurve: AppColors.easeOut,
        switchOutCurve: AppColors.easeOut,
        transitionBuilder: (child, animation) {
          final slide = Tween<Offset>(
            begin: Offset(0.04 * dir, 0),
            end: Offset.zero,
          ).animate(animation);
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(position: slide, child: child),
          );
        },
        // Не накладываем уходящую и въезжающую страницы стопкой по центру —
        // оставляем обычный размер, верхнюю кладём поверх.
        layoutBuilder: (current, previous) => Stack(
          alignment: Alignment.topCenter,
          children: [...previous, if (current != null) current],
        ),
        child: KeyedSubtree(
          key: ValueKey(tabs[selected].path),
          child: widget.child,
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: selected,
        onDestinationSelected: (i) => context.go(tabs[i].path),
        destinations: [
          for (final t in tabs)
            NavigationDestination(
              icon: Icon(t.icon),
              selectedIcon: Icon(t.iconSelected),
              label: _tabLabel(context, t.path),
            ),
        ],
      ),
    );
  }
}

String _tabLabel(BuildContext context, String path) {
  final l10n = context.l10n;
  return switch (path) {
    '/today' => l10n.navToday,
    '/stats' => l10n.navStats,
    '/goals' => l10n.navGoals,
    '/profile' => l10n.navProfile,
    _ => '',
  };
}

class _TabSpec {
  const _TabSpec(this.path, this.icon, this.iconSelected);
  final String path;
  final IconData icon;
  final IconData iconSelected;
}
