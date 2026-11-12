import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/appearance.dart';
import '../../../l10n/app_localizations.dart';
import '../../../l10n/l10n_extensions.dart';
import '../../../widgets/fancy_toast.dart';
import '../core/integration_command.dart';
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
    final skipped = entries.where((e) => e.action == PlanAction.skip).length;
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
              padding: const EdgeInsets.only(bottom: 96),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                  child: Text(
                    l10n.importSummary(
                      entries.length - skipped,
                      skipped,
                    ),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                for (var i = 0; i < entries.length; i++)
                  _EntryTile(
                    entry: entries[i],
                    selected: _selected.contains(i),
                    onChanged: entries[i].action == PlanAction.skip || _busy
                        ? null
                        : (v) => setState(
                              () => v ? _selected.add(i) : _selected.remove(i),
                            ),
                  ),
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
    final skipped = entry.action == PlanAction.skip;
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.7);
    final lines = [
      _when(context, entry),
      switch (entry.action) {
        PlanAction.create => l10n.importStatusNew,
        PlanAction.update => l10n.importStatusUpdate,
        PlanAction.skip => l10n.importStatusSkip,
      },
      if (entry.skip != null) planSkipText(entry.skip!, l10n),
    ].where((s) => s.isNotEmpty).join(' · ');
    return CheckboxListTile(
      value: skipped ? false : selected,
      onChanged: onChanged == null ? null : (v) => onChanged!(v ?? false),
      controlAffinity: ListTileControlAffinity.leading,
      secondary: entry.repeats
          ? Icon(Icons.repeat_rounded, size: 20, color: muted)
          : null,
      title: Text(
        entry.title,
        style: skipped ? TextStyle(color: muted) : null,
      ),
      subtitle: Text(lines, style: TextStyle(color: muted)),
    );
  }

  static String _when(BuildContext context, PlanEntry e) {
    final date = e.date;
    if (date == null) return '';
    final locale = Localizations.localeOf(context).languageCode;
    final d = DateFormat('d MMM', locale).format(date);
    final start = e.startMinutes;
    if (start == null) return d;
    final end = e.endMinutes;
    return '$d, ${formatHm(start)}${end == null ? '' : '–${formatHm(end)}'}';
  }
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
