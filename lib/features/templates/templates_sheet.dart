import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../data/models/day_template.dart';
import '../../data/models/task.dart';
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

class _TemplatesSheet extends ConsumerWidget {
  const _TemplatesSheet({
    required this.date,
    required this.isPast,
    required this.dayTasks,
  });

  final DateTime date;
  final bool isPast;
  final List<Task> dayTasks;

  /// Пункты для нового шаблона из текущего дня (без перенесённых оригиналов).
  List<TemplateItem> get _capturable => dayTasks
      .where((t) => !t.isTransferred)
      .map(TemplateItem.fromTask)
      .toList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final templates = ref.watch(templatesProvider).value ?? const [];
    final canSave = _capturable.isNotEmpty;

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
              Icon(Icons.dashboard_customize_outlined,
                  color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(l10n.templatesSheetTitle, style: theme.textTheme.titleMedium),
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
                label: Text(l10n.saveDayAsTemplate(_capturable.length)),
              ),
            ),
          const SizedBox(height: 12),
          Text(l10n.applyLabel,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              )),
          const SizedBox(height: 4),
          if (templates.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text(
                  l10n.noTemplatesYet,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ),
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
                      subtitle: Text(l10n.tasksCountShort(t.items.length)),
                      onTap: isPast ? null : () => _apply(context, ref, t),
                      trailing: PopupMenuButton<String>(
                        onSelected: (a) {
                          if (a == 'rename') {
                            _rename(context, ref, t);
                          } else if (a == 'delete') {
                            ref.read(templateRepositoryProvider).remove(t.id);
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
                              leading: const Icon(Icons.delete_outline,
                                  color: AppColors.danger),
                              title: Text(l10n.deleteMenuItem,
                                  style: const TextStyle(color: AppColors.danger)),
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
          if (isPast && templates.isNotEmpty)
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
    final repo = ref.read(templateRepositoryProvider);
    final items = _capturable;
    final name = await _promptName(context, title: l10n.templateNameTitle);
    if (name == null || name.isEmpty) return;
    await repo.add(name, items);
    if (context.mounted) {
      showFancyToast(context, message: l10n.templateSavedToast(name));
    }
  }

  Future<void> _apply(
      BuildContext context, WidgetRef ref, DayTemplate t) async {
    final l10n = context.l10n;
    await ref.read(taskRepositoryProvider).applyTemplate(t.items, date);
    if (context.mounted) {
      Navigator.of(context).pop();
      showFancyToast(context,
          message: l10n.addedFromTemplateToast(t.name, t.items.length));
    }
  }

  Future<void> _rename(
      BuildContext context, WidgetRef ref, DayTemplate t) async {
    final name = await _promptName(context,
        title: context.l10n.renameTitle, initial: t.name);
    if (name == null || name.isEmpty) return;
    await ref.read(templateRepositoryProvider).rename(t.id, name);
  }

  Future<String?> _promptName(BuildContext context,
      {required String title, String? initial}) {
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
