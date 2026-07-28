import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../core/create_action.dart';
import '../../core/current_time_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_fonts.dart';
import '../../core/theme/appearance.dart';
import '../../core/utils/date_utils.dart';
import '../../core/utils/format_utils.dart';
import '../../data/models/recurrence_rule.dart';
import '../../data/models/task.dart';
import '../../data/repositories/backlog_repository.dart';
import '../../data/repositories/goal_repository.dart';
import '../../data/repositories/rating_repository.dart';
import '../../data/repositories/stats_repository.dart';
import '../../data/repositories/task_repository.dart';
import '../../l10n/l10n_extensions.dart';
import '../backlog/backlog_screen.dart';
import '../search/global_search.dart';
import '../templates/templates_sheet.dart';
import '../../services/notification_controller.dart';
import '../../services/pomodoro_controller.dart';
import '../../services/quote_service.dart';
import '../../widgets/backlog_nudge_card.dart';
import '../../widgets/battery_hint_card.dart';
import '../../widgets/draw_check_box.dart';
import '../../widgets/error_view.dart';
import '../../widgets/esc_dismissible.dart';
import '../../widgets/fancy_dialog.dart';
import '../../widgets/fancy_toast.dart';
import '../../widgets/glow_fab.dart';
import '../../widgets/pomodoro_banner.dart';
import '../../widgets/productivity_ring.dart';
import '../../widgets/seg_chip.dart';
import '../../widgets/stagger_reveal.dart';
import '../../widgets/star_rating.dart';
import '../../widgets/subtask_checklist.dart';
import '../../widgets/tag_mini.dart';

// ─── Вспомогательные функции ─────────────────────────────────────────────────

/// Задача выполнена в срок — единая логика в [StatsRepository.taskIsOnTime].
bool _isTaskOnTime(Task task) => StatsRepository.taskIsOnTime(task);

String _fmtTime(int minutes) => '${(minutes ~/ 60).toString().padLeft(2, '0')}:'
    '${(minutes % 60).toString().padLeft(2, '0')}';

/// intl отдаёт название месяца в «естественном» регистре языка (в русском —
/// строчными: «июль»). Для заголовка календаря хотим заглавную первую букву
/// независимо от языка.
String _capitalize(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

String _fmtDuration(int minutes, BuildContext context) {
  final ru = Localizations.localeOf(context).languageCode == 'ru';
  final hSuffix = ru ? 'ч' : 'h';
  final mSuffix = ru ? 'м' : 'm';
  if (minutes < 60) return '$minutes$mSuffix';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return m == 0 ? '$h$hSuffix' : '$h$hSuffix $m$mSuffix';
}

// ─── Граница «прошлое» с учётом ночного времени ──────────────────────────────

/// До 4:00 утра вчерашний день ещё считается «сегодняшним» для редактирования.
DateTime _effectiveToday(DateTime now) =>
    now.hour < 4 ? today().subtract(const Duration(days: 1)) : today();

// ─── Порог показа «Оцените день» на сегодня ──────────────────────────────────

/// Минута дня (0..1439), с которой на СЕГОДНЯ показываем карточку оценки дня:
/// всегда за полчаса до тихих часов (дефолт тихих часов — 23:00 → порог 22:30).
int _dayRatingTriggerMinutes(int quietStart) => (quietStart - 30) % 1440;

// ─── Состояние задачи по времени ─────────────────────────────────────────────

enum _TimeState { normal, upcoming, active, urgent, overdue }

_TimeState _calcTimeState(Task task, DateTime now) {
  if (task.isCompleted) return _TimeState.normal;
  // Подсветка по времени — только для активного («эффективного») дня.
  // До 4:00 утра активным остаётся вчерашний день.
  if (!isSameDay(task.date, _effectiveToday(now))) return _TimeState.normal;

  final start = task.startMinutes;
  final end = task.endMinutes;
  // Задача «через полночь» (например, 22:00 → 01:00): конец по числу минут
  // МЕНЬШЕ начала — на деле он наступает на следующий календарный день, а
  // не раньше начала. Считаем такую задачу не просроченной, пока не
  // наступит её реальный конец (а не в момент, когда nowMin случайно
  // превысит маленькое число вроде 60).
  final overnight = start != null && end != null && end < start;

  // Сколько календарных дней прошло с даты задачи: 0 — тот же день; 1 — уже
  // наступил следующий календарный день (но эффективный «сегодня» по
  // правилу 4:00 утра ещё вчерашний, см. проверку выше).
  final daysSince = dateOnly(now).difference(dateOnly(task.date)).inDays;

  // Окно до 4:00: уже наступил следующий календарный день. Для обычных
  // задач — сразу просрочены, как и раньше. Для «через полночь» — конец
  // ещё может не наступить, проверяем ниже по фактическому времени.
  if (daysSince >= 1 && !overnight) return _TimeState.overdue;
  if (daysSince >= 2) return _TimeState.overdue; // overnight, но давно позади

  final nowMin = now.hour * 60 + now.minute;
  // Переводим «конец» и «сейчас» в непрерывную шкалу минут от полуночи ДНЯ
  // ЗАДАЧИ — для overnight-конца прибавляем сутки, чтобы сравнение не
  // «оборачивалось» вокруг полуночи.
  final endFromTaskDay = end == null ? null : (overnight ? end + 1440 : end);
  final nowFromTaskDay = daysSince * 1440 + nowMin;

  if (endFromTaskDay != null && nowFromTaskDay >= endFromTaskDay) {
    return _TimeState.overdue;
  }
  if (endFromTaskDay != null && nowFromTaskDay >= endFromTaskDay - 30) {
    return _TimeState.urgent;
  }

  // После 23:00 (в день самой задачи) все невыполненные задачи дня
  // подсвечиваются как «срочные».
  if (daysSince == 0 && nowMin >= 23 * 60) return _TimeState.urgent;

  if (start != null && nowFromTaskDay >= start) return _TimeState.active;
  if (start != null) return _TimeState.upcoming;
  return _TimeState.normal;
}

// ─── Ручной перенос задач ─────────────────────────────────────────────────────

/// Задачу можно перенести вперёд вручную в двух случаях:
/// • 0:00–3:59: задача на прошлом календарном дне (effective today = вчера)
/// • 23:00–23:59: задача на сегодняшнем дне (предложить отложить на завтра)
bool _isTransferable(Task t, DateTime now) {
  if (t.isCompleted ||
      t.isTransferred ||
      t.recurrenceRuleId != null ||
      t.transferredFromId != null) return false;
  final taskDay = dateOnly(t.date);
  final calendarToday = dateOnly(now);
  if (taskDay.isBefore(calendarToday)) return true; // 0:00–3:59
  if (now.hour >= 23 && taskDay == calendarToday) return true; // 23:xx
  return false;
}

/// Целевая дата переноса:
/// • прошлый календарный день → сегодня по календарю
/// • сегодня (окно 23:xx) → завтра
DateTime _calcTransferTarget(DateTime taskDate, DateTime now) {
  final calendarToday = dateOnly(now);
  if (dateOnly(taskDate).isBefore(calendarToday)) return calendarToday;
  return calendarToday.add(const Duration(days: 1));
}

// ─── Главный экран ───────────────────────────────────────────────────────────

class TodayScreen extends ConsumerStatefulWidget {
  const TodayScreen({super.key});

  @override
  ConsumerState<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends ConsumerState<TodayScreen> {
  late DateTime _selected;
  late DateTime _focused;
  CalendarFormat _format = CalendarFormat.month;

  @override
  void initState() {
    super.initState();
    // До 4:00 утра активным днём считается вчерашний.
    final effToday = _effectiveToday(DateTime.now());
    _selected = effToday;
    _focused = effToday;
    // Регистрируем «создать» для Ctrl+N: новая задача на выбранный день.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(createActionProvider.notifier).state = () {
        if (mounted) _showAddTaskSheet(context, _selected);
      };
    });
    // Ленивая материализация повторений для дня, открытого первым при
    // старте экрана (раньше это делал tasksForDayProvider при подписке).
    unawaited(
        ref.read(taskRepositoryProvider).ensureRecurrencesForDay(effToday));
  }

  bool get _isToday => isSameDay(_selected, _effectiveToday(DateTime.now()));

  String _title(BuildContext context) {
    if (_isToday) return context.l10n.todayTitle;
    final locale = Localizations.localeOf(context).languageCode;
    return DateFormat('d MMMM', locale).format(_selected);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final now = ref.watch(currentTimeProvider).value ?? DateTime.now();
    final isPast = _selected.isBefore(_effectiveToday(now));
    final quietStart =
        ref.watch(notificationControllerProvider).prefs.quietStart;

    final statsAsync = ref.watch(statsForDayProvider(_selected));
    final quoteLocale =
        Localizations.localeOf(context).languageCode == 'en' ? 'en' : 'ru';
    final quote = ref.watch(randomQuoteProvider(quoteLocale));
    // Подписка на общий поток задач — двигает ребилд при любой мутации.
    // Сами задачи дня читаем СРАЗУ синхронно ниже, из уже загруженного кэша
    // репозитория, а не через tasksForDayProvider.family(_selected): семейный
    // провайдер создаёт НОВЫЙ стрим при каждом переключении дня в календаре,
    // тот на кадр проваливается в loading, весь список размонтируется и
    // каскад StaggerReveal играет заново — баг «задачи пропадают и плавно
    // появляются». Синхронное чтение кэша убирает этот зазор полностью.
    ref.watch(allTasksProvider);
    final taskRepo = ref.read(taskRepositoryProvider);
    final tasksAsync = AsyncValue.data(taskRepo.tasksForDay(_selected));

    return Scaffold(
      appBar: AppBar(
        title: Text(_title(context)),
        actions: [
          IconButton(
            tooltip: l10n.searchTasksTooltip,
            icon: const Icon(Icons.search),
            onPressed: () async {
              final picked = await showSearch<DateTime?>(
                context: context,
                delegate: GlobalSearchDelegate(
                  tasks: ref.read(allTasksProvider).value ?? const [],
                  searchFieldLabel: l10n.searchTasksHint,
                ),
              );
              if (picked != null && mounted) {
                setState(() {
                  _selected = picked;
                  _focused = picked;
                });
                unawaited(taskRepo.ensureRecurrencesForDay(picked));
              }
            },
          ),
        ],
      ),
      floatingActionButton: isPast
          ? null
          : GlowFab(
              onPressed: () => _showAddTaskSheet(context, _selected),
              icon: Icons.add,
              label: l10n.addTaskFabLabel,
            ),
      body: Column(
        children: [
          TableCalendar<Task>(
            locale: Localizations.localeOf(context).languageCode,
            focusedDay: _focused,
            firstDay: DateTime(2020),
            lastDay: DateTime(2100),
            calendarFormat: _format,
            selectedDayPredicate: (d) => isSameDay(d, _selected),
            onDaySelected: (sel, foc) {
              setState(() {
                _selected = sel;
                _focused = foc;
              });
              unawaited(taskRepo.ensureRecurrencesForDay(sel));
            },
            onFormatChanged: (fmt) => setState(() => _format = fmt),
            onPageChanged: (foc) => setState(() => _focused = foc),
            startingDayOfWeek: StartingDayOfWeek.monday,
            // Кнопка формата («Месяц / 2 недели / Неделя») — в виде карточки:
            // поверхность + тёплая тень-«наклейка», без жирной обводки.
            headerStyle: HeaderStyle(
              // table_calendar берёт название месяца из intl «как есть» —
              // в русской локали оно строчное («июль»). Капитализируем сами.
              titleTextFormatter: (date, locale) =>
                  _capitalize(DateFormat.yMMMM(locale).format(date)),
              formatButtonShowsNext: false,
              formatButtonPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              formatButtonTextStyle: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
              formatButtonDecoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
                boxShadow: AppColors.stickerShadow,
                border: Border.all(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? AppColors.surfaceDarkMuted
                      : AppColors.ringTrack,
                ),
              ),
            ),
            availableCalendarFormats: {
              CalendarFormat.month: l10n.calFormatMonth,
              CalendarFormat.twoWeeks: l10n.calFormatTwoWeeks,
              CalendarFormat.week: l10n.calFormatWeek,
            },
            eventLoader: taskRepo.plannedForDay,
            calendarStyle: const CalendarStyle(
              todayDecoration: BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
            ),
            calendarBuilders: CalendarBuilders<Task>(
              markerBuilder: (context, day, tasks) {
                if (tasks.isEmpty) return const SizedBox.shrink();
                final done = tasks.where((t) => t.isCompleted).length;
                // Будущий день (ещё не наступил), где ничего не выполнено —
                // синяя точка вместо красной (не нагнетаем тревожность).
                final isFuture = dateOnly(day).isAfter(today());
                final color = done == tasks.length
                    ? AppColors.success
                    : done == 0
                        ? (isFuture ? AppColors.primary : AppColors.danger)
                        : AppColors.warning;
                return Positioned(
                  bottom: 4,
                  child: Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 6),
          const Divider(height: 1),
          Expanded(
            child: tasksAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, st) => ErrorView(
                onRetry: () {
                  ref.invalidate(tasksForDayProvider(_selected));
                  ref.invalidate(statsForDayProvider(_selected));
                },
              ),
              data: (tasks) {
                final stats = statsAsync.value;
                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                  children: [
                    // Журнальная шапка дня: день недели «глиной» + линейка +
                    // карточка «Шаблоны дня» справа.
                    _DayMasthead(
                      date: _selected,
                      onTemplates: () => showTemplatesSheet(
                        context,
                        date: _selected,
                        isPast: isPast,
                        dayTasks: tasks,
                      ),
                    ),
                    // Активный Помодоро (скрыт, когда таймер не запущен).
                    const PomodoroBanner(),
                    // Подсказка про работу в фоне (скрыта, когда не нужна).
                    const BatteryHintCard(),
                    const SizedBox(height: 8),
                    _DualRingRow(
                      productivity: stats?.productivity,
                      completedTasks: stats?.completedTasks ?? 0,
                      completedFraction: stats?.completedFraction ?? 0,
                      totalTasks: stats?.totalTasks ?? tasks.length,
                      timeliness: stats?.timeliness,
                      onTimeCount: stats?.onTimeCount ?? 0,
                      lateCount: stats?.lateCount ?? 0,
                    ),
                    // ── Бюджет дня по времени ───────────────────────────────
                    // Сумма оценок невыполненных задач. Виден только когда
                    // есть хотя бы одна оценка (метрика необязательная).
                    if (!isPast)
                      _DayBudgetRow(tasks: tasks, date: _selected, now: now),
                    // ── Оценка прошедшего дня (рефлексия) ───────────────────
                    // Прошлые дни — всегда. Сегодня — начиная с порога
                    // «за полчаса до тихих часов», чтобы не ждать полуночи.
                    if (dateOnly(_selected).isBefore(dateOnly(now)) ||
                        (isSameDay(_selected, now) &&
                            now.hour * 60 + now.minute >=
                                _dayRatingTriggerMinutes(quietStart)))
                      _DayRatingRow(date: _selected),
                    // ── Кнопки действий ─────────────────────────────────────
                    // «Скопировать» — на всех днях (когда есть задачи).
                    // «Удалить все» — только на сегодня / будущих днях.
                    // ── Карточка «Невыполненные задачи (N)» ─────────────
                    Consumer(
                      builder: (ctx, ref, _) {
                        final items =
                            ref.watch(backlogItemsProvider).value ?? const [];
                        if (items.isEmpty) return const SizedBox.shrink();
                        final oldest = items.reduce(
                            (a, b) => a.addedAt.isBefore(b.addedAt) ? a : b);
                        return Padding(
                          padding: const EdgeInsets.only(top: 6, bottom: 2),
                          child: BacklogNudgeCard(
                            icon: Icons.inbox_outlined,
                            title: l10n.backlogChip(items.length),
                            subtitle: l10n.backlogOldestLabel(oldest.title),
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => const TaskBacklogScreen(),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    if (tasks.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      // Wrap, а не Row: на узком экране три кнопки («Перенести
                      // всё» + «Скопировать» + «Удалить все») не влезают в одну
                      // строку → Row давал overflow и обрезал «Удалить все».
                      // Wrap переносит лишнюю кнопку на след. строку (вправо).
                      Wrap(
                        alignment: WrapAlignment.end,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          // «Перенести всё» — в ночном окне (0:00–3:59 и 23:xx)
                          // показывается независимо от isPast
                          Builder(builder: (ctx) {
                            final hasTransferable =
                                tasks.any((t) => _isTransferable(t, now));
                            if (!hasTransferable)
                              return const SizedBox.shrink();
                            return Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child: TextButton.icon(
                                onPressed: () => _transferAll(context, tasks),
                                icon: const Icon(Icons.east, size: 17),
                                label: Text(l10n.transferAllBtn),
                                style: TextButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 6),
                                ),
                              ),
                            );
                          }),
                          TextButton.icon(
                            onPressed: () => _copyTasks(context, tasks),
                            icon: const Icon(
                              Icons.copy_all_outlined,
                              size: 17,
                            ),
                            label: Text(l10n.copyBtn),
                            style: TextButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                            ),
                          ),
                          if (!isPast) ...[
                            const SizedBox(width: 4),
                            TextButton.icon(
                              onPressed: () => _confirmDeleteAll(context),
                              icon: const Icon(
                                Icons.delete_sweep_outlined,
                                size: 17,
                              ),
                              label: Text(l10n.deleteAllBtn),
                              style: TextButton.styleFrom(
                                foregroundColor: AppColors.danger,
                                visualDensity: VisualDensity.compact,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                    const SizedBox(height: 10),
                    if (_isToday)
                      quote.when(
                        data: (q) => q == null
                            ? const SizedBox.shrink()
                            : _QuoteCard(text: q.text, author: q.author),
                        loading: () => const SizedBox.shrink(),
                        error: (_, __) => const SizedBox.shrink(),
                      ),
                    const SizedBox(height: 8),
                    if (tasks.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: NotebookEmptyState(
                          text: _isToday
                              ? l10n.emptyTodayState
                              : l10n.emptyDayState,
                        ),
                      )
                    else
                      _TaskSections(tasks: tasks, readOnly: isPast),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showAddTaskSheet(BuildContext context, DateTime date) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => EscDismissible(child: _TaskFormSheet(date: date)),
    );
  }

  /// Открывает встроенный датапикер и копирует задачи в выбранный день.
  Future<void> _transferAll(BuildContext context, List<Task> tasks) async {
    final repo = ref.read(taskRepositoryProvider);
    final now = DateTime.now();
    // Все задачи из одного дня (_selected) → одна целевая дата для всех
    final target = _calcTransferTarget(_selected, now);
    for (final t in tasks) {
      if (_isTransferable(t, now)) {
        await repo.transferTask(t, targetDate: target);
      }
    }
  }

  Future<void> _copyTasks(BuildContext context, List<Task> tasks) async {
    final l10n = context.l10n;
    final locale = Localizations.localeOf(context).languageCode;
    final picked = await showDatePicker(
      context: context,
      initialDate: today(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: l10n.copyPickerHelp,
      locale: Locale(locale),
    );
    if (picked == null || !context.mounted) return;
    await ref
        .read(taskRepositoryProvider)
        .copyTasksTo(tasks: tasks, targetDate: picked);
    if (context.mounted) {
      showFancyToast(
        context,
        message: l10n.copiedToast(DateFormat('d MMMM', locale).format(picked)),
      );
    }
  }

  /// Показывает диалог подтверждения и удаляет все задачи выбранного дня.
  Future<void> _confirmDeleteAll(BuildContext context) async {
    final l10n = context.l10n;
    final confirmed = await showFancyDialog<bool>(
      context: context,
      icon: Icons.delete_sweep_rounded,
      iconColor: AppColors.danger,
      title: l10n.deleteAllConfirmTitle,
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
      await ref.read(taskRepositoryProvider).deleteAllForDay(_selected);
    }
  }
}

enum _TaskAction { pomodoro, actualTime, transfer, copy, edit, delete }

enum _RecurringDeleteChoice { single, fromHere, entire }

/// Строка-вариант в fancy-диалоге удаления повторяющейся задачи: иконка в
/// круге + заголовок/подпись, вся строка нажимается с лёгкой подсветкой.
class _RecurringChoiceRow extends StatelessWidget {
  const _RecurringChoiceRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = danger ? AppColors.danger : AppColors.primary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: accent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: accent.withValues(alpha: 0.14),
                  ),
                  child: Icon(icon, color: accent, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: danger ? AppColors.danger : null,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Длительность повторения («В течение»). Ограничивает endDate правила.
enum _RecDuration { month, months3, months6, year, forever }

// ─── Плитка задачи ───────────────────────────────────────────────────────────

class _TaskTile extends ConsumerWidget {
  const _TaskTile({
    required this.task,
    this.readOnly = false,
    this.swipeable = true,
  });
  final Task task;
  final bool readOnly;

  /// false — во время анимации удаления из AnimatedList (без Dismissible).
  final bool swipeable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final now = ref.watch(currentTimeProvider).value ?? DateTime.now();
    final state = _calcTimeState(task, now);
    final theme = Theme.of(context);

    final isLateCompleted = task.isCompleted && !_isTaskOnTime(task);

    // Задачу можно перенести вперёд в «ночном» окне:
    // • 0:00–3:59: прошлый календарный день ещё «effective today» → на сегодня
    // • 23:00–23:59: сегодня → на завтра (заранее отложить)
    final canTransfer = _isTransferable(task, now);

    // Редизайн «Живая бумага»: вместо заливки всей карточки цветом состояния —
    // тонкий цветной КОРЕШОК 4px слева + лёгкий тинт (~8%). Спокойнее читается.
    Color? spineColor;
    Color? cardColor;
    // «Активная» задача (время начала уже наступило) — единственный случай,
    // где тинт должен быть НЕПРОЗРАЧНЫМ: карточка обозначает то, чем нужно
    // заниматься прямо сейчас, и не должна казаться блёклой/просвечивающей
    // (особенно заметно на фоне «Точки» — сквозь alpha-тинт видны точки).
    var isActiveState = false;
    if (task.isCompleted) {
      // Выполненная — зелёный корешок (независимо от дня: и сегодня, и в
      // прошлом), кроме выполненных с опозданием — те остаются янтарными.
      spineColor = isLateCompleted ? AppColors.warning : AppColors.success;
    } else if (readOnly) {
      spineColor = AppColors.danger;
    } else {
      spineColor = switch (state) {
        _TimeState.active => theme.colorScheme.primary,
        _TimeState.urgent => AppColors.warning,
        _TimeState.overdue => AppColors.danger,
        _ => null,
      };
      isActiveState = state == _TimeState.active;
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

    final isRecurring = task.recurrenceRuleId != null;

    final Widget baseLeading = (task.isCounter || task.isChecklist)
        ? _progressLeading(context, ref, theme)
        : readOnly
            ? Icon(
                !task.isCompleted
                    ? Icons.cancel_outlined
                    : isLateCompleted
                        ? Icons.watch_later_outlined
                        : Icons.check_circle,
                color: !task.isCompleted
                    ? AppColors.danger
                    : isLateCompleted
                        ? AppColors.warning
                        : AppColors.success,
              )
            : DrawCheckBox(
                value: task.isCompleted,
                onChanged: (_) => _onCheckbox(context, ref),
              );
    // Перенесённая задача остаётся окрашенной как обычная невыполненная/
    // выполненная — просто получает маленький бейдж-стрелку поверх иконки,
    // а не полностью серое оформление (см. фикс «должна быть красной»).
    final Widget leadingWidget = task.isTransferred
        ? _withTransferredBadge(context, baseLeading)
        : baseLeading;

    final listTile = ListTile(
      leading: leadingWidget,
      title: Row(
        children: [
          Flexible(
            child: Text(
              task.title,
              style: task.isCompleted
                  ? const TextStyle(
                      decoration: TextDecoration.lineThrough,
                      color: AppColors.textSecondary,
                    )
                  : null,
            ),
          ),
          if (task.priority != TaskPriority.none) ...[
            const SizedBox(width: 6),
            Icon(
              switch (task.priority) {
                TaskPriority.high => Icons.keyboard_double_arrow_up,
                TaskPriority.medium => Icons.keyboard_arrow_up,
                _ => Icons.keyboard_arrow_down,
              },
              size: 16,
              color: switch (task.priority) {
                TaskPriority.high => AppColors.danger,
                TaskPriority.medium => AppColors.warning,
                _ => AppColors.textSecondary,
              },
            ),
          ],
          if (isRecurring) ...[
            const SizedBox(width: 6),
            Icon(
              Icons.repeat,
              size: 14,
              color: theme.colorScheme.primary.withValues(alpha: 0.7),
            ),
          ],
          if (task.goalId != null) ...[
            const SizedBox(width: 6),
            Icon(
              Icons.flag_outlined,
              size: 14,
              color: theme.colorScheme.primary.withValues(alpha: 0.7),
            ),
          ],
        ],
      ),
      subtitle: _buildSubtitle(context, ref, theme),
      trailing: task.isTransferred
          ? null
          : readOnly
              ? (canTransfer
                  ? IconButton(
                      tooltip: l10n.transferForwardTooltip,
                      icon: Icon(Icons.east, color: theme.colorScheme.primary),
                      onPressed: () => _handleTransfer(context, ref),
                    )
                  : null)
              : PopupMenuButton<_TaskAction>(
                  icon: const Icon(Icons.more_vert),
                  onSelected: (action) {
                    if (action == _TaskAction.pomodoro) {
                      ref.read(pomodoroProvider).startFocus(task);
                    } else if (action == _TaskAction.actualTime) {
                      _showActualTimeDialog(
                          context, ref.read(taskRepositoryProvider));
                    } else if (action == _TaskAction.transfer) {
                      _handleTransfer(context, ref);
                    } else if (action == _TaskAction.copy) {
                      _copyTaskToDate(context, ref);
                    } else if (action == _TaskAction.edit) {
                      showModalBottomSheet<void>(
                        context: context,
                        isScrollControlled: true,
                        useSafeArea: true,
                        builder: (_) => EscDismissible(
                          autofocus: true,
                          child: _TaskFormSheet(
                              date: task.date, existingTask: task),
                        ),
                      );
                    } else {
                      _handleDelete(context, ref);
                    }
                  },
                  itemBuilder: (_) => [
                    if (!task.isCompleted)
                      PopupMenuItem(
                        value: _TaskAction.pomodoro,
                        child: ListTile(
                          leading: const Icon(Icons.timer_outlined),
                          title: Text(
                              l10n.focusMinutesMenuItem(kPomodoroFocusMinutes)),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    if (task.estimatedMinutes != null ||
                        task.actualMinutes != null)
                      PopupMenuItem(
                        value: _TaskAction.actualTime,
                        child: ListTile(
                          leading: const Icon(Icons.timelapse_outlined),
                          title: Text(l10n.actualTimeMenuItem),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    if (canTransfer)
                      PopupMenuItem(
                        value: _TaskAction.transfer,
                        child: ListTile(
                          leading: Icon(Icons.east,
                              color: theme.colorScheme.primary),
                          title: Text(l10n.transferForwardTooltip),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    PopupMenuItem(
                      value: _TaskAction.copy,
                      child: ListTile(
                        leading: const Icon(Icons.copy_all_outlined),
                        title: Text(l10n.copyBtn),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    PopupMenuItem(
                      value: _TaskAction.edit,
                      child: ListTile(
                        leading: const Icon(Icons.edit_outlined),
                        title: Text(l10n.editMenuItem),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    PopupMenuItem(
                      value: _TaskAction.delete,
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

    final Widget content = task.isCounter
        ? Column(
            mainAxisSize: MainAxisSize.min,
            children: [listTile, _buildCounterBar(context, ref, theme)],
          )
        : task.isChecklist
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  listTile,
                  SubtaskChecklist(
                    subtasks: task.subtasks,
                    readOnly: readOnly,
                    onToggle: (s) => _toggleSub(context, ref, s),
                  ),
                ],
              )
            : listTile;

    // Кросс-фейд тинта состояния (260 мс): при смене статуса по времени
    // (обычная → активная → срочная → просрочена) фон карточки и корешок
    // плавно перетекают, а не «прыгают». TweenAnimationBuilder не анимирует
    // первую отрисовку (begin == null → берётся end), поэтому при прокрутке
    // списка карточки не мерцают.
    final Widget tileChild = spineColor == null
        ? content
        : Stack(
            children: [
              content,
              // Корешок состояния: 4px цветная лента у левого края, во всю
              // высоту карточки (включая счётчик/подзадачи).
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

    // Кросс-фейд только когда есть тинт. Без тинта (cardColor == null) —
    // обычный Card: ColorTween(end: null) запрещён (TweenAnimationBuilder
    // требует non-null end) и в release рисует серый ErrorWidget во всю высоту.
    Widget tile = cardColor == null
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

    if (state == _TimeState.upcoming) {
      tile = Opacity(opacity: 0.45, child: tile);
    }

    // Прошлые дни — только просмотр: свайп отключён.
    if (readOnly) return tile;

    // Перенесённые оригиналы нельзя удалять — история неизменна.
    if (task.isTransferred) return tile;

    // Во время анимации удаления из AnimatedList — без Dismissible.
    if (!swipeable) return tile;

    // Повторяющиеся задачи нельзя удалять свайпом: диалог выбора типа удаления
    // конфликтует с Dismissible — пока диалог открыт, AnimatedList успевает
    // убрать тайл из дерева, после чего Dismissible пытается анимировать
    // уже несуществующий виджет и падает. Удаление — только через меню ⋮.
    if (isRecurring) return tile;

    return Dismissible(
      key: ValueKey(task.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        color: AppColors.danger.withValues(alpha: 0.12),
        child: const Icon(Icons.delete_outline, color: AppColors.danger),
      ),
      onDismissed: (_) => ref.read(taskRepositoryProvider).deleteTask(task),
      child: tile,
    );
  }

  Future<void> _handleTransfer(BuildContext context, WidgetRef ref) async {
    final repo = ref.read(taskRepositoryProvider);
    final now = DateTime.now();
    final target = _calcTransferTarget(task.date, now);
    await repo.transferTask(task, targetDate: target);
  }

  /// Копирует эту одну задачу на выбранный день — оригинал остаётся на месте
  /// (в отличие от переноса). Тот же пикер/тост, что и у копирования всего дня.
  Future<void> _copyTaskToDate(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final locale = Localizations.localeOf(context).languageCode;
    final picked = await showDatePicker(
      context: context,
      initialDate: today(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: l10n.copyPickerHelp,
      locale: Locale(locale),
    );
    if (picked == null || !context.mounted) return;
    await ref
        .read(taskRepositoryProvider)
        .copyTasksTo(tasks: [task], targetDate: picked);
    if (context.mounted) {
      showFancyToast(
        context,
        message: l10n.copiedToast(DateFormat('d MMMM', locale).format(picked)),
      );
    }
  }

  Future<void> _handleDelete(BuildContext context, WidgetRef ref) async {
    if (task.recurrenceRuleId == null) {
      await ref.read(taskRepositoryProvider).deleteTask(task);
    } else {
      await _showRecurringDeleteDialog(context, ref);
    }
  }

  Future<void> _showRecurringDeleteDialog(
    BuildContext context,
    WidgetRef ref,
  ) async {
    // Читаем repo ДО await — правило Riverpod: не использовать ref после
    // async-разрыва, иначе возможно тихое исключение если виджет перестроен.
    final repo = ref.read(taskRepositoryProvider);
    final l10n = context.l10n;

    final choice = await showFancyDialog<_RecurringDeleteChoice>(
      context: context,
      icon: Icons.repeat_rounded,
      iconColor: AppColors.primary,
      title: l10n.recurringDeleteTitle,
      contentBuilder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _RecurringChoiceRow(
            icon: Icons.event_busy_outlined,
            title: l10n.recurringDeleteSingleTitle,
            subtitle: l10n.recurringDeleteSingleSubtitle,
            onTap: () => Navigator.pop(ctx, _RecurringDeleteChoice.single),
          ),
          _RecurringChoiceRow(
            icon: Icons.skip_next_outlined,
            title: l10n.recurringDeleteFromHereTitle,
            subtitle: l10n.recurringDeleteFromHereSubtitle,
            onTap: () => Navigator.pop(ctx, _RecurringDeleteChoice.fromHere),
          ),
          _RecurringChoiceRow(
            icon: Icons.delete_sweep_outlined,
            title: l10n.recurringDeleteEntireTitle,
            subtitle: l10n.recurringDeleteEntireSubtitle,
            danger: true,
            onTap: () => Navigator.pop(ctx, _RecurringDeleteChoice.entire),
          ),
        ],
      ),
    );

    if (choice == null) return;
    // Виджет мог быть демонтирован пока диалог был открыт.
    if (!context.mounted) return;

    switch (choice) {
      case _RecurringDeleteChoice.single:
        await repo.deleteTask(task);
        break;
      case _RecurringDeleteChoice.fromHere:
        await repo.deleteOccurrencesFrom(task);
        break;
      case _RecurringDeleteChoice.entire:
        await repo.deleteEntireSeries(
          task.recurrenceRuleId!,
          cutoffDate: _effectiveToday(DateTime.now()),
        );
        break;
    }
  }

  /// Счётчик: полоса прогресса на всю ширину сверху, под ней по центру —
  /// [−] [значение] [+]. Тап по значению — ручной ввод (удобно для больших целей).
  Widget _buildCounterBar(
      BuildContext context, WidgetRef ref, ThemeData theme) {
    final pct = ((task.counterProgress ?? 0) * 100).round();
    final repo = ref.read(taskRepositoryProvider);
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
                  begin: 0, end: (task.counterProgress ?? 0).clamp(0.0, 1.0)),
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
              if (!readOnly)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  iconSize: 30,
                  icon: const Icon(Icons.remove_circle_outline),
                  onPressed: task.progressCount > 0
                      ? () => repo.incrementCounter(task, -1)
                      : null,
                ),
              InkWell(
                onTap:
                    readOnly ? null : () => _showSetCounterDialog(context, ref),
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${compactCount(task.progressCount)} / ${compactCount(task.targetCount!)}  ·  $pct%',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: muted,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (!readOnly) ...[
                        const SizedBox(width: 4),
                        Icon(Icons.edit, size: 13, color: muted),
                      ],
                    ],
                  ),
                ),
              ),
              if (!readOnly)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  iconSize: 30,
                  icon: const Icon(Icons.add_circle),
                  color: theme.colorScheme.primary,
                  onPressed: task.progressCount < (task.targetCount ?? 0)
                      ? () async {
                          final willComplete =
                              task.progressCount + 1 >= task.targetCount!;
                          final navContext =
                              Navigator.of(context, rootNavigator: true)
                                  .context;
                          await repo.incrementCounter(task, 1);
                          if (willComplete) {
                            await _maybePromptActualTime(navContext, repo);
                            await _promptQuality(navContext, repo);
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

  /// Маленький бейдж-стрелка поверх обычной leading-иконки — помечает, что
  /// задача была перенесена, не меняя её обычный цвет/статус-иконку.
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

  /// Leading-кольцо для счётчика/чек-листа. У чек-листа (не readOnly) —
  /// кликабельно: отмечает всю задачу выполненной (и все подзадачи).
  Widget _progressLeading(
      BuildContext context, WidgetRef ref, ThemeData theme) {
    // Выполнено — кольцо зелёное (как корешок карточки), с опозданием —
    // янтарное; иначе обычный акцентный цвет темы.
    final ringColor = task.isCompleted
        ? (_isTaskOnTime(task) ? AppColors.success : AppColors.warning)
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
                  begin: 0, end: (task.progressRingValue ?? 0).clamp(0.0, 1.0)),
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
          task.isCompleted
              ? const Icon(Icons.check, size: 18, color: AppColors.success)
              : Text(
                  task.isChecklist
                      ? '${task.subtasksDone}/${task.subtasks.length}'
                      : compactCount(task.progressCount),
                  style: theme.textTheme.labelSmall,
                ),
        ],
      ),
    );
    if ((task.isChecklist || task.isCounter) && !readOnly) {
      return InkWell(
        customBorder: const CircleBorder(),
        onTap: () => _completeAll(context, ref),
        child: Tooltip(
          message: task.isCompleted
              ? context.l10n.resetTooltip
              : context.l10n.markDoneTooltip,
          child: ring,
        ),
      );
    }
    return ring;
  }

  /// Отмечает задачу выполненной целиком и обратно: чек-лист — все подзадачи,
  /// счётчик — прогресс в цель / 0.
  Future<void> _completeAll(BuildContext context, WidgetRef ref) async {
    final repo = ref.read(taskRepositoryProvider);
    final navContext = Navigator.of(context, rootNavigator: true).context;
    final willComplete = !task.isCompleted;
    if (task.isChecklist) {
      await repo.setAllSubtasksDone(task, willComplete);
    } else {
      await repo.setCounterProgress(task, willComplete ? task.targetCount! : 0);
    }
    if (willComplete) {
      await _maybePromptActualTime(navContext, repo);
      await _promptQuality(navContext, repo);
    }
  }

  /// Переключает подзадачу; если это завершает задачу — опрос качества.
  Future<void> _toggleSub(
      BuildContext context, WidgetRef ref, SubTask sub) async {
    final repo = ref.read(taskRepositoryProvider);
    final navContext = Navigator.of(context, rootNavigator: true).context;
    // Завершится ли задача этим переключением (отмечаем последнюю невыполненную).
    final willComplete = !sub.done &&
        task.subtasks.where((x) => x.id != sub.id).every((x) => x.done);
    await repo.toggleSubtask(task, sub.id);
    if (willComplete) {
      await _maybePromptActualTime(navContext, repo);
      await _promptQuality(navContext, repo);
    }
  }

  /// Диалог ручного ввода точного значения счётчика.
  Future<void> _showSetCounterDialog(
      BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final repo = ref.read(taskRepositoryProvider);
    final navContext = Navigator.of(context, rootNavigator: true).context;
    final controller = TextEditingController(text: '${task.progressCount}');
    final value = await showFancyDialog<int>(
      context: context,
      icon: Icons.tag_rounded,
      iconColor: AppColors.primary,
      title: task.title,
      autofocusEsc: false,
      contentBuilder: (ctx) => TextField(
        controller: controller,
        autofocus: true,
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        decoration: InputDecoration(
          border: const OutlineInputBorder(),
          suffixText: '/ ${task.targetCount}',
          helperText: l10n.enterNumberHelper(task.targetCount!),
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
      final willComplete = !task.isCompleted && value >= task.targetCount!;
      await repo.setCounterProgress(task, value);
      if (willComplete) {
        await _maybePromptActualTime(navContext, repo);
        await _promptQuality(navContext, repo);
      }
    }
  }

  Widget? _buildSubtitle(BuildContext context, WidgetRef ref, ThemeData theme) {
    // Время + хэштеги — в один ряд (пилюли встают рядом со временем).
    final l10n = context.l10n;
    final metaChildren = <Widget>[];
    final timeLabel = task.timeLabelWith(
        fromWord: l10n.timeFromWord, toWord: l10n.timeToWord);
    if (timeLabel != null) {
      metaChildren.add(Text(timeLabel, style: theme.textTheme.bodySmall));
    }
    for (final t in task.tags) {
      metaChildren.add(TagMini(label: t));
    }

    final lines = <String>[];
    if (task.estimatedMinutes != null) {
      final est = '~${_fmtDuration(task.estimatedMinutes!, context)}';
      lines.add(task.actualMinutes != null
          ? context.l10n.estimateWithActual(
              est, _fmtDuration(task.actualMinutes!, context))
          : est);
    }
    if (task.description != null) lines.add(task.description!);

    // Оценка качества показывается только если выставлена (рефлексия).
    final showQuality = task.isCompleted && task.quality != null;
    if (metaChildren.isEmpty && lines.isEmpty && !showQuality) return null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (metaChildren.isNotEmpty)
          Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: metaChildren,
          ),
        for (final l in lines) Text(l, style: theme.textTheme.bodySmall),
        if (showQuality)
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: GestureDetector(
              onTap: () =>
                  _promptQuality(context, ref.read(taskRepositoryProvider)),
              behavior: HitTestBehavior.opaque,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  StarRating(value: task.quality!, size: 13),
                  const SizedBox(width: 6),
                  Text(
                    '${task.quality!}/10',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _onCheckbox(BuildContext context, WidgetRef ref) async {
    // Захватываем живой repo и стабильный navigator-контекст ДО переключения:
    // после выполнения плитка переезжает в «Выполненные» и уничтожается,
    // поэтому ref/context этой плитки станут невалидны к моменту сохранения.
    final repo = ref.read(taskRepositoryProvider);
    final navContext = Navigator.of(context, rootNavigator: true).context;
    // Идёт Помодоро по этой задаче? Останавливаем и фиксируем факт ДО вопроса.
    ref.read(pomodoroProvider).stopIfTracking(task.id);
    final wasIncomplete = !task.isCompleted;
    // При выполнении даём галочке прочертиться (DrawCheckBox рисует ~340 мс)
    // ДО того, как задача уедет в «Выполненные» и плитка будет уничтожена.
    if (wasIncomplete) {
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }
    await repo.toggleCompleted(task);
    if (!wasIncomplete) return;
    await _maybePromptActualTime(navContext, repo);
    await _promptQuality(navContext, repo);
  }

  /// Спрашивает факт. время при выполнении — только если у задачи есть
  /// оценка и факт ещё не накоплен (свежее чтение из кэша). Общий шаг для
  /// всех способов завершить задачу: чекбокс, кольцо чек-листа/счётчика,
  /// последняя подзадача, инкремент/ручной ввод счётчика.
  Future<void> _maybePromptActualTime(
      BuildContext context, TaskRepository repo) async {
    final actual = repo.taskById(task.id)?.actualMinutes;
    if (task.estimatedMinutes != null && actual == null) {
      await _showActualTimeDialog(context, repo);
    }
  }

  /// Необязательный опрос качества выполнения. Открывает диалог со звёздами,
  /// при выборе — сохраняет оценку. Используется и для обычных задач, и при
  /// добивании счётчика до цели. [repo] передаётся явно (живой объект), чтобы
  /// сохранение пережило уничтожение плитки.
  Future<void> _promptQuality(BuildContext context, TaskRepository repo) async {
    final rating = await showQualityDialog(
      context,
      question: context.l10n.qualityQuestion,
      initial: task.quality,
    );
    if (rating != null) {
      await repo.setQuality(task, rating);
    }
  }

  /// Диалог факт. времени — и при выполнении («сколько ушло»), и для
  /// корректировки уже записанного (в т.ч. того, что насчитал Помодоро).
  /// Предзаполняется текущим [Task.actualMinutes] (свежее чтение из кэша).
  Future<void> _showActualTimeDialog(
      BuildContext context, TaskRepository repo) async {
    final l10n = context.l10n;
    final initial = repo.taskById(task.id)?.actualMinutes;
    int? selected = initial;
    await showFancyRawDialog<void>(
      context: context,
      barrierLabel: l10n.actualTimeTitle,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return FancyDialogCard(
            icon: Icons.timer_outlined,
            iconColor: AppColors.primary,
            title: l10n.actualTimeTitle,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 14),
                if (task.estimatedMinutes != null) ...[
                  Text(
                    l10n.estimateLabel(
                        _fmtDuration(task.estimatedMinutes!, ctx)),
                    style: Theme.of(ctx).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                ],
                // Чипы-пресеты + поле «Своё (мин)» — тот же пикер, что в форме.
                _DurationPicker(
                  initialValue: initial,
                  onChanged: (v) => setDialogState(() => selected = v),
                ),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: Text(l10n.cancel),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: (selected == null || selected! <= 0)
                          ? null
                          : () {
                              repo.updateActualMinutes(task, selected!);
                              Navigator.of(ctx).pop();
                            },
                      child: Text(l10n.save),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ─── Форма добавления / редактирования задачи ────────────────────────────────

class _TaskFormSheet extends ConsumerStatefulWidget {
  const _TaskFormSheet({required this.date, this.existingTask});
  final DateTime date;
  final Task? existingTask;

  bool get isEditing => existingTask != null;

  @override
  ConsumerState<_TaskFormSheet> createState() => _TaskFormSheetState();
}

class _TaskFormSheetState extends ConsumerState<_TaskFormSheet> {
  late final TextEditingController _titleController;
  int? _startMinutes;
  int? _endMinutes;
  int? _estimatedMinutes;

  // ── Счётчик (задача с прогрессом к числу) ─────────────────────────────────
  bool _isCounter = false;
  int _targetCount = 5;

  // ── Подзадачи (чек-лист) ──────────────────────────────────────────────────
  // Параллельные списки: контроллер текста + оригинальная подзадача (для
  // сохранения id/done при редактировании; null — новая подзадача).
  final List<TextEditingController> _subtaskCtrls = [];
  final List<SubTask?> _subtaskOrig = [];
  bool get _hasSubtasks => _subtaskCtrls.isNotEmpty;

  // ── Приоритет и теги ──────────────────────────────────────────────────────
  TaskPriority _priority = TaskPriority.none;
  final Set<String> _tags = {};
  final _tagCtrl = TextEditingController();
  final _tagSearchCtrl = TextEditingController();
  String _tagSearch = '';

  // ── Привязка к цели ───────────────────────────────────────────────────────
  String? _goalId;

  // ── Состояние повторения (только для новых задач) ─────────────────────────
  bool _isRecurring = false;
  RecurrenceKind _recurrenceKind = RecurrenceKind.weekly;
  final Set<int> _weekdays = {}; // 1..7 (пн..вс)
  final Set<int> _monthDays = {}; // 1..31
  int _intervalDays = 2;
  _RecDuration _recDuration = _RecDuration.year;

  bool get _isFromSeries => widget.existingTask?.recurrenceRuleId != null;

  @override
  void initState() {
    super.initState();
    final t = widget.existingTask;
    _titleController = TextEditingController(text: t?.title ?? '');
    _startMinutes = t?.startMinutes;
    _endMinutes = t?.endMinutes;
    _estimatedMinutes = t?.estimatedMinutes;
    _isCounter = t?.isCounter ?? false;
    _targetCount = t?.targetCount ?? 5;
    _goalId = t?.goalId;
    _priority = t?.priority ?? TaskPriority.none;
    _tags.addAll(t?.tags ?? const []);
    // Префилл подзадач из редактируемой задачи.
    for (final s in (t?.subtasks ?? const <SubTask>[])) {
      _subtaskCtrls.add(TextEditingController(text: s.title));
      _subtaskOrig.add(s);
    }
    // По умолчанию — текущий день недели предзаполнен для weekly.
    _weekdays.add(widget.date.weekday);
    _monthDays.add(widget.date.day);
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    // Повтор можно настраивать только при создании новой задачи. Для задач
    // из существующей серии — показываем подсказку, что меняется только
    // этот экземпляр; серию редактируем отдельно (TODO: будущий этап).
    // Повторение можно настроить при создании и при редактировании ОБЫЧНОЙ
    // (не из серии) задачи. У задачи из серии — только подсказка.
    final canEditRecurrence = !_isFromSeries;

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
            TextField(
              controller: _titleController,
              autofocus: !widget.isEditing,
              decoration: InputDecoration(
                hintText: l10n.taskTitleHint,
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _TimePicker(
                    label: l10n.timeFromLabel,
                    minutes: _startMinutes,
                    onChanged: (v) => setState(() => _startMinutes = v),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _TimePicker(
                    label: l10n.timeToLabel,
                    minutes: _endMinutes,
                    onChanged: (v) => setState(() => _endMinutes = v),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(l10n.estimateSectionLabel, style: theme.textTheme.labelMedium),
            const SizedBox(height: 6),
            _DurationPicker(
              initialValue: _estimatedMinutes,
              onChanged: (v) => _estimatedMinutes = v,
            ),
            const SizedBox(height: 12),
            _buildPrioritySection(theme),
            const SizedBox(height: 8),
            // Счётчик и подзадачи взаимоисключающи.
            if (!_hasSubtasks) _buildCounterSection(theme),
            if (!_isCounter) _buildSubtasksSection(theme),
            _buildTagsSection(theme),
            _buildGoalPicker(theme),
            const SizedBox(height: 8),
            if (canEditRecurrence) _buildRecurrenceSection(theme),
            if (_isFromSeries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Icon(Icons.repeat,
                        size: 16, color: theme.colorScheme.primary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        l10n.fromSeriesNote,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
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

  /// Пикер цели для привязки задачи. Показывается, только если на дату задачи
  /// есть цели-счётчики.
  Widget _buildGoalPicker(ThemeData theme) {
    final goals =
        ref.read(goalRepositoryProvider).counterGoalsForDate(widget.date);
    if (goals.isEmpty) return const SizedBox.shrink();
    final validId = goals.any((g) => g.id == _goalId) ? _goalId : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Text(context.l10n.goalSectionLabel, style: theme.textTheme.labelMedium),
        const SizedBox(height: 6),
        DropdownButtonFormField<String?>(
          initialValue: validId,
          isExpanded: true,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
          items: [
            DropdownMenuItem<String?>(
              value: null,
              child: Text(context.l10n.noGoalOption),
            ),
            for (final g in goals)
              DropdownMenuItem<String?>(
                value: g.id,
                child: Text(
                  '${g.title} · ${compactCount(g.progressCount)}/${compactCount(g.targetCount!)}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (v) => setState(() => _goalId = v),
        ),
      ],
    );
  }

  Widget _buildCounterSection(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Text(context.l10n.counterSwitchTitle),
          subtitle: Text(context.l10n.counterSwitchSubtitle),
          value: _isCounter,
          onChanged: (v) => setState(() => _isCounter = v),
        ),
        if (_isCounter)
          Row(
            children: [
              Text(context.l10n.counterTargetLabel),
              const SizedBox(width: 12),
              SizedBox(
                width: 110,
                child: TextFormField(
                  initialValue: '$_targetCount',
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    isDense: true,
                    contentPadding:
                        EdgeInsets.symmetric(vertical: 10, horizontal: 10),
                  ),
                  onChanged: (v) {
                    final n = int.tryParse(v.trim());
                    if (n != null && n >= 2) _targetCount = n;
                  },
                ),
              ),
              const SizedBox(width: 8),
              Text(context.l10n.counterTargetExample,
                  style: theme.textTheme.bodySmall),
            ],
          ),
      ],
    );
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
    // Нормализуем: без «#», без пробелов по краям, в нижнем регистре.
    final tag = raw.trim().replaceAll('#', '').toLowerCase();
    if (tag.isEmpty) return;
    setState(() => _tags.add(tag));
    _tagCtrl.clear();
  }

  Widget _buildTagsSection(ThemeData theme) {
    // Подсказки: все теги из существующих задач, кроме уже выбранных.
    // Раньше показывались только первые 8 (`known.take(8)`) — при большем
    // числе тегов часть просто не была видна. Теперь видны все: список
    // ограничен по ВЫСОТЕ (скролл), а не по количеству, плюс поиск, если
    // тегов много — чтобы форма не растягивалась на весь экран.
    final known = (<String>{
      for (final t in ref.read(allTasksProvider).value ?? const <Task>[])
        ...t.tags,
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
              border: OutlineInputBorder(),
              isDense: true,
              prefixText: '# ',
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            onSubmitted: _addTag,
          ),
        ),
      ],
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

  Widget _buildRecurrenceSection(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Text(context.l10n.recurringSwitchTitle),
          value: _isRecurring,
          onChanged: (v) => setState(() => _isRecurring = v),
        ),
        if (_isRecurring) ...[
          Wrap(
            spacing: 6,
            children: [
              for (final k in RecurrenceKind.values)
                SegChip(
                  label: _kindLabel(k),
                  selected: _recurrenceKind == k,
                  onTap: () => setState(() => _recurrenceKind = k),
                ),
            ],
          ),
          const SizedBox(height: 8),
          switch (_recurrenceKind) {
            RecurrenceKind.weekly => _buildWeekdaysPicker(theme),
            RecurrenceKind.monthly => _buildMonthDaysPicker(theme),
            RecurrenceKind.interval => _buildIntervalPicker(theme),
          },
          const SizedBox(height: 10),
          Text(context.l10n.recDurationSectionLabel,
              style: theme.textTheme.labelMedium),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            children: [
              for (final d in _RecDuration.values)
                SegChip(
                  label: _durationLabel(d),
                  selected: _recDuration == d,
                  onTap: () => setState(() => _recDuration = d),
                ),
            ],
          ),
        ],
      ],
    );
  }

  String _durationLabel(_RecDuration d) {
    final l10n = context.l10n;
    return switch (d) {
      _RecDuration.month => l10n.recDurationMonth,
      _RecDuration.months3 => l10n.recDurationMonths3,
      _RecDuration.months6 => l10n.recDurationMonths6,
      _RecDuration.year => l10n.recDurationYear,
      _RecDuration.forever => l10n.recDurationForever,
    };
  }

  /// Дата окончания правила по выбранной длительности (null = бессрочно).
  DateTime? _computeEndDate() {
    final s = dateOnly(widget.date);
    return switch (_recDuration) {
      _RecDuration.month => DateTime(s.year, s.month + 1, s.day),
      _RecDuration.months3 => DateTime(s.year, s.month + 3, s.day),
      _RecDuration.months6 => DateTime(s.year, s.month + 6, s.day),
      _RecDuration.year => DateTime(s.year + 1, s.month, s.day),
      _RecDuration.forever => null,
    };
  }

  Widget _buildWeekdaysPicker(ThemeData theme) {
    final l10n = context.l10n;
    final labels = [
      l10n.weekdayMon,
      l10n.weekdayTue,
      l10n.weekdayWed,
      l10n.weekdayThu,
      l10n.weekdayFri,
      l10n.weekdaySat,
      l10n.weekdaySun,
    ];
    return Wrap(
      spacing: 6,
      children: [
        for (var i = 0; i < 7; i++)
          SegChip(
            label: labels[i],
            selected: _weekdays.contains(i + 1),
            onTap: () => setState(() {
              if (_weekdays.contains(i + 1)) {
                _weekdays.remove(i + 1);
              } else {
                _weekdays.add(i + 1);
              }
            }),
          ),
      ],
    );
  }

  Widget _buildMonthDaysPicker(ThemeData theme) {
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (var d = 1; d <= 31; d++)
          SegChip(
            label: '$d',
            selected: _monthDays.contains(d),
            onTap: () => setState(() {
              if (_monthDays.contains(d)) {
                _monthDays.remove(d);
              } else {
                _monthDays.add(d);
              }
            }),
          ),
      ],
    );
  }

  Widget _buildIntervalPicker(ThemeData theme) {
    return Row(
      children: [
        Text(context.l10n.everyLabel),
        const SizedBox(width: 8),
        SizedBox(
          width: 60,
          child: TextFormField(
            initialValue: '$_intervalDays',
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
              contentPadding: EdgeInsets.symmetric(vertical: 10),
            ),
            onChanged: (v) {
              final n = int.tryParse(v);
              if (n != null && n > 0) _intervalDays = n;
            },
          ),
        ),
        const SizedBox(width: 8),
        Text(context.l10n.daysShort),
      ],
    );
  }

  String _kindLabel(RecurrenceKind k) {
    final l10n = context.l10n;
    return switch (k) {
      RecurrenceKind.weekly => l10n.recKindWeekly,
      RecurrenceKind.monthly => l10n.recKindMonthly,
      RecurrenceKind.interval => l10n.recKindInterval,
    };
  }

  /// Названия подзадач (непустые) — для путей создания.
  List<String> _subtaskTitles() => [
        for (final c in _subtaskCtrls)
          if (c.text.trim().isNotEmpty) c.text.trim(),
      ];

  /// Подзадачи для редактирования: сохраняют id/done существующих, новым — id.
  List<SubTask> _subtasksForEdit() {
    final result = <SubTask>[];
    for (var i = 0; i < _subtaskCtrls.length; i++) {
      final title = _subtaskCtrls[i].text.trim();
      if (title.isEmpty) continue;
      final orig = _subtaskOrig[i];
      result.add(orig != null
          ? orig.copyWith(title: title)
          : SubTask(
              id: 'st-${DateTime.now().microsecondsSinceEpoch}-$i',
              title: title));
    }
    return result;
  }

  Future<void> _save() async {
    final text = _titleController.text.trim();
    if (text.isEmpty) return;
    // Тег, набранный но не подтверждённый Enter, тоже забираем.
    if (_tagCtrl.text.trim().isNotEmpty) _addTag(_tagCtrl.text);
    final repo = ref.read(taskRepositoryProvider);
    final subtaskTitles = _subtaskTitles();

    if (_isRecurring && _recurrenceValid() && !_isFromSeries) {
      // Создаём правило. При редактировании обычной задачи — заменяем её серией.
      if (widget.isEditing) {
        await repo.deleteTask(widget.existingTask!);
      }
      await repo.createRecurrence(
        title: text,
        kind: _recurrenceKind,
        startDate: widget.date,
        weekdays: _weekdays.toList()..sort(),
        monthDays: _monthDays.toList()..sort(),
        intervalDays: _intervalDays,
        startMinutes: _startMinutes,
        endMinutes: _endMinutes,
        estimatedMinutes: _estimatedMinutes,
        targetCount: _isCounter ? _targetCount : null,
        endDate: _computeEndDate(),
        subtaskTitles: subtaskTitles,
        priority: _priority,
        tags: _tags.toList(),
      );
    } else if (widget.isEditing) {
      final existing = widget.existingTask!;
      final now = DateTime.now();
      final subs = _subtasksForEdit();
      var updated = existing.copyWith(
        title: text,
        startMinutes: _startMinutes,
        clearStartMinutes: _startMinutes == null,
        endMinutes: _endMinutes,
        clearEndMinutes: _endMinutes == null,
        estimatedMinutes: _estimatedMinutes,
        clearEstimatedMinutes: _estimatedMinutes == null,
        targetCount: _isCounter ? _targetCount : null,
        clearTargetCount: !_isCounter,
        goalId: _goalId,
        clearGoalId: _goalId == null,
        subtasks: subs,
        priority: _priority,
        tags: _tags.toList(),
        updatedAt: now,
      );
      // Если есть подзадачи — статус задачи определяется ими.
      if (subs.isNotEmpty) {
        final allDone = subs.every((s) => s.done);
        updated = updated.copyWith(
          completedAt: allDone ? (existing.completedAt ?? now) : null,
          clearCompleted: !allDone,
        );
      }
      await repo.updateTask(updated);
    } else {
      await repo.createAndAdd(
        title: text,
        date: widget.date,
        startMinutes: _startMinutes,
        endMinutes: _endMinutes,
        estimatedMinutes: _estimatedMinutes,
        targetCount: _isCounter ? _targetCount : null,
        goalId: _goalId,
        subtaskTitles: subtaskTitles,
        priority: _priority,
        tags: _tags.toList(),
      );
    }
    if (mounted) Navigator.of(context).pop();
  }

  /// Проверка, что выбранные параметры повторения имеют смысл — иначе
  /// просто сохраняем как обычную задачу без правила.
  bool _recurrenceValid() {
    switch (_recurrenceKind) {
      case RecurrenceKind.weekly:
        return _weekdays.isNotEmpty;
      case RecurrenceKind.monthly:
        return _monthDays.isNotEmpty;
      case RecurrenceKind.interval:
        return _intervalDays > 0;
    }
  }
}

// ─── Выбор времени ───────────────────────────────────────────────────────────

class _TimePicker extends StatelessWidget {
  const _TimePicker({
    required this.label,
    required this.minutes,
    required this.onChanged,
  });

  final String label;
  final int? minutes;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    final hasTime = minutes != null;
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            icon: const Icon(Icons.access_time, size: 16),
            label: Text(
              hasTime ? '$label: ${_fmtTime(minutes!)}' : label,
              overflow: TextOverflow.ellipsis,
            ),
            style: hasTime
                ? OutlinedButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.primary,
                  )
                : null,
            onPressed: () async {
              final picked = await showTimePicker(
                context: context,
                initialTime: hasTime
                    ? TimeOfDay(hour: minutes! ~/ 60, minute: minutes! % 60)
                    : const TimeOfDay(hour: 9, minute: 0),
              );
              if (picked != null && context.mounted) {
                onChanged(picked.hour * 60 + picked.minute);
              }
            },
          ),
        ),
        if (hasTime)
          IconButton(
            iconSize: 18,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            icon: const Icon(Icons.close),
            onPressed: () => onChanged(null),
          ),
      ],
    );
  }
}

// ─── Выбор длительности ──────────────────────────────────────────────────────

class _DurationPicker extends StatefulWidget {
  const _DurationPicker({required this.initialValue, required this.onChanged});

  final int? initialValue;
  final ValueChanged<int?> onChanged;

  @override
  State<_DurationPicker> createState() => _DurationPickerState();
}

class _DurationPickerState extends State<_DurationPicker> {
  static const _presets = [15, 30, 45, 60, 90, 120];

  int? _chipSelected;
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    final v = widget.initialValue;
    if (v != null && _presets.contains(v)) {
      _chipSelected = v;
      _ctrl = TextEditingController();
    } else {
      _ctrl = TextEditingController(text: v != null ? '$v' : '');
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            for (final m in _presets)
              SegChip(
                label: _fmtDuration(m, context),
                selected: _chipSelected == m,
                onTap: () {
                  setState(() {
                    _chipSelected = _chipSelected == m ? null : m;
                    if (_chipSelected != null) _ctrl.clear();
                  });
                  widget.onChanged(_chipSelected);
                },
              ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: 150,
          child: TextField(
            controller: _ctrl,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              hintText: context.l10n.customMinutesHint,
              border: OutlineInputBorder(),
              isDense: true,
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            onChanged: (val) {
              setState(() => _chipSelected = null);
              widget.onChanged(int.tryParse(val));
            },
          ),
        ),
      ],
    );
  }
}

// ─── Секции задач (срочные + невыполненные + выполненные) ────────────────────

class _TaskSections extends ConsumerStatefulWidget {
  const _TaskSections({required this.tasks, required this.readOnly});
  final List<Task> tasks;
  final bool readOnly;

  @override
  ConsumerState<_TaskSections> createState() => _TaskSectionsState();
}

class _TaskSectionsState extends ConsumerState<_TaskSections> {
  static const _dur = Duration(milliseconds: 280);

  final _urgKey = GlobalKey<AnimatedListState>();
  final _incKey = GlobalKey<AnimatedListState>();
  final _comKey = GlobalKey<AnimatedListState>();

  late List<Task> _urg; // срочные
  late List<Task> _inc; // невыполненные (не срочные)
  late List<Task> _com; // выполненные
  bool _comExpanded = true;

  /// Ключ сортировки как в TaskRepository (время → приоритет → order), с
  /// двумя поправками:
  /// 1) задача БЕЗ времени с высоким приоритетом сортируется так, будто её
  ///    время — «сейчас» ([now]), а не «в самом конце дня» — иначе она
  ///    рисовалась ниже вообще любой задачи с указанным временем, даже если
  ///    то время ещё не наступило;
  /// 2) задача С временем, которое ЕЩЁ НЕ НАСТУПИЛО («неактивная»,
  ///    _TimeState.upcoming) — уходит в отдельный нижний ярус, ниже даже
  ///    обычных задач без времени: она пока не актуальна для действия
  ///    прямо сейчас, в отличие от гибкой (без привязки ко времени) задачи.
  static int _sortKey(Task t, DateTime now) {
    final nowMin = now.hour * 60 + now.minute;
    final primary = t.startMinutes ?? t.endMinutes;
    if (primary != null) {
      if (_calcTimeState(t, now) == _TimeState.upcoming) {
        return 2000000 + primary;
      }
      return primary;
    }
    if (t.priority == TaskPriority.high) return nowMin;
    final prioritySlot = TaskPriority.high.index - t.priority.index;
    return 1440 + prioritySlot * 100000 + t.order;
  }

  static List<Task> _sorted(Iterable<Task> src, DateTime now) {
    return [...src]..sort((a, b) {
        final ka = _sortKey(a, now);
        final kb = _sortKey(b, now);
        // При равенстве ключей (например, несколько задач без времени с
        // высоким приоритетом — у всех ключ = nowMin) — по порядку задачи.
        return ka != kb ? ka.compareTo(kb) : a.order.compareTo(b.order);
      });
  }

  /// Задача попадает в «Срочно»: невыполнена и статус urgent или overdue.
  bool _isUrgent(Task t, DateTime now) {
    if (t.isCompleted || t.isTransferred) return false;
    final state = _calcTimeState(t, now);
    return state == _TimeState.urgent || state == _TimeState.overdue;
  }

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _urg = _sorted(widget.tasks.where((t) => _isUrgent(t, now)), now);
    _inc = _sorted(
        widget.tasks.where((t) => !t.isCompleted && !_isUrgent(t, now)), now);
    _com = _sorted(widget.tasks.where((t) => t.isCompleted), now);
  }

  @override
  void didUpdateWidget(_TaskSections old) {
    super.didUpdateWidget(old);
    if (old.tasks != widget.tasks) {
      final now = ref.read(currentTimeProvider).value ?? DateTime.now();
      _syncAll(widget.tasks, now);
    }
  }

  void _syncAll(List<Task> tasks, DateTime now) {
    _diff(_urg, _sorted(tasks.where((t) => _isUrgent(t, now)), now), _urgKey);
    _diff(
        _inc,
        _sorted(tasks.where((t) => !t.isCompleted && !_isUrgent(t, now)), now),
        _incKey);
    _diff(_com, _sorted(tasks.where((t) => t.isCompleted), now), _comKey);
    setState(() {});
  }

  void _diff(
    List<Task> cur,
    List<Task> nxt,
    GlobalKey<AnimatedListState> key,
  ) {
    // Удаляем исчезнувшие (с конца, чтобы не сбить индексы).
    for (var i = cur.length - 1; i >= 0; i--) {
      if (!nxt.any((t) => t.id == cur[i].id)) {
        final removed = cur.removeAt(i);
        key.currentState?.removeItem(
          i,
          (ctx, anim) => _animTile(removed, anim, swipeable: false),
          duration: _dur,
        );
      }
    }
    // Вставляем новые и переставляем существующие, чей порядок в nxt
    // изменился (например, поменяли приоритет у задачи без времени в том же
    // ярусе — она должна переехать сразу, а не просто молча обновить данные
    // на старом месте). Идём по nxt слева направо: к этому моменту cur[0..i)
    // уже точно совпадает с nxt[0..i), а хвост cur[i..) содержит то, что ещё
    // предстоит расставить.
    for (var i = 0; i < nxt.length; i++) {
      final target = nxt[i];
      final curIdx = cur.indexWhere((t) => t.id == target.id);
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

  Widget _animTile(Task task, Animation<double> anim,
      {bool swipeable = true, int? revealIndex}) {
    final tile = SizeTransition(
      sizeFactor: CurvedAnimation(parent: anim, curve: Curves.easeInOut),
      child: FadeTransition(
        opacity: CurvedAnimation(parent: anim, curve: Curves.easeIn),
        child: _TaskTile(
          task: task,
          readOnly: widget.readOnly,
          swipeable: swipeable,
        ),
      ),
    );
    // Стаггер-появление: каскад при первой отрисовке/смене дня. Не применяем
    // для анимации удаления (revealIndex == null), иначе плитка «проявлялась»
    // бы, пока её схлопывает SizeTransition.
    if (revealIndex == null) return tile;
    return StaggerReveal(
      key: ValueKey('reveal-${task.id}'),
      index: revealIndex,
      child: tile,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;

    // При каждом тике таймера пересчитываем срочность — задачи могут
    // переходить из «Невыполненных» в «Срочные» и обратно.
    ref.listen(currentTimeProvider, (_, next) {
      _syncAll(widget.tasks, next.value ?? DateTime.now());
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Срочные ───────────────────────────────────────────────────────
        // AnimatedList всегда в дереве; AnimatedAlign + ClipRect скрывают его
        // когда срочных нет — это позволяет insertItem работать в любой момент.
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
                      Icon(
                        Icons.access_alarm_rounded,
                        size: 15,
                        color: AppColors.warning,
                      ),
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
          // AnimatedList всегда в дереве — см. комментарий выше про _urgKey.
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

// ─── Два кольца: продуктивность + своевременность ────────────────────────────

/// Журнальная шапка дня: день недели капсом «глиной» + тонкая линейка-правило.
/// Экран открывается как разворот ежедневника.
class _DayMasthead extends StatelessWidget {
  const _DayMasthead({required this.date, required this.onTemplates});
  final DateTime date;
  final VoidCallback onTemplates;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    final weekday = DateFormat('EEEE', locale).format(date).toUpperCase();
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.7);
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 8, 2, 6),
      child: Row(
        children: [
          Text(
            weekday,
            style: theme.textTheme.labelMedium?.copyWith(
              color: AppColors.clay,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.4,
              fontSize: 11.5,
            ),
          ),
          const SizedBox(width: 12),
          // Линейка укорачивается (Expanded), чтобы не залезать под карточку.
          Expanded(child: Container(height: 1, color: theme.dividerColor)),
          const SizedBox(width: 12),
          // Карточка «Шаблоны дня».
          Material(
            color: theme.colorScheme.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(color: theme.dividerColor),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTemplates,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.dashboard_customize_outlined,
                        size: 16, color: muted),
                    const SizedBox(width: 6),
                    Text(
                      context.l10n.templatesLabel,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: muted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DualRingRow extends StatelessWidget {
  const _DualRingRow({
    required this.productivity,
    required this.completedTasks,
    required this.completedFraction,
    required this.totalTasks,
    required this.timeliness,
    required this.onTimeCount,
    required this.lateCount,
  });

  final double? productivity;
  final int completedTasks;

  /// Дробное выполнение (счётчики дают доли) — для подписи «3.6 / 5».
  final double completedFraction;
  final int totalTasks;
  final double? timeliness;
  final int onTimeCount;
  final int lateCount;

  /// Число без хвоста .0: 3.0 → «3», 3.6 → «3.6».
  static String _fmtNum(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Всегда два кольца фиксированного размера — без «прыжка» при появлении
    // данных о своевременности. «В срок» показывает «—», пока нет выполненных.
    Widget ringWithLabel({
      required double? value,
      required int done,
      required int total,
      required String label,
      List<Color>? ringColors,
      String? subtitle,
    }) =>
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ProductivityRing(
              value: value,
              done: done,
              total: total,
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

    // Геро-блок: два крупных кольца в «наклеенной» карточке — смысловой центр.
    return Card(
      margin: const EdgeInsets.only(bottom: 4),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            ringWithLabel(
              value: productivity,
              done: completedTasks,
              total: totalTasks,
              label: context.l10n.tasksRingLabel,
              // Дробная подпись, если есть частично выполненные счётчики.
              subtitle: '${_fmtNum(completedFraction)} / $totalTasks',
            ),
            ringWithLabel(
              value: timeliness,
              done: onTimeCount,
              total: onTimeCount + lateCount,
              label: context.l10n.onTimeRingLabel,
              ringColors: AppColors.warningGradient,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Бюджет дня по времени ───────────────────────────────────────────────────

/// Сумма оценок времени невыполненных задач дня. Оценка — необязательная
/// метрика, поэтому: задачи без неё в сумму не входят, но честно показываются
/// как «+N без оценки»; нет ни одной оценки → строки нет вовсе.
/// Предупреждение о перегрузе — контекстное: план сравнивается со временем,
/// оставшимся до 23:00 ЭТОГО дня (для будущих дней его всегда много —
/// предупреждения нет, утром запас больше, чем вечером).
class _DayBudgetRow extends StatelessWidget {
  const _DayBudgetRow({
    required this.tasks,
    required this.date,
    required this.now,
  });

  final List<Task> tasks;
  final DateTime date;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Невыполненные задачи дня → «остаток» (время + кол-во без оценки).
    // Перенесённые оригиналы «уехали» — не считаем.
    final pending =
        tasks.where((t) => !t.isCompleted && !t.isTransferred).toList();
    var sum = 0;
    var noEstimate = 0;
    for (final t in pending) {
      if (t.estimatedMinutes != null) {
        sum += t.estimatedMinutes!;
      } else {
        noEstimate++;
      }
    }

    // ── Заполнение бара: вес выполнения по задачам дня ───────────────────────
    // Задачи без оценки «бронируют» по 1/n; оценённые делят остаток (n-x)/n
    // пропорционально времени (эквивалентно «без оценки = средняя длит.»).
    // Учитываем частичное выполнение (счётчики/чек-листы) через
    // completionFraction. Заполнение = доля выполненного.
    final relevant = tasks.where((t) => !t.isTransferred).toList();
    final n = relevant.length;
    final x = relevant.where((t) => t.estimatedMinutes == null).length;
    final sumEst = relevant
        .where((t) => t.estimatedMinutes != null)
        .fold<int>(0, (a, t) => a + t.estimatedMinutes!);
    // Карточка имеет смысл только когда в дне есть оценённые задачи (бюджет
    // времени). Нет ни одной оценки → скрываем. (Раньше скрывали и когда всё
    // выполнено — теперь оставляем зелёную «готово».)
    if (sumEst == 0) return const SizedBox.shrink();

    double weightOf(Task t) {
      if (n == 0) return 0;
      if (t.estimatedMinutes == null || sumEst == 0) return 1 / n;
      return (t.estimatedMinutes! / sumEst) * ((n - x) / n);
    }

    final filled = relevant
        .fold<double>(0, (a, t) => a + weightOf(t) * t.completionFraction)
        .clamp(0.0, 1.0);

    // Сколько минут осталось до 23:00 выбранного дня. Для будущих дней —
    // много (overloaded не сработает), для прошедшего вечера — 0.
    final endOfDay = DateTime(date.year, date.month, date.day, 23);
    final minutesLeft = endOfDay.difference(now).inMinutes;
    final overloaded = sum > minutesLeft;
    final allDone = pending.isEmpty; // все задачи дня выполнены
    // После 23:05 незакрытый день требует внимания (как «срочные» задачи).
    final afterEnd = now.isAfter(endOfDay.add(const Duration(minutes: 5)));
    final isToday = dateOnly(date) == _effectiveToday(now);

    // Состояние:
    //  • не всё сделано + перегруз → красный (в любое время, даже после 23:05);
    //  • всё сделано до 23:05      → зелёный;
    //  • всё сделано после 23:05   → жёлтый (закрыто поздно);
    //  • иначе (в процессе, влезает) → без цвета.
    final Color? spine;
    final Color accent;
    final String label;
    final List<String> notes;
    Widget? trailing;

    final l10n = context.l10n;
    if (allDone) {
      // Выполнено: вовремя → зелёный, после 23:05 → жёлтый.
      final c = afterEnd ? AppColors.warning : AppColors.success;
      spine = c;
      accent = c;
      label = l10n.allDoneLabel;
      notes = afterEnd ? [l10n.dayClosedLateNote] : const [];
      trailing = Icon(Icons.check_circle, color: c, size: 20);
    } else if (overloaded) {
      // Незакрытый перегруженный день — красный в любое время.
      spine = AppColors.danger;
      accent = AppColors.danger;
      label = isToday ? l10n.remainingForLabel : l10n.planLabel;
      notes = [
        l10n.dayOverloadedNote,
        afterEnd ? l10n.dayNotClosedNote : l10n.doesNotFitBefore23Note,
        if (noEstimate > 0) l10n.noEstimateNote(noEstimate),
      ];
    } else {
      spine = null;
      accent = theme.colorScheme.primary;
      label = isToday ? l10n.remainingForLabel : l10n.planLabel;
      notes = [
        if (noEstimate > 0) l10n.noEstimateNote(noEstimate),
      ];
    }

    final textColor =
        spine ?? theme.colorScheme.onSurface.withValues(alpha: 0.6);
    final trackColor = theme.brightness == Brightness.dark
        ? AppColors.ringTrackDark
        : AppColors.ringTrack;

    // Справа — остаток времени (для «готово» — галочка вместо текста).
    trailing ??= Text(
      l10n.approxDuration(_fmtDuration(sum, context)),
      style: theme.textTheme.bodyMedium?.copyWith(
        color: textColor,
        fontWeight: FontWeight.w600,
      ),
    );

    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(color: textColor),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _GlowBar(
                  value: filled,
                  color: accent,
                  track: trackColor,
                ),
              ),
              const SizedBox(width: 10),
              trailing,
            ],
          ),
          if (notes.isNotEmpty) ...[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                notes.join(' · '),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: textColor,
                  fontWeight: spine != null ? FontWeight.w600 : null,
                ),
              ),
            ),
          ],
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Card(
        margin: EdgeInsets.zero,
        // Цветная карточка с корешком: зелёная (готово), жёлтая (после 23:05),
        // красная (перегруз) — как у задач соответствующих состояний.
        color: spine == null ? null : spine.withValues(alpha: 0.08),
        clipBehavior: spine == null ? Clip.none : Clip.antiAlias,
        child: spine == null
            ? content
            : Stack(
                children: [
                  content,
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    child: Container(width: 4, color: spine),
                  ),
                ],
              ),
      ),
    );
  }
}

/// Прогресс-бар со свечением заполненной части (как у колец). Дорожка —
/// приглушённая, заполнение — цвет состояния + мягкий цветной ореол.
class _GlowBar extends StatelessWidget {
  const _GlowBar({
    required this.value,
    required this.color,
    required this.track,
  });

  final double value; // 0..1
  final Color color;
  final Color track;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 8,
      // Анимируем заполнение: count-up при появлении (0 → value) и плавный
      // переход при изменении доли выполненного.
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: value.clamp(0.0, 1.0)),
        duration: const Duration(milliseconds: 700),
        curve: AppColors.easeOut,
        builder: (context, v, _) => LayoutBuilder(
          builder: (context, c) {
            final fillW = (c.maxWidth * v).clamp(0.0, c.maxWidth);
            return Stack(
              clipBehavior: Clip.none, // свечение не обрезаем
              children: [
                // Дорожка на всю ширину.
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: track,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
                // Заполнение слева + цветной ореол (свечение).
                if (fillW > 0)
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    width: fillW,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(6),
                        boxShadow: [
                          BoxShadow(
                            color: color.withValues(alpha: 0.6),
                            blurRadius: 6,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ─── Оценка прошедшего дня (рефлексия) ───────────────────────────────────────

class _DayRatingRow extends ConsumerWidget {
  const _DayRatingRow({required this.date});
  final DateTime date;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final rating = ref.watch(dayRatingProvider(date)).value;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            rating == null
                ? context.l10n.dayRatingQuestion
                : context.l10n.dayRatingResult(rating),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 4),
          StarRating(
            value: rating ?? 0,
            size: 26,
            onRate: (v) =>
                ref.read(ratingRepositoryProvider).setDayRating(date, v),
          ),
        ],
      ),
    );
  }
}

// ─── Карточка цитаты ─────────────────────────────────────────────────────────

class _QuoteCard extends StatelessWidget {
  const _QuoteCard({required this.text, this.author});
  final String text;
  final String? author;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Буквица «глиной» — редакторский штрих «живой бумаги». Первая буква —
    // крупный серив clay, остальной текст обтекает справа.
    final trimmed = text.trimLeft();
    final drop = trimmed.isEmpty ? '' : trimmed.substring(0, 1);
    final rest = trimmed.isEmpty ? '' : trimmed.substring(1);
    final bodyStyle = AppFonts.sourceSerif4(
      textStyle: theme.textTheme.bodyLarge,
      fontStyle: FontStyle.italic,
      height: 1.4,
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              drop,
              style: AppFonts.sourceSerif4(
                fontSize: 46,
                height: 0.92,
                fontWeight: FontWeight.w600,
                color: AppColors.clay,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(rest, style: bodyStyle),
                  if (author != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      '— $author',
                      style: AppFonts.sourceSerif4(
                        textStyle: theme.textTheme.bodySmall,
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
