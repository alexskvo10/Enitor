import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/appearance.dart';
import '../../core/utils/date_utils.dart';
import '../../data/models/backlog_item.dart';
import '../../data/models/goal.dart';
import '../../data/repositories/backlog_repository.dart';
import '../../data/repositories/goal_repository.dart';
import '../../data/repositories/task_repository.dart';
import '../../l10n/l10n_extensions.dart';
import '../../widgets/error_view.dart';
import '../../widgets/fancy_dialog.dart';

// ─── Экран «Невыполненные задачи» ────────────────────────────────────────────

class TaskBacklogScreen extends ConsumerWidget {
  const TaskBacklogScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemsAsync = ref.watch(backlogItemsProvider);
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.taskBacklogTitle)),
      body: itemsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) =>
            ErrorView(onRetry: () => ref.invalidate(backlogItemsProvider)),
        data: (items) {
          if (items.isEmpty) {
            return Center(
              child: NotebookEmptyState(
                icon: Icons.check_circle_outline,
                text: l10n.allDoneNote,
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            itemBuilder: (ctx, i) => _BacklogTaskTile(
              // Ключ по id: после переноса плитка остаётся «занятой», и без
              // ключа её состояние досталось бы следующему пункту списка.
              key: ValueKey(items[i].id),
              item: items[i],
            ),
          );
        },
      ),
    );
  }
}

class _BacklogTaskTile extends ConsumerStatefulWidget {
  const _BacklogTaskTile({super.key, required this.item});
  final BacklogItem item;

  @override
  ConsumerState<_BacklogTaskTile> createState() => _BacklogTaskTileState();
}

class _BacklogTaskTileState extends ConsumerState<_BacklogTaskTile> {
  /// Перенос идёт в два шага (создать задачу, убрать из бэклога): пока первый
  /// не закончился, второй тап не должен создать вторую задачу.
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final dateStr =
        DateFormat('d MMMM y', Localizations.localeOf(context).languageCode)
            .format(item.originalDate);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.title, style: theme.textTheme.bodyLarge),
                  const SizedBox(height: 2),
                  Text(
                    l10n.wasPlannedFor(dateStr),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color:
                          theme.colorScheme.onSurface.withValues(alpha: 0.55),
                    ),
                  ),
                  if (item.isCounter)
                    Text(
                      l10n.progressLabel(
                        '${item.progressCount}',
                        '${item.targetCount}',
                      ),
                      style: theme.textTheme.bodySmall,
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Кнопка «Выполнить» — поставить на сегодня
            TextButton(
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              ),
              onPressed: _busy ? null : _scheduleToday,
              child: Text(l10n.doItBtn),
            ),
            // Кнопка «Удалить»
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.delete_outline, color: AppColors.danger),
              onPressed: _busy ? null : _confirmDelete,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _scheduleToday() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final taskRepo = ref.read(taskRepositoryProvider);
      final backlogRepo = ref.read(backlogRepositoryProvider);
      final item = widget.item;
      // Используем календарный сегодня (не effective today):
      // в 2:10 на 6-е задача должна уйти на 6-е, а не на 5-е.
      final day = dateOnly(DateTime.now());
      // Цель — только если она ещё идёт в этот день: иначе вклад задачи
      // ушёл бы в закончившийся период.
      final goalId = item.goalId != null &&
              ref
                  .read(goalRepositoryProvider)
                  .counterGoalsForDate(day)
                  .any((g) => g.id == item.goalId)
          ? item.goalId
          : null;
      await taskRepo.createAndAdd(
        id: item.id,
        title: item.title,
        description: item.description,
        date: day,
        startMinutes: item.startMinutes,
        endMinutes: item.endMinutes,
        estimatedMinutes: item.estimatedMinutes,
        targetCount: item.targetCount,
        subtaskTitles: item.subtaskTitles,
        priority: item.priority,
        tags: item.tags,
        goalId: goalId,
        progressCount: item.progressCount,
      );
      await backlogRepo.remove(item.id);
    } catch (_) {
      // Не вышло — кнопки снова нужны. После успеха флаг не снимаем: плитка
      // сейчас уйдёт из списка, а до перерисовки тап по ней не должен работать.
      if (mounted) setState(() => _busy = false);
      rethrow;
    }
  }

  Future<void> _confirmDelete() async {
    final confirmed = await _confirmBacklogDelete(
      context,
      context.l10n.deleteBacklogTaskTitle,
    );
    if (confirmed && context.mounted) {
      await ref.read(backlogRepositoryProvider).remove(widget.item.id);
    }
  }
}

// ─── Экран «Недостигнутые цели» ──────────────────────────────────────────────

class GoalBacklogScreen extends ConsumerWidget {
  const GoalBacklogScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemsAsync = ref.watch(goalBacklogItemsProvider);
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.goalBacklogTitle)),
      body: itemsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) =>
            ErrorView(onRetry: () => ref.invalidate(goalBacklogItemsProvider)),
        data: (items) {
          if (items.isEmpty) {
            return Center(
              child: NotebookEmptyState(
                icon: Icons.emoji_events_outlined,
                text: l10n.allGoalsAchievedNote,
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            itemBuilder: (ctx, i) => _BacklogGoalTile(
              key: ValueKey(items[i].id),
              item: items[i],
            ),
          );
        },
      ),
    );
  }
}

class _BacklogGoalTile extends ConsumerStatefulWidget {
  const _BacklogGoalTile({super.key, required this.item});
  final GoalBacklogItem item;

  @override
  ConsumerState<_BacklogGoalTile> createState() => _BacklogGoalTileState();
}

class _BacklogGoalTileState extends ConsumerState<_BacklogGoalTile> {
  /// Так же, как у задач: повторный тап, пока цель переносится, ничего не делает.
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final periodLabel = item.originalRef
        .labelFor(Localizations.localeOf(context).languageCode == 'ru');

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.title, style: theme.textTheme.bodyLarge),
                  const SizedBox(height: 2),
                  Text(
                    l10n.fromPeriodLabel(periodLabel),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color:
                          theme.colorScheme.onSurface.withValues(alpha: 0.55),
                    ),
                  ),
                  if (item.isCounter)
                    Text(
                      item.unit == GoalUnit.minutes
                          ? l10n.progressLabel(
                              fmtDuration(item.progressCount, context),
                              fmtDuration(item.targetCount!, context),
                            )
                          : l10n.progressLabel(
                              '${item.progressCount}',
                              '${item.targetCount}',
                            ),
                      style: theme.textTheme.bodySmall,
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Кнопка «Достигнуть» — добавить в текущий период
            TextButton(
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              ),
              onPressed: _busy ? null : _achieveNow,
              child: Text(l10n.achieveNowBtn),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.delete_outline, color: AppColors.danger),
              onPressed: _busy ? null : _confirmDelete,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _achieveNow() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final goalRepo = ref.read(goalRepositoryProvider);
      final backlogRepo = ref.read(goalBacklogRepositoryProvider);
      final item = widget.item;
      final now = DateTime.now();
      final currentRef = GoalPeriodRef.current(item.period, now);
      await goalRepo.addGoal(
        title: item.title,
        description: item.description,
        period: currentRef.period,
        year: currentRef.year,
        month: currentRef.month,
        season: currentRef.season,
        weekStart: currentRef.weekStart,
        targetCount: item.targetCount,
        subtaskTitles: item.subtaskTitles,
        unit: item.unit,
        priority: item.priority,
        tags: item.tags,
        manualProgress: item.progressCount,
      );
      await backlogRepo.remove(item.id);
    } catch (_) {
      // Не вышло — кнопки снова нужны. После успеха флаг не снимаем: плитка
      // сейчас уйдёт из списка, а до перерисовки тап по ней не должен работать.
      if (mounted) setState(() => _busy = false);
      rethrow;
    }
  }

  Future<void> _confirmDelete() async {
    final confirmed = await _confirmBacklogDelete(
      context,
      context.l10n.deleteBacklogGoalTitle,
    );
    if (confirmed && context.mounted) {
      await ref.read(goalBacklogRepositoryProvider).remove(widget.item.id);
    }
  }
}

/// Диалог подтверждения удаления пункта бэклога. true — пользователь подтвердил.
Future<bool> _confirmBacklogDelete(BuildContext context, String title) async {
  final l10n = context.l10n;
  final confirmed = await showFancyDialog<bool>(
    context: context,
    icon: Icons.delete_outline,
    iconColor: AppColors.danger,
    title: title,
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
  return confirmed == true;
}
