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
            itemBuilder: (ctx, i) => _BacklogTaskTile(item: items[i]),
          );
        },
      ),
    );
  }
}

class _BacklogTaskTile extends ConsumerWidget {
  const _BacklogTaskTile({required this.item});
  final BacklogItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                      l10n.progressLabel(item.progressCount, item.targetCount!),
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
              onPressed: () => _scheduleToday(ref),
              child: Text(l10n.doItBtn),
            ),
            // Кнопка «Удалить»
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.delete_outline, color: AppColors.danger),
              onPressed: () =>
                  ref.read(backlogRepositoryProvider).remove(item.id),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _scheduleToday(WidgetRef ref) async {
    final taskRepo = ref.read(taskRepositoryProvider);
    final backlogRepo = ref.read(backlogRepositoryProvider);
    // Используем календарный сегодня (не effective today):
    // в 2:10 на 6-е задача должна уйти на 6-е, а не на 5-е.
    await taskRepo.createAndAdd(
      title: item.title,
      description: item.description,
      date: dateOnly(DateTime.now()),
      startMinutes: item.startMinutes,
      endMinutes: item.endMinutes,
      estimatedMinutes: item.estimatedMinutes,
      targetCount: item.targetCount,
      subtaskTitles: item.subtaskTitles,
      priority: item.priority,
      tags: item.tags,
    );
    await backlogRepo.remove(item.id);
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
            itemBuilder: (ctx, i) => _BacklogGoalTile(item: items[i]),
          );
        },
      ),
    );
  }
}

class _BacklogGoalTile extends ConsumerWidget {
  const _BacklogGoalTile({required this.item});
  final GoalBacklogItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                      l10n.progressLabel(item.progressCount, item.targetCount!),
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
              onPressed: () => _achieveNow(ref),
              child: Text(l10n.achieveNowBtn),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.delete_outline, color: AppColors.danger),
              onPressed: () =>
                  ref.read(goalBacklogRepositoryProvider).remove(item.id),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _achieveNow(WidgetRef ref) async {
    final goalRepo = ref.read(goalRepositoryProvider);
    final backlogRepo = ref.read(goalBacklogRepositoryProvider);
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
    );
    await backlogRepo.remove(item.id);
  }
}
