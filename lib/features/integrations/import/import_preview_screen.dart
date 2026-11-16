import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/appearance.dart';
import '../../../l10n/app_localizations.dart';
import '../../../l10n/l10n_extensions.dart';
import '../../../widgets/fancy_toast.dart';
import '../core/integration_command.dart';
import '../ui/section_parts.dart';
import 'import_plan.dart';

/// Предпросмотр импорта — общий для календарей и задач из других
/// приложений: что будет создано, обновлено, пропущено и почему. Ничего не
/// пишется, пока не нажата «Импортировать N». Возвращает число записанного.
class ImportPreviewScreen extends StatefulWidget {
  const ImportPreviewScreen({
    super.key,
    required this.title,
    required this.entries,
    this.warningsCount = 0,
  });

  final String title;
  final List<PlanEntry> entries;

  /// Строки файла, которые не удалось прочитать совсем.
  final int warningsCount;

  @override
  State<ImportPreviewScreen> createState() => _ImportPreviewScreenState();
}

class _ImportPreviewScreenState extends State<ImportPreviewScreen> {
  late final Set<int> _selected = {
    for (var i = 0; i < widget.entries.length; i++)
      if (widget.entries[i].action != PlanAction.skip) i,
  };
  bool _busy = false;

  Future<void> _import() async {
    final l10n = context.l10n;
    setState(() => _busy = true);
    var done = 0;
    try {
      for (final i in _selected.toList()..sort()) {
        await widget.entries[i].apply?.call();
        done++;
      }
    } catch (e) {
      // Записанное остаётся (повтор обновит те же записи, а не задвоит):
      // экран не висит, человек видит причину и может повторить.
      if (!mounted) return;
      setState(() => _busy = false);
      showFancyToast(
        context,
        message: l10n.importFailedToast('$e'),
        tone: ToastTone.error,
      );
      return;
    }
    if (!mounted) return;
    showFancyToast(context, message: l10n.importDoneToast(done));
    Navigator.of(context).pop(done);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final entries = widget.entries;
    final count = _selected.length;
    final importable = [
      for (var i = 0; i < entries.length; i++)
        if (entries[i].action != PlanAction.skip) i,
    ];
    final skipped = [
      for (final e in entries)
        if (e.action == PlanAction.skip) e,
    ];
    final updates = entries.where((e) => e.action == PlanAction.update).length;
    final allOn = count == importable.length;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: entries.isEmpty
          ? Center(
              child: NotebookEmptyState(
                text: widget.warningsCount > 0
                    ? l10n.importNothingReadable
                    : l10n.importEmpty,
                icon: Icons.event_busy_outlined,
              ),
            )
          : ListView(
              padding: const EdgeInsets.only(top: 4, bottom: 24),
              children: [
                // Сводка плашками: сколько нового, что обновится, что нет.
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (importable.length > updates)
                        _CountChip(
                          icon: Icons.add_rounded,
                          color: Theme.of(context).colorScheme.primary,
                          text: l10n.importCountNew(
                            importable.length - updates,
                          ),
                        ),
                      if (updates > 0)
                        _CountChip(
                          icon: Icons.sync_rounded,
                          color: AppColors.clay,
                          text: l10n.importCountUpdate(updates),
                        ),
                      if (skipped.isNotEmpty)
                        _CountChip(
                          icon: Icons.remove_rounded,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.55),
                          text: l10n.importCountSkip(skipped.length),
                        ),
                    ],
                  ),
                ),
                if (importable.isNotEmpty) ...[
                  Row(
                    children: [
                      Expanded(child: SectionTitle(l10n.importSectionWill)),
                      Padding(
                        padding: const EdgeInsets.only(right: 12, top: 8),
                        child: TextButton(
                          onPressed: _busy
                              ? null
                              : () => setState(
                                    () => allOn
                                        ? _selected.clear()
                                        : _selected.addAll(importable),
                                  ),
                          child: Text(
                            allOn
                                ? l10n.importSelectNone
                                : l10n.importSelectAll,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SectionCard(
                    children: [
                      for (final i in importable) ...[
                        if (i != importable.first) tileDivider,
                        _EntryTile(
                          entry: entries[i],
                          selected: _selected.contains(i),
                          onChanged: _busy
                              ? null
                              : (v) => setState(
                                    () => v
                                        ? _selected.add(i)
                                        : _selected.remove(i),
                                  ),
                        ),
                      ],
                    ],
                  ),
                ],
                if (skipped.isNotEmpty) ...[
                  SectionTitle(l10n.importSectionSkipped),
                  SectionCard(
                    children: [
                      for (final e in skipped) ...[
                        if (e != skipped.first) tileDivider,
                        _SkippedTile(entry: e),
                      ],
                    ],
                  ),
                  SectionNote(l10n.importSkippedNote),
                ],
              ],
            ),
      bottomNavigationBar: entries.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton.icon(
                  onPressed: count == 0 || _busy ? null : _import,
                  icon: _busy
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.download_done_rounded),
                  label: Text(l10n.importButton(count)),
                ),
              ),
            ),
    );
  }
}

/// Плашка сводки: цветной значок и «Новых: 5».
class _CountChip extends StatelessWidget {
  const _CountChip({
    required this.icon,
    required this.color,
    required this.text,
  });

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(8, 5, 12, 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                text,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
          ],
        ),
      );
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({
    required this.entry,
    required this.selected,
    required this.onChanged,
  });

  final PlanEntry entry;
  final bool selected;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.7);
    final small = theme.textTheme.bodySmall?.copyWith(color: muted);
    final when = _when(context, entry);
    // Что не перенесётся у импортируемого (например, часть повтора).
    final note = entry.skip == null ? null : planSkipText(entry.skip!, l10n);
    return CheckboxListTile(
      value: selected,
      onChanged: onChanged == null ? null : (v) => onChanged!(v ?? false),
      controlAffinity: ListTileControlAffinity.leading,
      title: Text(
        entry.title,
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Wrap(
          spacing: 10,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (when.isNotEmpty) Text(when, style: small),
            if (entry.repeats)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.repeat_rounded, size: 14, color: muted),
                  const SizedBox(width: 3),
                  Flexible(child: Text(l10n.importRepeats, style: small)),
                ],
              ),
            if (entry.action == PlanAction.update)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.clay.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  l10n.importStatusUpdate,
                  style: small?.copyWith(
                    color: AppColors.clay,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            if (note != null) Text(note, style: small),
          ],
        ),
      ),
    );
  }
}

/// Пропущенное — без флажка, приглушённо, с причиной.
class _SkippedTile extends StatelessWidget {
  const _SkippedTile({required this.entry});

  final PlanEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.6);
    final when = _when(context, entry);
    final reason =
        entry.skip == null ? '' : planSkipText(entry.skip!, context.l10n);
    return ListTile(
      leading: Icon(Icons.do_not_disturb_on_outlined, color: muted),
      title: Text(
        entry.title,
        style: theme.textTheme.titleSmall?.copyWith(color: muted),
      ),
      subtitle: Text(
        [when, reason].where((s) => s.isNotEmpty).join(' · '),
        style: theme.textTheme.bodySmall?.copyWith(color: muted),
      ),
    );
  }
}

String _when(BuildContext context, PlanEntry e) {
  final date = e.date;
  if (date == null) return '';
  final locale = Localizations.localeOf(context).languageCode;
  final d = DateFormat('d MMM', locale).format(date);
  final start = e.startMinutes;
  if (start == null) return d;
  final end = e.endMinutes;
  return '$d, ${formatHm(start)}${end == null ? '' : '–${formatHm(end)}'}';
}

String planSkipText(PlanSkip s, AppLocalizations l10n) => switch (s) {
      PlanSkip.allDay => l10n.importSkipAllDay,
      PlanSkip.unsupportedRepeat => l10n.importSkipRepeat,
      PlanSkip.unchanged => l10n.importSkipUnchanged,
      PlanSkip.alreadyImported => l10n.importSkipAlready,
      PlanSkip.past => l10n.importSkipPast,
      PlanSkip.noTitle => l10n.importSkipNoTitle,
      PlanSkip.completedWithoutDate => l10n.importSkipDoneNoDate,
      PlanSkip.brokenRow => l10n.importSkipBroken,
    };
