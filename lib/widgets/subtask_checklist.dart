import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../data/models/task.dart' show SubTask;
import '../l10n/l10n_extensions.dart';

/// Сворачиваемый список подзадач (чек-лист) под плиткой задачи/цели.
/// Заголовок «Подзадачи · N/M» сворачивает/разворачивает список.
class SubtaskChecklist extends StatefulWidget {
  const SubtaskChecklist({
    super.key,
    required this.subtasks,
    required this.readOnly,
    required this.onToggle,
  });

  final List<SubTask> subtasks;
  final bool readOnly;
  final Future<void> Function(SubTask) onToggle;

  @override
  State<SubtaskChecklist> createState() => _SubtaskChecklistState();
}

class _SubtaskChecklistState extends State<SubtaskChecklist> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final done = widget.subtasks.where((s) => s.done).length;
    final total = widget.subtasks.length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Заголовок-переключатель.
          InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
              child: Row(
                children: [
                  AnimatedRotation(
                    turns: _expanded ? 0.25 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.chevron_right,
                      size: 18,
                      color:
                          theme.colorScheme.onSurface.withValues(alpha: 0.55),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    context.l10n.subtasksHeader(done, total),
                    style: theme.textTheme.labelMedium?.copyWith(
                      color:
                          theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Список пунктов (сворачивается).
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child: _expanded
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final s in widget.subtasks)
                        InkWell(
                          borderRadius: BorderRadius.circular(6),
                          onTap: widget.readOnly
                              ? null
                              : () => widget.onToggle(s),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 1),
                            child: Row(
                              children: [
                                if (widget.readOnly)
                                  Icon(
                                    s.done
                                        ? Icons.check_box
                                        : Icons.check_box_outline_blank,
                                    size: 20,
                                    color: s.done
                                        ? AppColors.success
                                        : theme.colorScheme.onSurface
                                            .withValues(alpha: 0.4),
                                  )
                                else
                                  SizedBox(
                                    width: 32,
                                    height: 32,
                                    child: Checkbox(
                                      value: s.done,
                                      visualDensity: VisualDensity.compact,
                                      onChanged: (_) => widget.onToggle(s),
                                    ),
                                  ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    s.title,
                                    style: s.done
                                        ? TextStyle(
                                            decoration:
                                                TextDecoration.lineThrough,
                                            color: theme.colorScheme.onSurface
                                                .withValues(alpha: 0.5),
                                          )
                                        : theme.textTheme.bodyMedium,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}
