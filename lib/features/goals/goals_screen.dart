import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../core/create_action.dart';
import '../../core/current_time_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/appearance.dart';
import '../../core/utils/date_utils.dart';
import '../../core/utils/format_utils.dart';
import '../../data/models/goal.dart';
import '../../data/models/task.dart' show SubTask, TaskPriority;
import '../../data/repositories/backlog_repository.dart';
import '../../data/repositories/goal_repository.dart';
import '../../data/repositories/rating_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/l10n_extensions.dart';
import '../search/global_search.dart';
import '../../widgets/backlog_nudge_card.dart';
import '../../widgets/draw_check_box.dart';
import '../../widgets/esc_dismissible.dart';
import '../../widgets/fancy_dialog.dart';
import '../../widgets/fancy_toast.dart';
import '../../widgets/glow_fab.dart';
import '../../widgets/pill_toggle.dart';
import '../../widgets/productivity_ring.dart';
import '../../widgets/seg_chip.dart';
import '../../widgets/stagger_reveal.dart';
import '../../widgets/star_rating.dart';
import '../../widgets/subtask_checklist.dart';
import '../../widgets/tag_mini.dart';
import '../backlog/backlog_screen.dart';

/// intl отдаёт название месяца в «естественном» регистре языка (в русском —
/// строчными: «июль»). Для заголовка календаря хотим заглавную первую букву
/// независимо от языка.
String _capitalize(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

// ─── Главный экран ───────────────────────────────────────────────────────────

class GoalsScreen extends ConsumerStatefulWidget {
  const GoalsScreen({super.key});

  @override
  ConsumerState<GoalsScreen> createState() => _GoalsScreenState();
}

class _GoalsScreenState extends ConsumerState<GoalsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  /// Текущий выбранный период для каждой вкладки (порядок = GoalPeriod.values).
  late List<GoalPeriodRef> _refs;

  GoalPeriodRef get _currentRef => _refs[_tabController.index];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _refs =
        GoalPeriod.values.map((p) => GoalPeriodRef.current(p, now)).toList();
    _tabController =
        TabController(length: GoalPeriod.values.length, vsync: this)
          ..addListener(() => setState(() {}));
    // Регистрируем «создать» для Ctrl+N: новая цель для текущего периода.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(createActionProvider.notifier).state = () {
        if (mounted) _showAddGoalSheet(context);
      };
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _navigate(int tabIndex, GoalPeriodRef newRef) {
    setState(() => _refs[tabIndex] = newRef);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.goalsTitle),
        actions: [
          IconButton(
            tooltip: l10n.searchGoalsTooltip,
            icon: const Icon(Icons.search),
            onPressed: () async {
              final goal = await showSearch<Goal?>(
                context: context,
                delegate: GoalSearchDelegate(
                  goals: ref.read(allGoalsProvider).value ?? const [],
                  searchFieldLabel: l10n.searchGoalsHint,
                ),
              );
              if (goal != null && mounted) {
                final idx = GoalPeriod.values.indexOf(goal.period);
                setState(() => _refs[idx] = goal.ref);
                _tabController.animateTo(idx);
              }
            },
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: PillToggle<int>(
              selected: _tabController.index,
              segments: [
                (0, l10n.goalsPeriodWeek),
                (1, l10n.goalsPeriodMonth),
                (2, l10n.goalsPeriodSeason),
                (3, l10n.goalsPeriodYear),
              ],
              // animateTo меняет вкладку; слушатель контроллера (addListener в
              // initState) делает setState → пилюля едет и при свайпе страниц.
              onChanged: (i) => _tabController.animateTo(i),
            ),
          ),
        ),
      ),
      floatingActionButton: _currentRef.isPast()
          ? null
          : GlowFab(
              onPressed: () => _showAddGoalSheet(context),
              icon: Icons.add,
              label: l10n.addGoalFabLabel,
            ),
      body: TabBarView(
        controller: _tabController,
        children: [
          for (var i = 0; i < _refs.length; i++)
            _GoalsList(
              periodRef: _refs[i],
              // Активна = текущая вкладка. Каскад на вкладке стартует, только
              // когда она становится активной (а не пока строится за кадром).
              active: _tabController.index == i,
              onPrev: () => _navigate(i, _refs[i].previous),
              onNext: () => _navigate(i, _refs[i].next),
            ),
        ],
      ),
    );
  }

  Future<void> _showAddGoalSheet(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) =>
          EscDismissible(child: _GoalFormSheet(periodRef: _currentRef)),
    );
  }
}

// ─── Срочность цели ──────────────────────────────────────────────────────────

enum _GoalUrgency { upcoming, normal, active, urgent, overdue }

/// Вычисляет уровень срочности/актуальности невыполненной цели.
///
/// upcoming — дата начала ещё не наступила (startDate в будущем).
/// active   — цель началась (startDate задана и наступила), дедлайн не горит.
/// urgent   — дедлайн (или конец периода) близко (≤ urgencyThreshold дней).
/// overdue  — период уже завершился.
/// normal   — нет startDate, не срочно.
_GoalUrgency _calcGoalUrgency(Goal goal) {
  if (goal.completed) return _GoalUrgency.normal;

  final today = dateOnly(DateTime.now());

  // Период закончился → просрочено
  if (today.isAfter(goal.periodEnd)) return _GoalUrgency.overdue;

  // Дата начала ещё не наступила → ещё не актуальна
  if (goal.startDate != null && today.isBefore(goal.startDate!)) {
    return _GoalUrgency.upcoming;
  }

  // Порог срочности считаем по дедлайну (если задан) или концу периода
  final effectiveDeadline = goal.deadline ?? goal.periodEnd;
  final daysLeft = effectiveDeadline.difference(today).inDays;
  if (daysLeft <= goal.ref.urgencyThreshold) return _GoalUrgency.urgent;

  // Цель уже началась (startDate задана и наступила) — подсвечиваем активной
  if (goal.startDate != null) return _GoalUrgency.active;

  return _GoalUrgency.normal;
}

// ─── Список целей за период ───────────────────────────────────────────────────

class _GoalsList extends ConsumerWidget {
  const _GoalsList({
    required this.periodRef,
    required this.active,
    required this.onPrev,
    required this.onNext,
  });

  final GoalPeriodRef periodRef;

  /// Вкладка активна (видима пользователю) — каскад появления стартует только
  /// тогда, иначе он прошёл бы за кадром (TabBarView строит соседнюю заранее).
  final bool active;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  bool get isPast => periodRef.isPast();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(goalRepositoryProvider);

    return StreamBuilder<List<Goal>>(
      stream: repo.watchGoalsForRef(periodRef),
      builder: (context, snap) {
        final l10n = context.l10n;
        final ru = Localizations.localeOf(context).languageCode == 'ru';
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final goals = snap.data!;
        final done = goals.where((g) => g.completed).length;
        // Дробная доля: цель-счётчик 6/12 даёт 0.5.
        final fraction = goals.fold<double>(0, (s, g) => s + g.completionValue);
        final value = goals.isEmpty ? null : fraction / goals.length;

        // «В срок» по целям текущего периода
        final completedGoals = goals.where((g) => g.completed).toList();
        final onTimeGoals = completedGoals.where((g) => g.isOnTime).length;
        final lateGoals = completedGoals.length - onTimeGoals;
        final timelinessValue =
            completedGoals.isEmpty ? null : onTimeGoals / completedGoals.length;

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          children: [
            const SizedBox(height: 16),
            // ── Кольца прогресса ──────────────────────────────────────────
            _GoalDualRingRow(
              value: value,
              done: done,
              completedFraction: fraction,
              total: goals.length,
              timeliness: timelinessValue,
              onTimeCount: onTimeGoals,
              lateCount: lateGoals,
            ),
            // ── Оценка прошедшего периода (рефлексия) ─────────────────────
            if (periodRef.endInclusive.isBefore(dateOnly(DateTime.now())))
              _PeriodRatingRow(periodRef: periodRef),
            // ── Навигация по периоду ──────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  tooltip: l10n.prevPeriodTooltip,
                  onPressed: onPrev,
                ),
                Flexible(
                  child: Text(
                    periodRef.labelFor(ru),
                    style: Theme.of(context).textTheme.titleMedium,
                    textAlign: TextAlign.center,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  tooltip: l10n.nextPeriodTooltip,
                  onPressed: onNext,
                ),
              ],
            ),
            // ── Карточка «Недостигнутые цели (N)» ──────────────────────
            Consumer(
              builder: (ctx, ref, _) {
                final items =
                    ref.watch(goalBacklogItemsProvider).value ?? const [];
                if (items.isEmpty) return const SizedBox.shrink();
                final oldest = items
                    .reduce((a, b) => a.addedAt.isBefore(b.addedAt) ? a : b);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: BacklogNudgeCard(
                    icon: Icons.flag_outlined,
                    title: l10n.goalBacklogChip(items.length),
                    subtitle: l10n.backlogOldestLabel(oldest.title),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const GoalBacklogScreen(),
                      ),
                    ),
                  ),
                );
              },
            ),
            // ── Кнопки действий (справа) ──────────────────────────────────
            // Wrap, а не Row: на узком экране кнопки не влезают в строку и
            // Row обрезал «Удалить все» (overflow). Wrap переносит на след. строку.
            if (goals.isNotEmpty)
              Wrap(
                alignment: WrapAlignment.end,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (isPast) ...[
                    Builder(builder: (ctx) {
                      final hasTransferable = goals.any((g) =>
                          !g.completed &&
                          !g.isTransferred &&
                          g.transferredFromId == null);
                      if (!hasTransferable) return const SizedBox.shrink();
                      return TextButton.icon(
                        onPressed: () => _transferAll(context, ref, goals),
                        icon: const Icon(Icons.east, size: 17),
                        label: Text(l10n.transferAllBtn),
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                        ),
                      );
                    }),
                    const SizedBox(width: 4),
                  ],
                  TextButton.icon(
                    onPressed: () => _copyGoals(context, ref, goals),
                    icon: const Icon(Icons.copy_all_outlined, size: 17),
                    label: Text(l10n.copyBtn),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                    ),
                  ),
                  if (!isPast) ...[
                    const SizedBox(width: 4),
                    TextButton.icon(
                      onPressed: () => _deleteAll(context, ref),
                      icon: const Icon(Icons.delete_sweep_outlined, size: 17),
                      label: Text(l10n.deleteAllBtn),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.danger,
                        visualDensity: VisualDensity.compact,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                      ),
                    ),
                  ],
                ],
              ),
            const SizedBox(height: 4),
            // ── Пустое состояние или список ───────────────────────────────
            if (goals.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: NotebookEmptyState(
                  text:
                      isPast ? l10n.emptyGoalsPastState : l10n.emptyGoalsState,
                ),
              )
            else
              _GoalSections(
                goals: goals,
                isPast: isPast,
                repo: repo,
                active: active,
              ),
          ],
        );
      },
    );
  }

  Future<void> _transferAll(
      BuildContext context, WidgetRef ref, List<Goal> goals) async {
    final repo = ref.read(goalRepositoryProvider);
    final currentRef = GoalPeriodRef.current(periodRef.period, DateTime.now());
    for (final g in goals) {
      if (!g.completed && !g.isTransferred && g.transferredFromId == null) {
        await repo.transferGoal(g, targetRef: currentRef);
      }
    }
  }

  Future<void> _copyGoals(
      BuildContext context, WidgetRef ref, List<Goal> goals) async {
    final repo = ref.read(goalRepositoryProvider);
    final GoalPeriodRef? target = await _pickGoalCopyTarget(context, periodRef);
    if (target == null || !context.mounted) return;

    await repo.copyGoalsTo(goals: goals, target: target);

    if (context.mounted) {
      final ru = Localizations.localeOf(context).languageCode == 'ru';
      showFancyToast(context,
          message: context.l10n.copiedToPeriodToast(target.labelFor(ru)));
    }
  }

  Future<void> _deleteAll(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final repo = ref.read(goalRepositoryProvider);
    final confirmed = await showFancyDialog<bool>(
      context: context,
      icon: Icons.delete_sweep_rounded,
      iconColor: AppColors.danger,
      title: l10n.deleteAllGoalsConfirmTitle,
      content: l10n.cannotUndo,
      actions: (ctx) => [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(l10n.cancel),
        ),
        const SizedBox(width: 8),
        FilledButton(
          autofocus: true,
          style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(l10n.delete),
        ),
      ],
    );
    if (confirmed == true) {
      await repo.deleteAllForPeriod(periodRef);
    }
  }
}

/// Выбор целевого периода для копирования цели — зависит от типа периода
/// [source] (та же логика для копирования всех целей периода и одной цели).
Future<GoalPeriodRef?> _pickGoalCopyTarget(
    BuildContext context, GoalPeriodRef source) async {
  final l10n = context.l10n;
  switch (source.period) {
    case GoalPeriod.week:
      final picked = await showFancyRawDialog<DateTime>(
        context: context,
        barrierLabel: l10n.copyToWeekBarrier,
        builder: (ctx) => _WeekPickerDialog(initialWeekStart: source.start),
      );
      if (picked == null) return null;
      final ws = startOfWeek(picked);
      return GoalPeriodRef(
        period: GoalPeriod.week,
        year: ws.year,
        weekStart: ws,
      );
    case GoalPeriod.month:
      final picked = await showFancyRawDialog<DateTime>(
        context: context,
        barrierLabel: l10n.copyToMonthBarrier,
        builder: (ctx) => _MonthPickerDialog(initialYear: source.year),
      );
      if (picked == null) return null;
      return GoalPeriodRef(
        period: GoalPeriod.month,
        year: picked.year,
        month: picked.month,
      );
    case GoalPeriod.season:
      final picked = await showFancyRawDialog<(int, int)>(
        context: context,
        barrierLabel: l10n.copyToSeasonBarrier,
        builder: (ctx) => _SeasonPickerDialog(initialYear: source.year),
      );
      if (picked == null) return null;
      return GoalPeriodRef(
        period: GoalPeriod.season,
        year: picked.$1,
        season: picked.$2,
      );
    case GoalPeriod.year:
      final picked = await showFancyRawDialog<int>(
        context: context,
        barrierLabel: l10n.copyToYearBarrier,
        builder: (ctx) => _YearPickerDialog(
          todayYear: DateTime.now().year,
          sourceYear: source.year,
        ),
      );
      if (picked == null) return null;
      return GoalPeriodRef(period: GoalPeriod.year, year: picked);
  }
}

// ─── Секции целей (требует внимания / невыполненные / выполненные) ───────────

class _GoalSections extends ConsumerStatefulWidget {
  const _GoalSections({
    required this.goals,
    required this.isPast,
    required this.repo,
    required this.active,
  });

  final List<Goal> goals;
  final bool isPast;
  final GoalRepository repo;

  /// Вкладка активна — каскад появления целей стартует только тогда.
  final bool active;

  @override
  ConsumerState<_GoalSections> createState() => _GoalSectionsState();
}

class _GoalSectionsState extends ConsumerState<_GoalSections> {
  static const _dur = Duration(milliseconds: 280);

  final _urgKey = GlobalKey<AnimatedListState>();
  final _incKey = GlobalKey<AnimatedListState>();
  final _comKey = GlobalKey<AnimatedListState>();

  late List<Goal> _urg; // требует внимания (urgent + overdue)
  late List<Goal> _inc; // невыполненные (обычные)
  late List<Goal> _com; // выполненные
  bool _comExpanded = true;

  /// «Требует внимания» имеет смысл только пока период ещё идёт — цель ещё
  /// можно успеть закрыть. Для прошедших периодов (widget.isPast) период уже
  /// завершился: невыполненная цель — это просто «не выполнена», а не
  /// «горящий дедлайн», поэтому в _urg такие цели не попадают (иначе они
  /// зависают в жёлтой секции «Требует внимания» даже когда сделать уже
  /// ничего нельзя).
  bool _isAttention(Goal g) {
    if (widget.isPast) return false;
    final u = _calcGoalUrgency(g);
    return u == _GoalUrgency.urgent || u == _GoalUrgency.overdue;
  }

  /// Невыполненные — по приоритету (высокий раньше), при равенстве — по
  /// дате создания (стабильный порядок, не «прыгает» без причины). У целей
  /// нет времени дня, поэтому, в отличие от задач, приоритет — единственный
  /// критерий сортировки, а не запасной для «задач без времени».
  static List<Goal> _sortedByPriority(Iterable<Goal> goals) {
    final list = goals.toList();
    list.sort((a, b) {
      final byPriority = b.priority.index.compareTo(a.priority.index);
      if (byPriority != 0) return byPriority;
      return a.createdAt.compareTo(b.createdAt);
    });
    return list;
  }

  @override
  void initState() {
    super.initState();
    _urg = _sortedByPriority(
        widget.goals.where((g) => !g.completed && _isAttention(g)));
    _inc = _sortedByPriority(
        widget.goals.where((g) => !g.completed && !_isAttention(g)));
    _com = widget.goals.where((g) => g.completed).toList();
  }

  @override
  void didUpdateWidget(_GoalSections old) {
    super.didUpdateWidget(old);
    if (old.goals != widget.goals) _syncAll(widget.goals);
  }

  void _syncAll(List<Goal> goals) {
    _diff(
        _urg,
        _sortedByPriority(goals.where((g) => !g.completed && _isAttention(g))),
        _urgKey);
    _diff(
        _inc,
        _sortedByPriority(goals.where((g) => !g.completed && !_isAttention(g))),
        _incKey);
    _diff(_com, goals.where((g) => g.completed).toList(), _comKey);
    setState(() {});
  }

  void _diff(List<Goal> cur, List<Goal> nxt, GlobalKey<AnimatedListState> key) {
    // Удаляем исчезнувшие (с конца, чтобы не сбить индексы)
    for (var i = cur.length - 1; i >= 0; i--) {
      if (!nxt.any((g) => g.id == cur[i].id)) {
        final removed = cur.removeAt(i);
        key.currentState?.removeItem(
          i,
          (ctx, anim) => _animTile(removed, anim, swipeable: false),
          duration: _dur,
        );
      }
    }
    // Вставляем новые и переставляем существующие, чей порядок в nxt
    // изменился (например, поменяли приоритет — цель должна переехать
    // сразу, а не просто молча обновить данные на старом месте). Идём по
    // nxt слева направо: к этому моменту cur[0..i) уже точно совпадает с
    // nxt[0..i), а хвост cur[i..) содержит то, что ещё предстоит расставить.
    for (var i = 0; i < nxt.length; i++) {
      final target = nxt[i];
      final curIdx = cur.indexWhere((g) => g.id == target.id);
      if (curIdx == -1) {
        // Новый элемент — вставляем на нужную позицию.
        cur.insert(i, target);
        key.currentState?.insertItem(i, duration: _dur);
      } else if (curIdx != i) {
        // Уже есть, но не на своём месте — переставляем (снять со старой
        // позиции и поставить на новую), а не оставлять как было.
        cur.removeAt(curIdx);
        key.currentState?.removeItem(
          curIdx,
          (ctx, anim) => _animTile(target, anim, swipeable: false),
          duration: _dur,
        );
        cur.insert(i, target);
        key.currentState?.insertItem(i, duration: _dur);
      } else if (target != cur[i]) {
        cur[i] = target;
      }
    }
  }

  Widget _animTile(Goal goal, Animation<double> anim,
      {bool swipeable = true, int? revealIndex}) {
    final tile = SizeTransition(
      sizeFactor: CurvedAnimation(parent: anim, curve: Curves.easeInOut),
      child: FadeTransition(
        opacity: CurvedAnimation(parent: anim, curve: Curves.easeIn),
        child: _GoalTile(
          goal: goal,
          urgency: _calcGoalUrgency(goal),
          isPast: widget.isPast,
          repo: widget.repo,
          swipeable: swipeable,
        ),
      ),
    );
    // Каскадное появление (как у задач); не применяем к анимации удаления.
    // active — каскад стартует, только когда вкладка видима (см. StaggerReveal).
    if (revealIndex == null) return tile;
    return StaggerReveal(
      key: ValueKey('reveal-${goal.id}'),
      index: revealIndex,
      active: widget.active,
      child: tile,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;

    // При каждом тике таймера пересчитываем срочность — цели могут переходить
    // в «Требует внимания» и обратно сами по себе, без изменения данных
    // (раньше секции целей это не отслеживали вовсе, в отличие от задач).
    ref.listen(currentTimeProvider, (_, __) => _syncAll(widget.goals));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Требует внимания ──────────────────────────────────────────────
        ClipRect(
          child: AnimatedAlign(
            duration: _dur,
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            heightFactor: _urg.isNotEmpty ? 1.0 : 0.0,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 6, left: 2),
                  child: Row(
                    children: [
                      Icon(Icons.access_alarm_rounded,
                          size: 15, color: AppColors.warning),
                      const SizedBox(width: 5),
                      Text(
                        l10n.urgentSectionLabel(_urg.length),
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: AppColors.warning,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                ),
                AnimatedList(
                  key: _urgKey,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  initialItemCount: _urg.length,
                  itemBuilder: (ctx, i, anim) {
                    if (i >= _urg.length) return const SizedBox.shrink();
                    return _animTile(_urg[i], anim, revealIndex: i);
                  },
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),

        // ── Невыполненные ─────────────────────────────────────────────────
        AnimatedList(
          key: _incKey,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          initialItemCount: _inc.length,
          itemBuilder: (ctx, i, anim) {
            if (i >= _inc.length) return const SizedBox.shrink();
            return _animTile(_inc[i], anim, revealIndex: i);
          },
        ),

        // ── Выполненные ───────────────────────────────────────────────────
        if (_com.isNotEmpty) ...[
          const SizedBox(height: 4),
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => setState(() => _comExpanded = !_comExpanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
              child: Row(
                children: [
                  AnimatedRotation(
                    turns: _comExpanded ? 0.25 : 0,
                    duration: _dur,
                    child: Icon(
                      Icons.chevron_right,
                      size: 18,
                      color:
                          theme.colorScheme.onSurface.withValues(alpha: 0.55),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    l10n.completedSectionLabel(_com.length),
                    style: theme.textTheme.labelMedium?.copyWith(
                      color:
                          theme.colorScheme.onSurface.withValues(alpha: 0.55),
                    ),
                  ),
                ],
              ),
            ),
          ),
          ClipRect(
            child: AnimatedAlign(
              duration: _dur,
              curve: Curves.easeInOut,
              alignment: Alignment.topCenter,
              heightFactor: _comExpanded ? 1.0 : 0.0,
              child: AnimatedList(
                key: _comKey,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                initialItemCount: _com.length,
                itemBuilder: (ctx, i, anim) {
                  if (i >= _com.length) return const SizedBox.shrink();
                  return _animTile(_com[i], anim, revealIndex: i);
                },
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ─── Плитка цели ─────────────────────────────────────────────────────────────

enum _GoalAction { transfer, edit, copy, delete }

class _GoalTile extends StatelessWidget {
  const _GoalTile({
    required this.goal,
    required this.urgency,
    required this.isPast,
    required this.repo,
    this.swipeable = true,
  });

  final Goal goal;
  final _GoalUrgency urgency;
  final bool isPast;

  /// false — во время анимации удаления из AnimatedList (без Dismissible).
  final bool swipeable;
  final GoalRepository repo;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final isDeadlineOverdue = goal.deadline != null &&
        !goal.completed &&
        goal.deadline!.isBefore(today);

    final isLateCompleted = goal.completed && !goal.isOnTime;

    final theme = Theme.of(context);
    final l10n = context.l10n;

    // Редизайн «Живая бумага»: корешок 4px + лёгкий тинт вместо заливки.
    Color? spineColor;
    Color? cardColor;
    // «Активная» цель (период уже начался) — единственный случай, где тинт
    // должен быть НЕПРОЗРАЧНЫМ: карточка обозначает то, чем нужно заниматься
    // прямо сейчас, и не должна казаться блёклой/просвечивающей (особенно
    // заметно на фоне «Точки» — сквозь alpha-тинт видны точки).
    var isActiveState = false;
    // Выполненная — зелёный корешок (независимо от периода: и в активном, и
    // в прошлом), кроме выполненных с опозданием — те остаются янтарными.
    // Порядок проверок — как у задач (_TaskTile): completed проверяется
    // ПЕРВЫМ, до isPast/срочности, иначе достигнутая в активном периоде цель
    // оставалась бы без подсветки вообще.
    if (goal.completed) {
      spineColor = isLateCompleted ? AppColors.warning : AppColors.success;
    } else if (isPast) {
      spineColor = AppColors.danger;
    } else {
      // Активный период: акцент по срочности/состоянию.
      spineColor = switch (urgency) {
        _GoalUrgency.overdue => AppColors.danger,
        _GoalUrgency.urgent => AppColors.warning,
        _GoalUrgency.active => theme.colorScheme.primary,
        _GoalUrgency.upcoming || _GoalUrgency.normal => null,
      };
      isActiveState = urgency == _GoalUrgency.active;
    }
    cardColor ??= spineColor == null
        ? null
        : isActiveState
            // Тот же тинт, но заранее «впечённый» в сплошной цвет карточки —
            // альфа-канала не остаётся, фон экрана сквозь неё не виден.
            // Альфа выше, чем у остальных тинтов (0.08): на тёплом тёмном
            // cardColor в dark-теме 8% primarySoft даёт почти нейтральный
            // серый (каналы RGB после смешивания почти равны) — с 0.18
            // синий оттенок читается уверенно в обеих темах.
            ? Color.alphaBlend(
                spineColor.withValues(alpha: 0.18),
                theme.cardTheme.color ?? theme.cardColor,
              )
            : spineColor.withValues(alpha: 0.08);

    final Widget baseLeading = (goal.isCounter || goal.isChecklist)
        ? _progressLeading(context, theme)
        : isPast
            ? Icon(
                !goal.completed
                    ? Icons.cancel_outlined
                    : isLateCompleted
                        ? Icons.watch_later_outlined
                        : Icons.check_circle,
                color: !goal.completed
                    ? AppColors.danger
                    : isLateCompleted
                        ? AppColors.warning
                        : AppColors.success,
              )
            : DrawCheckBox(
                value: goal.completed,
                onChanged: (_) => _onToggle(context),
              );
    // Перенесённая цель остаётся окрашенной как обычная невыполненная/
    // выполненная — просто получает маленький бейдж-стрелку поверх иконки,
    // а не полностью серое оформление (см. фикс «должна быть красной»).
    final Widget leadingWidget = goal.isTransferred
        ? _withTransferredBadge(context, baseLeading)
        : baseLeading;

    final listTile = ListTile(
      leading: leadingWidget,
      title: Row(
        children: [
          Flexible(
            child: Text(
              goal.title,
              style: goal.completed
                  ? const TextStyle(
                      decoration: TextDecoration.lineThrough,
                      color: AppColors.textSecondary,
                    )
                  : null,
            ),
          ),
          if (goal.priority != TaskPriority.none) ...[
            const SizedBox(width: 6),
            Icon(
              switch (goal.priority) {
                TaskPriority.high => Icons.keyboard_double_arrow_up,
                TaskPriority.medium => Icons.keyboard_arrow_up,
                _ => Icons.keyboard_arrow_down,
              },
              size: 16,
              color: switch (goal.priority) {
                TaskPriority.high => AppColors.danger,
                TaskPriority.medium => AppColors.warning,
                _ => AppColors.textSecondary,
              },
            ),
          ],
        ],
      ),
      subtitle: _buildSubtitle(context, isDeadlineOverdue),
      // Перенесённый оригинал — «история неизменна», как у задач: ни меню, ни
      // кнопки переноса (свайп-удаление тоже отключено — см. ниже по методу).
      trailing: goal.isTransferred
          ? null
          : isPast
              ? (_canTransferGoal()
                  ? IconButton(
                      tooltip: l10n.transferToCurrentPeriodTooltip,
                      icon: Icon(Icons.east, color: theme.colorScheme.primary),
                      onPressed: () => _handleTransfer(),
                    )
                  : null)
              : PopupMenuButton<_GoalAction>(
                  icon: const Icon(Icons.more_vert),
                  onSelected: (action) {
                    if (action == _GoalAction.edit) {
                      _showEditSheet(context);
                    } else if (action == _GoalAction.copy) {
                      _copyGoalToPeriod(context);
                    } else if (action == _GoalAction.transfer) {
                      _handleTransferEarly();
                    } else {
                      repo.deleteGoal(goal.id);
                    }
                  },
                  itemBuilder: (_) => [
                    // Досрочный перенос — доступен, только когда цель уже
                    // «Требует внимания» (близко к дедлайну/концу периода).
                    // Аналог «ночного окна» у задач: не ждать, пока период
                    // формально закончится, а подтолкнуть цель в следующий
                    // период заранее, пока ещё есть время среагировать.
                    if (_canTransferGoalEarly())
                      PopupMenuItem(
                        value: _GoalAction.transfer,
                        child: ListTile(
                          leading: Icon(Icons.east,
                              color: theme.colorScheme.primary),
                          title: Text(l10n.transferForwardTooltip),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    PopupMenuItem(
                      value: _GoalAction.edit,
                      child: ListTile(
                        leading: const Icon(Icons.edit_outlined),
                        title: Text(l10n.editMenuItem),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    PopupMenuItem(
                      value: _GoalAction.copy,
                      child: ListTile(
                        leading: const Icon(Icons.copy_all_outlined),
                        title: Text(l10n.copyBtn),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    PopupMenuItem(
                      value: _GoalAction.delete,
                      child: ListTile(
                        leading: const Icon(Icons.delete_outline,
                            color: AppColors.danger),
                        title: Text(l10n.deleteMenuItem,
                            style: const TextStyle(color: AppColors.danger)),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ],
                ),
    );

    final Widget content = goal.isCounter
        ? Column(
            mainAxisSize: MainAxisSize.min,
            children: [listTile, _buildCounterBar(context, theme)],
          )
        : goal.isChecklist
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  listTile,
                  SubtaskChecklist(
                    subtasks: goal.subtasks,
                    readOnly: isPast,
                    onToggle: (s) => _toggleSub(context, s),
                  ),
                ],
              )
            : listTile;

    // Кросс-фейд тинта состояния (260 мс) — как на экране задач.
    final Widget tileChild = spineColor == null
        ? content
        : Stack(
            children: [
              content,
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 260),
                  curve: AppColors.easeOut,
                  width: 4,
                  color: spineColor,
                ),
              ),
            ],
          );

    // Кросс-фейд только при наличии тинта. Без него (cardColor == null) —
    // обычный Card: ColorTween(end: null) падает (TweenAnimationBuilder требует
    // non-null end) → в release серый ErrorWidget во всю высоту.
    final Widget tile = cardColor == null
        ? Card(
            margin: const EdgeInsets.only(bottom: 8),
            // Всегда обрезаем по скруглению — иначе вспышка от нажатия
            // (чекбокс, меню ⋮) вылезает за уголки карточки без корешка.
            clipBehavior: Clip.antiAlias,
            child: tileChild,
          )
        : TweenAnimationBuilder<Color?>(
            duration: const Duration(milliseconds: 260),
            curve: AppColors.easeOut,
            tween: ColorTween(end: cardColor),
            child: tileChild,
            builder: (context, animColor, child) => Card(
              margin: const EdgeInsets.only(bottom: 8),
              color: animColor,
              // Всегда обрезаем по скруглению — иначе вспышка от нажатия
              // (чекбокс, меню ⋮) вылезает за уголки карточки без корешка.
              clipBehavior: Clip.antiAlias,
              child: child,
            ),
          );

    // Цель ещё не началась (startDate в будущем) → слегка прозрачная
    final Widget maybeFaded = urgency == _GoalUrgency.upcoming
        ? Opacity(opacity: 0.45, child: tile)
        : tile;

    // Прошлые периоды — только просмотр: свайп отключён.
    if (isPast) return maybeFaded;

    // Перенесённый оригинал — «история неизменна», как у задач: свайп-удаление
    // тоже отключено (копию, если она не выполнена, всё ещё можно удалить
    // обычным способом — тогда она уходит в бэклог, см. GoalRepository.deleteGoal).
    if (goal.isTransferred) return maybeFaded;

    // Во время анимации удаления из AnimatedList — без Dismissible.
    if (!swipeable) return maybeFaded;

    return Dismissible(
      key: ValueKey(goal.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        color: AppColors.danger.withValues(alpha: 0.12),
        child: const Icon(Icons.delete_outline, color: AppColors.danger),
      ),
      onDismissed: (_) => repo.deleteGoal(goal.id),
      child: maybeFaded,
    );
  }

  /// Счётчик цели: полоса прогресса сверху, под ней по центру [−] значение [+].
  /// Тап по значению — ручной ввод (удобно для больших целей).
  Widget _buildCounterBar(BuildContext context, ThemeData theme) {
    final pct = ((goal.counterProgress ?? 0) * 100).round();
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.6);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: TweenAnimationBuilder<double>(
              tween: Tween(
                  begin: 0, end: (goal.counterProgress ?? 0).clamp(0.0, 1.0)),
              duration: const Duration(milliseconds: 600),
              curve: AppColors.easeOut,
              builder: (context, animated, _) => LinearProgressIndicator(
                value: animated,
                minHeight: 7,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (!isPast)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  iconSize: 30,
                  icon: const Icon(Icons.remove_circle_outline),
                  onPressed: goal.progressCount > 0
                      ? () => repo.incrementGoalCounter(goal, -1)
                      : null,
                ),
              InkWell(
                onTap: isPast ? null : () => _showSetCounterDialog(context),
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${compactCount(goal.progressCount)} / ${compactCount(goal.targetCount!)}  ·  $pct%',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: muted,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (!isPast) ...[
                        const SizedBox(width: 4),
                        Icon(Icons.edit, size: 13, color: muted),
                      ],
                    ],
                  ),
                ),
              ),
              if (!isPast)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  iconSize: 30,
                  icon: const Icon(Icons.add_circle),
                  color: theme.colorScheme.primary,
                  onPressed: goal.progressCount < (goal.targetCount ?? 0)
                      ? () async {
                          final willComplete = !goal.completed &&
                              goal.progressCount + 1 >= goal.targetCount!;
                          final navContext =
                              Navigator.of(context, rootNavigator: true)
                                  .context;
                          await repo.incrementGoalCounter(goal, 1);
                          if (willComplete) {
                            await _promptQuality(navContext);
                          }
                        }
                      : null,
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// Диалог ручного ввода точного значения счётчика цели.
  Future<void> _showSetCounterDialog(BuildContext context) async {
    final l10n = context.l10n;
    final navContext = Navigator.of(context, rootNavigator: true).context;
    final controller = TextEditingController(text: '${goal.progressCount}');
    final value = await showFancyDialog<int>(
      context: context,
      icon: Icons.tag_rounded,
      iconColor: AppColors.primary,
      title: goal.title,
      autofocusEsc: false,
      contentBuilder: (ctx) => TextField(
        controller: controller,
        autofocus: true,
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        decoration: InputDecoration(
          border: const OutlineInputBorder(),
          suffixText: '/ ${goal.targetCount}',
          helperText: l10n.enterNumberHelper(goal.targetCount!),
        ),
        onSubmitted: (v) => Navigator.pop(ctx, int.tryParse(v.trim())),
      ),
      actions: (ctx) => [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(l10n.cancel),
        ),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: () =>
              Navigator.pop(ctx, int.tryParse(controller.text.trim())),
          child: Text(l10n.ok),
        ),
      ],
    );
    if (value != null) {
      final willComplete = !goal.completed && value >= goal.targetCount!;
      await repo.setGoalProgress(goal, value);
      if (willComplete) await _promptQuality(navContext);
    }
  }

  /// Маленький бейдж-стрелка поверх обычной leading-иконки — помечает, что
  /// цель была перенесена, не меняя её обычный цвет/статус-иконку.
  Widget _withTransferredBadge(BuildContext context, Widget child) {
    final theme = Theme.of(context);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned(
          right: -2,
          bottom: -2,
          child: Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: theme.cardTheme.color ?? theme.cardColor,
              border: Border.all(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.15),
              ),
            ),
            child: Icon(
              Icons.east,
              size: 9,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
            ),
          ),
        ),
      ],
    );
  }

  /// Leading-кольцо для счётчика/чек-листа цели. У чек-листа (не isPast) —
  /// кликабельно: отмечает всю цель достигнутой (и все подзадачи).
  Widget _progressLeading(BuildContext context, ThemeData theme) {
    // Выполнено — кольцо зелёное (как корешок карточки), с опозданием —
    // янтарное; иначе обычный акцентный цвет темы. Тот же приём, что и у
    // задач (_TaskTile._progressLeading).
    final ringColor = goal.completed
        ? (goal.isOnTime ? AppColors.success : AppColors.warning)
        : theme.colorScheme.primary;
    final ring = SizedBox(
      width: 38,
      height: 38,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 38,
            height: 38,
            child: TweenAnimationBuilder<double>(
              tween: Tween(
                  begin: 0, end: (goal.progressRingValue ?? 0).clamp(0.0, 1.0)),
              duration: const Duration(milliseconds: 600),
              curve: AppColors.easeOut,
              builder: (context, animated, _) => CircularProgressIndicator(
                value: animated,
                strokeWidth: 3.5,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
                color: ringColor,
              ),
            ),
          ),
          goal.completed
              ? const Icon(Icons.check, size: 18, color: AppColors.success)
              : Text(
                  goal.isChecklist
                      ? '${goal.subtasksDone}/${goal.subtasks.length}'
                      : compactCount(goal.progressCount),
                  style: theme.textTheme.labelSmall),
        ],
      ),
    );
    if ((goal.isChecklist || goal.isCounter) && !isPast) {
      return InkWell(
        customBorder: const CircleBorder(),
        onTap: () => _completeAll(context),
        child: Tooltip(
          message: goal.completed
              ? context.l10n.resetTooltip
              : context.l10n.markAchievedTooltip,
          child: ring,
        ),
      );
    }
    return ring;
  }

  /// Отмечает цель достигнутой целиком и обратно: чек-лист — все подзадачи,
  /// счётчик — прогресс в цель / 0.
  Future<void> _completeAll(BuildContext context) async {
    final navContext = Navigator.of(context, rootNavigator: true).context;
    final willComplete = !goal.completed;
    if (goal.isChecklist) {
      await repo.setAllGoalSubtasksDone(goal, willComplete);
    } else {
      await repo.setGoalProgress(goal, willComplete ? goal.targetCount! : 0);
    }
    if (willComplete) await _promptQuality(navContext);
  }

  /// Переключает подзадачу цели; если это завершает цель — опрос качества.
  Future<void> _toggleSub(BuildContext context, SubTask sub) async {
    final navContext = Navigator.of(context, rootNavigator: true).context;
    final willComplete = !sub.done &&
        goal.subtasks.where((x) => x.id != sub.id).every((x) => x.done);
    await repo.toggleGoalSubtask(goal, sub.id);
    if (willComplete) await _promptQuality(navContext);
  }

  Widget? _buildSubtitle(BuildContext context, bool isDeadlineOverdue) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    // Тот же стиль подписи, что и у задач (_TaskTile._buildSubtitle) —
    // theme.textTheme.bodySmall вместо сырого TextStyle(fontSize: 12) —
    // подхватывает шрифт и цвет темы, а не выпадает на дефолтный.
    final baseStyle = theme.textTheme.bodySmall;
    // Тот же размер/альфа, что у значков-бейджей в заголовке задачи
    // (повтор/привязка к цели — 14px, альфа 0.7), вместо прежних 13px/0.5.
    final mutedIconColor = theme.colorScheme.onSurface.withValues(alpha: 0.7);
    final lines = <Widget>[];

    if (goal.tags.isNotEmpty) {
      lines.add(
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [for (final t in goal.tags) TagMini(label: t)],
        ),
      );
    }

    if (goal.startDate != null) {
      final dateStr = DateFormat('d MMMM yyyy', locale).format(goal.startDate!);
      lines.add(
        Wrap(
          spacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Icon(Icons.play_circle_outline, size: 14, color: mutedIconColor),
            Text(l10n.sinceDatePrefix(dateStr), style: baseStyle),
          ],
        ),
      );
    }

    if (goal.deadline != null) {
      final dateStr = DateFormat('d MMMM yyyy', locale).format(goal.deadline!);
      lines.add(
        Wrap(
          spacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Icon(
              Icons.flag_outlined,
              size: 14,
              color: isDeadlineOverdue ? AppColors.danger : mutedIconColor,
            ),
            Text(
              dateStr,
              style: baseStyle?.copyWith(
                color: isDeadlineOverdue ? AppColors.danger : null,
              ),
            ),
            if (isDeadlineOverdue)
              Text(
                l10n.overdueSuffix,
                style: baseStyle?.copyWith(
                  color: AppColors.danger,
                  fontStyle: FontStyle.italic,
                ),
              ),
          ],
        ),
      );
    }

    if (goal.description != null) {
      lines.add(Text(goal.description!, style: baseStyle));
    }

    // Оценка качества достижения — только если выставлена (рефлексия).
    if (goal.completed && goal.quality != null) {
      lines.add(
        Padding(
          padding: const EdgeInsets.only(top: 3),
          child: GestureDetector(
            onTap: () => _promptQuality(context),
            behavior: HitTestBehavior.opaque,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                StarRating(value: goal.quality!, size: 13),
                const SizedBox(width: 6),
                Text(
                  '${goal.quality!}/10',
                  style: baseStyle?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (lines.isEmpty) return null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: lines,
    );
  }

  /// Переключение выполнения через чекбокс + опрос качества при завершении.
  /// navContext берём ДО переключения: плитка переедет в «Выполненные» и
  /// будет уничтожена, её context станет невалиден к моменту показа диалога.
  Future<void> _onToggle(BuildContext context) async {
    final navContext = Navigator.of(context, rootNavigator: true).context;
    final wasIncomplete = !goal.completed;
    // Даём галочке прочертиться до того, как цель уедет в «Выполненные».
    if (wasIncomplete) {
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }
    await repo.toggleComplete(goal);
    if (wasIncomplete) await _promptQuality(navContext);
  }

  /// Необязательный опрос качества достижения цели.
  Future<void> _promptQuality(BuildContext context) async {
    final rating = await showQualityDialog(
      context,
      question: context.l10n.goalQualityQuestion,
      initial: goal.quality,
    );
    if (rating != null) await repo.setQuality(goal, rating);
  }

  bool _canTransferGoal() =>
      !goal.completed && !goal.isTransferred && goal.transferredFromId == null;

  Future<void> _handleTransfer() async {
    final currentRef = GoalPeriodRef.current(goal.period, DateTime.now());
    await repo.transferGoal(goal, targetRef: currentRef);
  }

  /// Досрочный перенос активной (ещё не прошедшей) цели в СЛЕДУЮЩИЙ период —
  /// в отличие от [_handleTransfer], который переносит уже прошедшую цель В
  /// текущий. Доступен только когда цель «Требует внимания» — см.
  /// [_canTransferGoalEarly].
  bool _canTransferGoalEarly() =>
      !goal.completed &&
      !goal.isTransferred &&
      goal.transferredFromId == null &&
      urgency == _GoalUrgency.urgent;

  Future<void> _handleTransferEarly() async {
    await repo.transferGoal(goal, targetRef: goal.ref.next);
  }

  /// Копирует эту одну цель в выбранный период — оригинал остаётся на месте
  /// (в отличие от переноса). Тот же пикер периода, что и у копирования всех
  /// целей сразу (_pickGoalCopyTarget), только источник — период самой цели.
  Future<void> _copyGoalToPeriod(BuildContext context) async {
    final target = await _pickGoalCopyTarget(context, goal.ref);
    if (target == null || !context.mounted) return;
    await repo.copyGoalsTo(goals: [goal], target: target);
    if (context.mounted) {
      final ru = Localizations.localeOf(context).languageCode == 'ru';
      showFancyToast(
        context,
        message: context.l10n.copiedToPeriodToast(target.labelFor(ru)),
      );
    }
  }

  Future<void> _showEditSheet(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => EscDismissible(
        autofocus: true,
        child: _GoalFormSheet(
          periodRef: goal.ref,
          existingGoal: goal,
        ),
      ),
    );
  }
}

// ─── Два кольца: выполнение целей + своевременность ──────────────────────────

class _GoalDualRingRow extends StatelessWidget {
  const _GoalDualRingRow({
    required this.value,
    required this.done,
    required this.completedFraction,
    required this.total,
    required this.timeliness,
    required this.onTimeCount,
    required this.lateCount,
  });

  final double? value;
  final int done;

  /// Дробное выполнение (цели-счётчики дают доли) — для подписи «3.5 / 5».
  final double completedFraction;
  final int total;
  final double? timeliness;
  final int onTimeCount;
  final int lateCount;

  /// Число без хвоста .0: 3.0 → «3», 3.5 → «3.5».
  static String _fmtNum(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;

    // Всегда два кольца фиксированного размера — без «прыжка» при появлении
    // данных о своевременности. «В срок» показывает «—», пока нет выполненных.
    Widget ringWithLabel({
      required double? val,
      required int d,
      required int t,
      required String label,
      List<Color>? ringColors,
      String? subtitle,
    }) =>
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ProductivityRing(
              value: val,
              done: d,
              total: t,
              size: 132,
              strokeWidth: 10,
              ringColors: ringColors,
              subtitle: subtitle,
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
            ),
          ],
        );

    // Геро-блок целей в «наклеенной» карточке — как на «Сегодня».
    return Card(
      margin: const EdgeInsets.only(bottom: 4),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            ringWithLabel(
              val: value,
              d: done,
              t: total,
              label: l10n.goalsTitle,
              subtitle: '${_fmtNum(completedFraction)} / $total',
            ),
            ringWithLabel(
              val: timeliness,
              d: onTimeCount,
              t: onTimeCount + lateCount,
              label: l10n.onTimeRingLabel,
              ringColors: AppColors.warningGradient,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Форма добавления / редактирования цели ──────────────────────────────────

class _GoalFormSheet extends ConsumerStatefulWidget {
  const _GoalFormSheet({
    required this.periodRef,
    this.existingGoal,
  });

  final GoalPeriodRef periodRef;
  final Goal? existingGoal;

  bool get isEditing => existingGoal != null;

  @override
  ConsumerState<_GoalFormSheet> createState() => _GoalFormSheetState();
}

class _GoalFormSheetState extends ConsumerState<_GoalFormSheet> {
  late final TextEditingController _titleController;
  DateTime? _startDate;
  DateTime? _deadline;
  bool _isCounter = false;
  int _targetCount = 10;

  // Подзадачи (чек-лист) — взаимоисключающи со счётчиком.
  final List<TextEditingController> _subtaskCtrls = [];
  final List<SubTask?> _subtaskOrig = [];
  bool get _hasSubtasks => _subtaskCtrls.isNotEmpty;

  // ── Приоритет и теги (как у задач) ────────────────────────────────────────
  TaskPriority _priority = TaskPriority.none;
  final Set<String> _tags = {};
  final _tagCtrl = TextEditingController();
  final _tagSearchCtrl = TextEditingController();
  String _tagSearch = '';

  DateTime get _periodStart => widget.periodRef.start;
  DateTime get _periodEnd => widget.periodRef.endInclusive;

  /// Безопасная начальная дата для пикера дедлайна.
  /// Должна быть >= _startDate (если задана) и <= _periodEnd.
  DateTime get _safeDeadlineInitialDate {
    final first = _startDate ?? _periodStart;
    final d = _deadline;
    if (d == null || d.isBefore(first) || d.isAfter(_periodEnd)) return first;
    return d;
  }

  /// Безопасная начальная дата для пикера даты начала.
  DateTime get _safeStartDateInitialDate {
    final d = _startDate;
    if (d == null) return _periodStart;
    if (d.isBefore(_periodStart) || d.isAfter(_periodEnd)) return _periodStart;
    return d;
  }

  String get _hint {
    final l10n = context.l10n;
    return switch (widget.periodRef.period) {
      GoalPeriod.week => l10n.goalHintWeek,
      GoalPeriod.month => l10n.goalHintMonth,
      GoalPeriod.season => l10n.goalHintSeason,
      GoalPeriod.year => l10n.goalHintYear,
    };
  }

  @override
  void initState() {
    super.initState();
    _titleController =
        TextEditingController(text: widget.existingGoal?.title ?? '');
    _startDate = widget.existingGoal?.startDate;
    _deadline = widget.existingGoal?.deadline;
    _isCounter = widget.existingGoal?.isCounter ?? false;
    _targetCount = widget.existingGoal?.targetCount ?? 10;
    _priority = widget.existingGoal?.priority ?? TaskPriority.none;
    _tags.addAll(widget.existingGoal?.tags ?? const []);
    for (final s in (widget.existingGoal?.subtasks ?? const <SubTask>[])) {
      _subtaskCtrls.add(TextEditingController(text: s.title));
      _subtaskOrig.add(s);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _tagCtrl.dispose();
    _tagSearchCtrl.dispose();
    for (final c in _subtaskCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  void _addSubtask() {
    setState(() {
      _subtaskCtrls.add(TextEditingController());
      _subtaskOrig.add(null);
    });
  }

  void _removeSubtask(int i) {
    setState(() {
      _subtaskCtrls.removeAt(i).dispose();
      _subtaskOrig.removeAt(i);
    });
  }

  List<String> _subtaskTitles() => [
        for (final c in _subtaskCtrls)
          if (c.text.trim().isNotEmpty) c.text.trim(),
      ];

  List<SubTask> _subtasksForEdit() {
    final result = <SubTask>[];
    for (var i = 0; i < _subtaskCtrls.length; i++) {
      final title = _subtaskCtrls[i].text.trim();
      if (title.isEmpty) continue;
      final orig = _subtaskOrig[i];
      result.add(orig != null
          ? orig.copyWith(title: title)
          : SubTask(
              id: 'gst-${DateTime.now().microsecondsSinceEpoch}-$i',
              title: title));
    }
    return result;
  }

  Widget _buildPrioritySection(ThemeData theme) {
    final l10n = context.l10n;
    String labelFor(TaskPriority p) => switch (p) {
          TaskPriority.none => l10n.priorityNone,
          TaskPriority.low => l10n.priorityLow,
          TaskPriority.medium => l10n.priorityMedium,
          TaskPriority.high => l10n.priorityHigh,
        };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.prioritySectionLabel, style: theme.textTheme.labelMedium),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          children: [
            for (final p in TaskPriority.values)
              SegChip(
                label: labelFor(p),
                selected: _priority == p,
                onTap: () => setState(() => _priority = p),
              ),
          ],
        ),
      ],
    );
  }

  void _addTag(String raw) {
    final tag = raw.trim().replaceAll('#', '').toLowerCase();
    if (tag.isEmpty) return;
    setState(() => _tags.add(tag));
    _tagCtrl.clear();
  }

  /// Тот же список-с-поиском, что и у задач (_TaskFormSheetState) — подсказки
  /// собираются из уже использованных тегов всех целей.
  Widget _buildTagsSection(ThemeData theme) {
    final known = (<String>{
      for (final g in ref.read(allGoalsProvider).value ?? const <Goal>[])
        ...g.tags,
    }..removeAll(_tags))
        .toList()
      ..sort();
    final query = _tagSearch.trim().toLowerCase();
    final filtered =
        query.isEmpty ? known : known.where((t) => t.contains(query)).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Text(context.l10n.tagsSectionLabel, style: theme.textTheme.labelMedium),
        const SizedBox(height: 6),
        if (_tags.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final t in _tags)
                  InputChip(
                    label: Text('#$t'),
                    visualDensity: VisualDensity.compact,
                    onDeleted: () => setState(() => _tags.remove(t)),
                  ),
              ],
            ),
          ),
        if (known.length > 6)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: SizedBox(
              width: 180,
              child: TextField(
                controller: _tagSearchCtrl,
                decoration: InputDecoration(
                  hintText: context.l10n.searchTagsHint,
                  prefixIcon: const Icon(Icons.search, size: 18),
                  border: const OutlineInputBorder(),
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                ),
                onChanged: (v) => setState(() => _tagSearch = v),
              ),
            ),
          ),
        if (known.isNotEmpty)
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 96),
            child: SingleChildScrollView(
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final t in filtered)
                    ActionChip(
                      label: Text('#$t'),
                      visualDensity: VisualDensity.compact,
                      labelStyle: TextStyle(
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                      onPressed: () => setState(() {
                        _tags.add(t);
                        _tagSearchCtrl.clear();
                        _tagSearch = '';
                      }),
                    ),
                  if (filtered.isEmpty)
                    Text(
                      context.l10n.noTagsFound,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 6),
        SizedBox(
          width: 180,
          child: TextField(
            controller: _tagCtrl,
            decoration: InputDecoration(
              hintText: context.l10n.newTagHint,
              border: const OutlineInputBorder(),
              isDense: true,
              prefixText: '# ',
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            onSubmitted: _addTag,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final locale = Localizations.localeOf(context).languageCode;
    final hasDeadline = _deadline != null;

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Название ─────────────────────────────────────────────────
            TextField(
              controller: _titleController,
              autofocus: !widget.isEditing,
              decoration: InputDecoration(
                hintText: _hint,
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 12),
            // ── Дата начала ──────────────────────────────────────────────
            Text(l10n.startDateLabel, style: theme.textTheme.labelMedium),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.play_circle_outline, size: 16),
                    label: Text(
                      _startDate != null
                          ? DateFormat('d MMMM yyyy', locale)
                              .format(_startDate!)
                          : l10n.startOfPeriodOption,
                      overflow: TextOverflow.ellipsis,
                    ),
                    style: _startDate != null
                        ? OutlinedButton.styleFrom(
                            foregroundColor: theme.colorScheme.secondary,
                          )
                        : null,
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _safeStartDateInitialDate,
                        firstDate: _periodStart,
                        lastDate: _deadline ?? _periodEnd,
                        helpText: l10n.startDateHelp,
                        locale: Locale(locale),
                      );
                      if (picked != null && mounted) {
                        setState(() => _startDate = picked);
                      }
                    },
                  ),
                ),
                if (_startDate != null)
                  IconButton(
                    iconSize: 18,
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 32, minHeight: 32),
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() => _startDate = null),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            // ── Дедлайн ─────────────────────────────────────────────────
            Text(l10n.deadlineLabel, style: theme.textTheme.labelMedium),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.flag_outlined, size: 16),
                    label: Text(
                      hasDeadline
                          ? DateFormat('d MMMM yyyy', locale).format(_deadline!)
                          : l10n.noDeadlineOption,
                      overflow: TextOverflow.ellipsis,
                    ),
                    style: hasDeadline
                        ? OutlinedButton.styleFrom(
                            foregroundColor: theme.colorScheme.primary,
                          )
                        : null,
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _safeDeadlineInitialDate,
                        firstDate: _startDate ?? _periodStart,
                        lastDate: _periodEnd,
                        helpText: l10n.deadlineHelp,
                        locale: Locale(locale),
                      );
                      if (picked != null && mounted) {
                        setState(() => _deadline = picked);
                      }
                    },
                  ),
                ),
                if (hasDeadline)
                  IconButton(
                    iconSize: 18,
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 32, minHeight: 32),
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() => _deadline = null),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            // ── Приоритет (как у задач) ────────────────────────────────────
            _buildPrioritySection(theme),
            const SizedBox(height: 8),
            // ── Счётчик (скрыт, если есть подзадачи) ──────────────────────
            if (!_hasSubtasks) ...[
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(l10n.counterSwitchTitle),
                subtitle: Text(l10n.goalCounterSwitchSubtitle),
                value: _isCounter,
                onChanged: (v) => setState(() => _isCounter = v),
              ),
              if (_isCounter)
                Row(
                  children: [
                    Text(l10n.counterTargetLabel),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 110,
                      child: TextFormField(
                        initialValue: '$_targetCount',
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                              vertical: 10, horizontal: 10),
                        ),
                        onChanged: (v) {
                          final n = int.tryParse(v.trim());
                          if (n != null && n >= 2) _targetCount = n;
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(l10n.counterTargetExampleGoal,
                        style: theme.textTheme.bodySmall),
                  ],
                ),
            ],
            // ── Подзадачи (скрыты, если счётчик) ──────────────────────────
            if (!_isCounter) _buildSubtasksSection(theme),
            // ── Теги (как у задач) ──────────────────────────────────────────
            _buildTagsSection(theme),
            const SizedBox(height: 16),
            // ── Кнопка сохранения ────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _save,
                child: Text(widget.isEditing ? l10n.saveBtn : l10n.addBtn),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubtasksSection(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 4),
        Row(
          children: [
            Icon(Icons.checklist_rounded,
                size: 18, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Text(context.l10n.subtasksSectionLabel,
                style: theme.textTheme.labelLarge),
          ],
        ),
        for (var i = 0; i < _subtaskCtrls.length; i++)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _subtaskCtrls[i],
                    decoration: InputDecoration(
                      hintText: context.l10n.subtaskItemHint(i + 1),
                      border: const OutlineInputBorder(),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                    ),
                    onSubmitted: (_) => _addSubtask(),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => _removeSubtask(i),
                ),
              ],
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _addSubtask,
            icon: const Icon(Icons.add, size: 18),
            label: Text(_hasSubtasks
                ? context.l10n.addAnotherSubtask
                : context.l10n.addSubtasks),
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _save() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) return;
    // Не даём потерять введённый, но не подтверждённый тег.
    if (_tagCtrl.text.trim().isNotEmpty) _addTag(_tagCtrl.text);

    final repo = ref.read(goalRepositoryProvider);

    if (widget.isEditing) {
      final existing = widget.existingGoal!;
      final now = DateTime.now();
      final subs = _subtasksForEdit();
      var updated = existing.copyWith(
        title: title,
        startDate: _startDate,
        clearStartDate: _startDate == null,
        deadline: _deadline,
        clearDeadline: _deadline == null,
        targetCount: _isCounter ? _targetCount : null,
        clearTargetCount: !_isCounter,
        subtasks: subs,
        priority: _priority,
        tags: _tags.toList(),
        updatedAt: now,
      );
      // При наличии подзадач достижение цели определяется ими.
      if (subs.isNotEmpty) {
        final allDone = subs.every((s) => s.done);
        updated = updated.copyWith(
          completed: allDone,
          completedAt: allDone ? (existing.completedAt ?? now) : null,
          clearCompletedAt: !allDone,
        );
      }
      await repo.updateGoal(updated);
    } else {
      final r = widget.periodRef;
      await repo.addGoal(
        title: title,
        period: r.period,
        year: r.year,
        month: r.month,
        season: r.season,
        weekStart: r.weekStart,
        startDate: _startDate,
        deadline: _deadline,
        targetCount: _isCounter ? _targetCount : null,
        subtaskTitles: _subtaskTitles(),
        priority: _priority,
        tags: _tags.toList(),
      );
    }

    if (mounted) Navigator.of(context).pop();
  }
}

// ─── Пикер недели ─────────────────────────────────────────────────────────────
// Календарь (table_calendar) с подсветкой ЦЕЛОЙ недели: тап по любому дню
// выделяет всю неделю (пн–вс) единой полосой через range-режим.
// Прошлые недели недоступны (firstDay = текущий понедельник).
// Возвращает понедельник выбранной недели.

class _WeekPickerDialog extends StatefulWidget {
  const _WeekPickerDialog({required this.initialWeekStart});
  final DateTime initialWeekStart;

  @override
  State<_WeekPickerDialog> createState() => _WeekPickerDialogState();
}

class _WeekPickerDialogState extends State<_WeekPickerDialog> {
  late final DateTime _firstWeek; // текущий понедельник — раньше нельзя
  late DateTime _weekStart; // понедельник выбранной недели
  late DateTime _focused;

  @override
  void initState() {
    super.initState();
    _firstWeek = startOfWeek(DateTime.now());
    final initial = startOfWeek(widget.initialWeekStart);
    _weekStart = initial.isBefore(_firstWeek) ? _firstWeek : initial;
    _focused = _weekStart;
  }

  DateTime get _weekEnd => _weekStart.add(const Duration(days: 6));

  String _weekLabel(bool ru) => GoalPeriodRef(
        period: GoalPeriod.week,
        year: _weekStart.year,
        weekStart: _weekStart,
      ).labelFor(ru);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final locale = Localizations.localeOf(context).languageCode;
    final primary = theme.colorScheme.primary;

    return FancyDialogCard(
      icon: Icons.calendar_view_week_rounded,
      iconColor: AppColors.clay,
      title: l10n.copyToWeekBarrier,
      child: SizedBox(
        width: 280,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            TableCalendar<void>(
              focusedDay: _focused,
              firstDay: _firstWeek,
              lastDay: DateTime(DateTime.now().year + 10, 12, 31),
              calendarFormat: CalendarFormat.month,
              availableCalendarFormats: {
                CalendarFormat.month: l10n.calFormatMonth,
              },
              startingDayOfWeek: StartingDayOfWeek.monday,
              locale: locale,
              headerStyle: HeaderStyle(
                titleTextFormatter: (date, loc) =>
                    _capitalize(DateFormat.yMMMM(loc).format(date)),
              ),
              // Подсветка целой недели через range.
              rangeStartDay: _weekStart,
              rangeEndDay: _weekEnd,
              rangeSelectionMode: RangeSelectionMode.toggledOff,
              selectedDayPredicate: (_) => false,
              onDaySelected: (sel, foc) {
                setState(() {
                  _weekStart = startOfWeek(sel);
                  _focused = foc;
                });
              },
              onPageChanged: (foc) => _focused = foc,
              calendarStyle: CalendarStyle(
                rangeHighlightColor: primary.withValues(alpha: 0.18),
                rangeStartDecoration: BoxDecoration(
                  color: primary,
                  shape: BoxShape.circle,
                ),
                rangeEndDecoration: BoxDecoration(
                  color: primary,
                  shape: BoxShape.circle,
                ),
                withinRangeDecoration: const BoxDecoration(
                  shape: BoxShape.circle,
                ),
                todayDecoration: BoxDecoration(
                  color: primary.withValues(alpha: 0.4),
                  shape: BoxShape.circle,
                ),
                // Дни соседнего месяца видимы и бледные — чтобы неделя,
                // переходящая на следующий месяц, была видна целиком.
                outsideDaysVisible: true,
                outsideTextStyle: TextStyle(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _weekLabel(locale == 'ru'),
              style: theme.textTheme.titleSmall?.copyWith(color: primary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(l10n.cancel),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(_weekStart),
                  child: Text(l10n.chooseBtn),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Пикер месяца ────────────────────────────────────────────────────────────
// Год с кнопками ‹ / › + сетка 3 × 4 месяцев.
// Прошедшие месяцы (относительно сегодня) недоступны и показаны серым.
// В прошлый год навигация заблокирована.
// Возвращает DateTime(targetYear, targetMonth).

class _MonthPickerDialog extends StatefulWidget {
  const _MonthPickerDialog({required this.initialYear});
  final int initialYear;

  @override
  State<_MonthPickerDialog> createState() => _MonthPickerDialogState();
}

class _MonthPickerDialogState extends State<_MonthPickerDialog> {
  static const _monthsRu = [
    'Январь',
    'Февраль',
    'Март',
    'Апрель',
    'Май',
    'Июнь',
    'Июль',
    'Август',
    'Сентябрь',
    'Октябрь',
    'Ноябрь',
    'Декабрь',
  ];
  static const _monthsEn = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  List<String> _months(BuildContext context) =>
      Localizations.localeOf(context).languageCode == 'ru'
          ? _monthsRu
          : _monthsEn;

  late int _year;
  late int _todayYear;
  late int _todayMonth;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _todayYear = now.year;
    _todayMonth = now.month;
    // Никогда не начинаем с прошлого года
    _year = widget.initialYear >= _todayYear ? widget.initialYear : _todayYear;
  }

  bool _isMonthPast(int month) =>
      _year < _todayYear || (_year == _todayYear && month < _todayMonth);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final canGoBack = _year > _todayYear;

    return FancyDialogCard(
      icon: Icons.calendar_month_rounded,
      iconColor: AppColors.clay,
      title: l10n.copyToEllipsisTitle,
      child: SizedBox(
        width: 280,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: canGoBack ? () => setState(() => _year--) : null,
                ),
                Text('$_year', style: theme.textTheme.titleMedium),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () => setState(() => _year++),
                ),
              ],
            ),
            const SizedBox(height: 4),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                childAspectRatio: 2.6,
                mainAxisSpacing: 6,
                crossAxisSpacing: 6,
              ),
              itemCount: 12,
              itemBuilder: (ctx, i) {
                final isPast = _isMonthPast(i + 1);
                return InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: isPast
                      ? null
                      : () => Navigator.of(context).pop(DateTime(_year, i + 1)),
                  child: Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      color: isPast
                          ? AppColors.textSecondary.withValues(alpha: 0.07)
                          : AppColors.clay.withValues(alpha: 0.13),
                    ),
                    child: Text(
                      _months(context)[i],
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: isPast ? AppColors.textSecondary : null,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(l10n.cancel),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Пикер сезона ─────────────────────────────────────────────────────────────
// Год с кнопками ‹ / › + карточка «Зима N-1/N» сверху по центру (зима, заходящая
// в начало текущего года) + сетка 2 × 2 (Весна/Лето/Осень/Зима N/N+1).
// Зимние карточки показывают оба года. Завершившиеся сезоны серые и недоступны.
// Возвращает (год, индекс сезона).

class _SeasonPickerDialog extends StatefulWidget {
  const _SeasonPickerDialog({required this.initialYear});
  final int initialYear;

  @override
  State<_SeasonPickerDialog> createState() => _SeasonPickerDialogState();
}

class _SeasonPickerDialogState extends State<_SeasonPickerDialog> {
  late int _year;
  late int _minYear;

  @override
  void initState() {
    super.initState();
    final (anchorYear, _) = seasonOf(DateTime.now());
    _minYear = anchorYear;
    _year = widget.initialYear >= _minYear ? widget.initialYear : _minYear;
  }

  String _winterLabel(int year, bool ru) => GoalPeriodRef(
        period: GoalPeriod.season,
        year: year,
        season: 0,
      ).labelFor(ru);

  /// Карточка сезона. Серая и некликабельная, если сезон уже завершился.
  Widget _cell(BuildContext context, int year, int idx, String label) {
    final theme = Theme.of(context);
    final ref = GoalPeriodRef(
      period: GoalPeriod.season,
      year: year,
      season: idx,
    );
    final isPast = ref.endInclusive.isBefore(today());
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: isPast ? null : () => Navigator.of(context).pop((year, idx)),
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: isPast
              ? AppColors.textSecondary.withValues(alpha: 0.07)
              : AppColors.clay.withValues(alpha: 0.13),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: isPast ? AppColors.textSecondary : null,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final ru = Localizations.localeOf(context).languageCode == 'ru';
    final canGoBack = _year > _minYear;

    return FancyDialogCard(
      icon: Icons.wb_sunny_rounded,
      iconColor: AppColors.clay,
      title: l10n.copyToEllipsisTitle,
      child: SizedBox(
        width: 280,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: canGoBack ? () => setState(() => _year--) : null,
                ),
                Text('$_year', style: theme.textTheme.titleMedium),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () => setState(() => _year++),
                ),
              ],
            ),
            const SizedBox(height: 4),
            // Зима предыдущего года (заходит в январь–февраль текущего):
            // отдельной карточкой сверху по центру.
            Center(
              child: SizedBox(
                width: 131,
                height: 50,
                child: _cell(
                  context,
                  _year - 1,
                  0,
                  _winterLabel(_year - 1, ru),
                ),
              ),
            ),
            const SizedBox(height: 6),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 2.6,
                mainAxisSpacing: 6,
                crossAxisSpacing: 6,
              ),
              itemCount: 4,
              itemBuilder: (ctx, gridIndex) {
                final i = seasonDisplayOrder[gridIndex];
                final label =
                    i == 0 ? _winterLabel(_year, ru) : seasonNamesFor(ru)[i];
                return _cell(context, _year, i, label);
              },
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(l10n.cancel),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Пикер года ──────────────────────────────────────────────────────────────
// Сетка 3 × 4 = 12 лет на страницу. Навигация ‹ XXXX – YYYY › вперёд/назад
// по 12 лет без ограничения сверху. Назад — только до страницы с todayYear.
// Сегодняшний год выделен primaryContainer. Год-источник — обводка.
// Возвращает int.

class _YearPickerDialog extends StatefulWidget {
  const _YearPickerDialog({
    required this.todayYear,
    required this.sourceYear,
  });

  final int todayYear;
  final int sourceYear;

  @override
  State<_YearPickerDialog> createState() => _YearPickerDialogState();
}

class _YearPickerDialogState extends State<_YearPickerDialog> {
  static const _pageSize = 12;

  late int _pageStart;
  late int _minPageStart;

  /// Год за пределами grace-периода (15 января следующего года).
  bool _isPastGrace(int y) => DateTime.now().isAfter(DateTime(y + 1, 1, 15));

  @override
  void initState() {
    super.initState();
    _pageStart = 2000 + ((widget.todayYear - 2000) ~/ _pageSize) * _pageSize;
    _minPageStart = _pageStart;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final canGoBack = _pageStart > _minPageStart;

    return FancyDialogCard(
      icon: Icons.event_repeat_rounded,
      iconColor: AppColors.clay,
      title: l10n.copyToEllipsisTitle,
      child: SizedBox(
        width: 280,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: canGoBack
                      ? () => setState(() => _pageStart -= _pageSize)
                      : null,
                ),
                Text(
                  '$_pageStart – ${_pageStart + _pageSize - 1}',
                  style: theme.textTheme.titleMedium,
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () => setState(() => _pageStart += _pageSize),
                ),
              ],
            ),
            const SizedBox(height: 4),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                childAspectRatio: 2.6,
                mainAxisSpacing: 6,
                crossAxisSpacing: 6,
              ),
              itemCount: _pageSize,
              itemBuilder: (ctx, i) {
                final y = _pageStart + i;
                final isPast = _isPastGrace(y);
                final isToday = y == widget.todayYear;
                final isSource = y == widget.sourceYear;

                return InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: isPast ? null : () => Navigator.of(context).pop(y),
                  child: Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      color: isPast
                          ? AppColors.textSecondary.withValues(alpha: 0.07)
                          : isToday
                              ? AppColors.primary.withValues(alpha: 0.16)
                              : AppColors.clay.withValues(alpha: 0.13),
                      border: isSource && !isToday && !isPast
                          ? Border.all(color: AppColors.clay, width: 1.5)
                          : null,
                    ),
                    child: Text(
                      '$y',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: (isToday || isSource) && !isPast
                            ? FontWeight.bold
                            : null,
                        color: isPast
                            ? AppColors.textSecondary
                            : isToday
                                ? AppColors.primary
                                : null,
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(l10n.cancel),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Оценка прошедшего периода (рефлексия) ───────────────────────────────────

class _PeriodRatingRow extends ConsumerWidget {
  const _PeriodRatingRow({required this.periodRef});
  final GoalPeriodRef periodRef;

  String _periodAccusative(AppLocalizations l10n) => switch (periodRef.period) {
        GoalPeriod.week => l10n.periodAccusativeWeek,
        GoalPeriod.month => l10n.periodAccusativeMonth,
        GoalPeriod.season => l10n.periodAccusativeSeason,
        GoalPeriod.year => l10n.periodAccusativeYear,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final rating = ref.watch(periodRatingProvider(periodRef.key)).value;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            rating == null
                ? l10n.periodRatingQuestion(_periodAccusative(l10n))
                : l10n.periodRatingResult(rating),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 4),
          StarRating(
            value: rating ?? 0,
            size: 26,
            onRate: (v) => ref
                .read(ratingRepositoryProvider)
                .setPeriodRating(periodRef.key, v),
          ),
        ],
      ),
    );
  }
}
