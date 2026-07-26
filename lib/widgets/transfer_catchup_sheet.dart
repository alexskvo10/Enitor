import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../data/models/goal.dart';
import '../data/models/task.dart';
import '../l10n/l10n_extensions.dart';
import 'fancy_dialog.dart';

/// Результат догоняющего диалога: какие задачи/цели пользователь оставил
/// отмеченными (= перенести). Всё, что было в исходных кандидатах, но не
/// попало сюда — пользователь явно отказался от переноса (снял галочку или
/// нажал «Не переносить»).
typedef TransferCatchupSelection = ({Set<String> taskIds, Set<String> goalIds});

/// Догоняющий диалог: показывается, когда пользователь не заходил в
/// приложение в момент, когда перенос должен был случиться (пропустил
/// границу 4:00). По визуальному языку — как диалог оценки качества/
/// фактического времени (fancy_dialog.dart: FancyDialogCard, медальон-
/// иконка, пружинное появление), но со списком с чекбоксами внутри.
///
/// Возвращает `null`, если диалог закрыли без явного решения (Esc/тап по
/// затемнению) — тогда решение не принято, кандидаты останутся кандидатами
/// и предложатся снова в следующий раз.
Future<TransferCatchupSelection?> showTransferCatchupSheet(
  BuildContext context, {
  required List<Task> tasks,
  required List<Goal> goals,
}) {
  return showFancyRawDialog<TransferCatchupSelection>(
    context: context,
    barrierLabel: 'transfer-catchup',
    builder: (ctx) => _TransferCatchupDialog(tasks: tasks, goals: goals),
  );
}

class _TransferCatchupDialog extends StatefulWidget {
  const _TransferCatchupDialog({required this.tasks, required this.goals});

  final List<Task> tasks;
  final List<Goal> goals;

  @override
  State<_TransferCatchupDialog> createState() =>
      _TransferCatchupDialogState();
}

class _TransferCatchupDialogState extends State<_TransferCatchupDialog> {
  late final Set<String> _checkedTaskIds =
      widget.tasks.map((t) => t.id).toSet();
  late final Set<String> _checkedGoalIds =
      widget.goals.map((g) => g.id).toSet();

  int get _checkedCount => _checkedTaskIds.length + _checkedGoalIds.length;

  void _selectAll() => setState(() {
        _checkedTaskIds
          ..clear()
          ..addAll(widget.tasks.map((t) => t.id));
        _checkedGoalIds
          ..clear()
          ..addAll(widget.goals.map((g) => g.id));
      });

  void _deselectAll() => setState(() {
        _checkedTaskIds.clear();
        _checkedGoalIds.clear();
      });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;

    return FancyDialogCard(
      icon: Icons.update,
      iconColor: AppColors.primary,
      title: l10n.transferCatchupTitle,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 10),
          Text(
            l10n.transferCatchupSubtitle,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: Wrap(
              spacing: 2,
              children: [
                TextButton(
                  onPressed: _selectAll,
                  child: Text(l10n.selectAllBtn),
                ),
                TextButton(
                  onPressed: _deselectAll,
                  child: Text(l10n.deselectAllBtn),
                ),
              ],
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 260),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (widget.tasks.isNotEmpty) ...[
                    _groupLabel(theme, l10n.navToday),
                    for (final t in widget.tasks)
                      _CandidateRow(
                        title: t.title,
                        checked: _checkedTaskIds.contains(t.id),
                        onChanged: (v) => setState(() {
                          if (v) {
                            _checkedTaskIds.add(t.id);
                          } else {
                            _checkedTaskIds.remove(t.id);
                          }
                        }),
                      ),
                  ],
                  if (widget.goals.isNotEmpty) ...[
                    _groupLabel(theme, l10n.navGoals),
                    for (final g in widget.goals)
                      _CandidateRow(
                        title: g.title,
                        checked: _checkedGoalIds.contains(g.id),
                        onChanged: (v) => setState(() {
                          if (v) {
                            _checkedGoalIds.add(g.id);
                          } else {
                            _checkedGoalIds.remove(g.id);
                          }
                        }),
                      ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              // «Не переносить» — серая кнопка: явный отказ от ВСЕХ
              // кандидатов (как «Нет» у баннера, но разом), в отличие от
              // Esc/тапа по затемнению, который просто откладывает решение.
              TextButton(
                style: TextButton.styleFrom(
                  backgroundColor:
                      theme.colorScheme.surfaceContainerHighest,
                  foregroundColor: theme.colorScheme.onSurface,
                ),
                onPressed: () => Navigator.pop(
                  context,
                  (taskIds: <String>{}, goalIds: <String>{}),
                ),
                child: Text(l10n.transferCatchupDeclineAll),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () => Navigator.pop(context, (
                  taskIds: _checkedTaskIds,
                  goalIds: _checkedGoalIds,
                )),
                child: Text(l10n.transferCatchupConfirm(_checkedCount)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _groupLabel(ThemeData theme, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 2),
        child: Text(
          text,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
}

class _CandidateRow extends StatelessWidget {
  const _CandidateRow({
    required this.title,
    required this.checked,
    required this.onChanged,
  });

  final String title;
  final bool checked;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!checked),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            SizedBox(
              width: 32,
              height: 32,
              child: Checkbox(
                value: checked,
                visualDensity: VisualDensity.compact,
                onChanged: (v) => onChanged(v ?? false),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(title, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
    );
  }
}
