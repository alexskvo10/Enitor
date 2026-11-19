import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/appearance.dart';
import '../../data/models/day_template.dart';
import '../../data/models/schedule_item.dart';
import '../../data/models/schedule_template.dart';
import '../../data/models/task.dart';
import '../../data/repositories/schedule_repository.dart';
import '../../data/repositories/schedule_template_repository.dart';
import '../../data/repositories/task_repository.dart';
import '../../data/repositories/template_repository.dart';
import '../../l10n/l10n_extensions.dart';
import '../../widgets/esc_dismissible.dart';
import '../../widgets/fancy_dialog.dart';
import '../../widgets/fancy_toast.dart';

/// Шит «Шаблоны дня»: сохранить текущий день как шаблон + применить шаблон.
Future<void> showTemplatesSheet(
  BuildContext context, {
  required DateTime date,
  required bool isPast,
  required List<Task> dayTasks,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => EscDismissible(
      autofocus: true,
      child: _TemplatesSheet(date: date, isPast: isPast, dayTasks: dayTasks),
    ),
  );
}

/// Тот же шит для вкладки «Расписание»: шаблон — набор пунктов дня.
Future<void> showScheduleTemplatesSheet(
  BuildContext context, {
  required DateTime date,
  required bool isPast,
  required List<ScheduleItem> dayItems,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => EscDismissible(
      autofocus: true,
      child: _TemplatesSheet(date: date, isPast: isPast, dayItems: dayItems),
    ),
  );
}

/// Шаблон в списке шита, общий вид для задач и расписания.
typedef _Entry = ({String id, String name, int count});

class _TemplatesSheet extends ConsumerStatefulWidget {
  const _TemplatesSheet({
    required this.date,
    required this.isPast,
    this.dayTasks,
    this.dayItems,
  });

  final DateTime date;
  final bool isPast;

  /// Ровно одно из двух: задачи дня или пункты расписания дня.
  final List<Task>? dayTasks;
  final List<ScheduleItem>? dayItems;

  bool get schedule => dayItems != null;

  @override
  ConsumerState<_TemplatesSheet> createState() => _TemplatesSheetState();
}

class _TemplatesSheetState extends ConsumerState<_TemplatesSheet> {
  /// Шаблон сейчас применяется: повторный тап до конца первого не создаёт
  /// задачи второй раз.
  bool _applying = false;

  /// Пункты для нового шаблона из текущего дня (без перенесённых оригиналов).
  List<TemplateItem> get _capturable => (widget.dayTasks ?? const [])
      .where((t) => !t.isTransferred)
      .map(TemplateItem.fromTask)
      .toList();

  List<ScheduleTemplateItem> get _capturableItems =>
      (widget.dayItems ?? const []).map(ScheduleTemplateItem.fromItem).toList();

  int get _captureCount =>
      widget.schedule ? _capturableItems.length : _capturable.length;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final List<_Entry> templates = widget.schedule
        ? [
            for (final t in ref.watch(scheduleTemplatesProvider).value ??
                const <ScheduleTemplate>[])
              (id: t.id, name: t.name, count: t.items.length),
          ]
        : [
            for (final t
                in ref.watch(templatesProvider).value ?? const <DayTemplate>[])
              (id: t.id, name: t.name, count: t.items.length),
          ];
    final canSave = _captureCount > 0;

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.dashboard_customize_outlined,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                l10n.templatesSheetTitle,
                style: theme.textTheme.titleMedium,
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Сохранить текущий день.
          if (canSave)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _saveCurrentDay(context, ref),
                icon: const Icon(Icons.add, size: 18),
                label: Text(l10n.saveDayAsTemplate(_captureCount)),
              ),
            ),
          const SizedBox(height: 12),
          Text(
            l10n.applyLabel,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 4),
          if (templates.isEmpty)
            NotebookEmptyState(
              icon: Icons.bookmark_border,
              text: l10n.noTemplatesYet,
            )
          else
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: templates.length,
                itemBuilder: (ctx, i) {
                  final t = templates[i];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      title: Text(t.name),
                      subtitle: Text(
                        widget.schedule
                            ? l10n.scheduleItemsCount(t.count)
                            : l10n.tasksCountShort(t.count),
                      ),
                      onTap:
                          widget.isPast ? null : () => _apply(context, ref, t),
                      trailing: PopupMenuButton<String>(
                        onSelected: (a) {
                          if (a == 'rename') {
                            _rename(context, ref, t);
                          } else if (a == 'delete') {
                            _confirmDelete(context, ref, t);
                          }
                        },
                        itemBuilder: (_) => [
                          PopupMenuItem(
                            value: 'rename',
                            child: ListTile(
                              leading: const Icon(Icons.edit_outlined),
                              title: Text(l10n.renameMenuItem),
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                          PopupMenuItem(
                            value: 'delete',
                            child: ListTile(
                              leading: const Icon(
                                Icons.delete_outline,
                                color: AppColors.danger,
                              ),
                              title: Text(
                                l10n.deleteMenuItem,
                                style: const TextStyle(
                                  color: AppColors.danger,
                                ),
                              ),
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          if (widget.isPast && templates.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                l10n.pastDayNoApplyNote,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _saveCurrentDay(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    // Снимок дня — до диалога: пока вводится название, день не меняется.
    final items = _capturable;
    final scheduleItems = _capturableItems;
    final name = await _promptName(context, title: l10n.templateNameTitle);
    if (name == null || name.isEmpty) return;
    if (widget.schedule) {
      await ref
          .read(scheduleTemplateRepositoryProvider)
          .add(name, scheduleItems);
    } else {
      await ref.read(templateRepositoryProvider).add(name, items);
    }
    if (context.mounted) {
      showFancyToast(context, message: l10n.templateSavedToast(name));
    }
  }

  Future<void> _apply(
    BuildContext context,
    WidgetRef ref,
    _Entry t,
  ) async {
    if (_applying) return;
    _applying = true;
    try {
      final l10n = context.l10n;
      var added = 0;
      if (widget.schedule) {
        final tpl = ref
            .read(scheduleTemplatesProvider)
            .value
            ?.where((x) => x.id == t.id)
            .firstOrNull;
        if (tpl != null) {
          added = await ref
              .read(scheduleRepositoryProvider)
              .applyTemplate(tpl.items, widget.date);
        }
      } else {
        final tpl = ref
            .read(templatesProvider)
            .value
            ?.where((x) => x.id == t.id)
            .firstOrNull;
        if (tpl != null) {
          await ref
              .read(taskRepositoryProvider)
              .applyTemplate(tpl.items, widget.date);
          added = tpl.items.length;
        }
      }
      if (context.mounted) {
        Navigator.of(context).pop();
        showFancyToast(
          context,
          message: l10n.addedFromTemplateToast(t.name, added),
        );
      }
    } catch (_) {
      // После успеха флаг не снимаем: шит закрывается, и тап во время
      // анимации закрытия не должен применить шаблон ещё раз.
      _applying = false;
      rethrow;
    }
  }

  Future<void> _rename(
    BuildContext context,
    WidgetRef ref,
    _Entry t,
  ) async {
    final name = await _promptName(
      context,
      title: context.l10n.renameTitle,
      initial: t.name,
    );
    if (name == null || name.isEmpty) return;
    if (widget.schedule) {
      await ref.read(scheduleTemplateRepositoryProvider).rename(t.id, name);
    } else {
      await ref.read(templateRepositoryProvider).rename(t.id, name);
    }
  }

  /// Диалог подтверждения удаления шаблона: удаляем только после «Удалить».
  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    _Entry t,
  ) async {
    final l10n = context.l10n;
    final confirmed = await showFancyDialog<bool>(
      context: context,
      icon: Icons.delete_outline,
      iconColor: AppColors.danger,
      title: l10n.deleteTemplateTitle(t.name),
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
    if (confirmed == true && context.mounted) {
      if (widget.schedule) {
        await ref.read(scheduleTemplateRepositoryProvider).remove(t.id);
      } else {
        await ref.read(templateRepositoryProvider).remove(t.id);
      }
    }
  }

  Future<String?> _promptName(
    BuildContext context, {
    required String title,
    String? initial,
  }) {
    final l10n = context.l10n;
    final ctrl = TextEditingController(text: initial ?? '');
    return showFancyDialog<String>(
      context: context,
      icon: Icons.bookmark_added_rounded,
      iconColor: AppColors.primary,
      title: title,
      autofocusEsc: false,
      contentBuilder: (ctx) => TextField(
        controller: ctrl,
        autofocus: true,
        textAlign: TextAlign.center,
        decoration: InputDecoration(
          hintText: l10n.templateNameHint,
          border: const OutlineInputBorder(),
        ),
        onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
      ),
      actions: (ctx) => [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(l10n.cancel),
        ),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
          child: Text(l10n.ok),
        ),
      ],
    );
  }
}
