part of 'today_screen.dart';

// ─── Вкладка «Расписание» ────────────────────────────────────────────────────
//
// Живёт частью экрана задач: делит с ним календарь и выбранный день и берёт
// готовые выборщики времени, сроки повторения и диалоги выбора.

/// Цвета пунктов; в пункте хранится индекс, null — без цвета.
const _scheduleColors = <Color>[
  AppColors.primary,
  AppColors.clay,
  AppColors.success,
  AppColors.warning,
  AppColors.danger,
  Color(0xFF8E6BBF),
  Color(0xFF3AA6B9),
];

Color? _scheduleColor(ScheduleItem i) {
  final c = i.colorIndex;
  return c == null || c < 0 || c >= _scheduleColors.length
      ? null
      : _scheduleColors[c];
}

/// «10:00–11:30» или просто «10:00», если конца нет.
String _scheduleTimeLabel(ScheduleItem i) => i.endMinutes == null
    ? _fmtTime(i.startMinutes)
    : '${_fmtTime(i.startMinutes)}–${_fmtTime(i.endMinutes!)}';

/// Лента пунктов на выбранный день или обзор его недели.
class _ScheduleDayView extends ConsumerStatefulWidget {
  const _ScheduleDayView({
    required this.date,
    required this.now,
    required this.onPickDay,
  });

  final DateTime date;
  final DateTime now;
  final ValueChanged<DateTime> onPickDay;

  @override
  ConsumerState<_ScheduleDayView> createState() => _ScheduleDayViewState();
}

class _ScheduleDayViewState extends ConsumerState<_ScheduleDayView> {
  bool _week = false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final all = ref.watch(scheduleItemsProvider).value ?? const [];
    final items = scheduleForDay(all, widget.date);
    final conflicts = scheduleConflicts(items);
    final theme = Theme.of(context);
    final muted = theme.brightness == Brightness.dark
        ? AppColors.textSecondaryDark
        : AppColors.textSecondary;

    // У недели шапка показывает её даты: «2 – 8 ноября», а на стыке месяцев
    // короче, «28 сент. – 4 окт.», иначе строка не влезет рядом с кнопкой.
    // Под шапкой у дня — сколько пунктов и сколько времени они занимают.
    String? weekTitle;
    var summary = '';
    if (_week) {
      final locale = Localizations.localeOf(context).languageCode;
      final d = widget.date;
      final monday = DateTime(d.year, d.month, d.day - d.weekday + 1);
      final sunday = DateTime(d.year, d.month, d.day + 7 - d.weekday);
      final short = DateFormat('d MMM', locale);
      weekTitle = monday.month == sunday.month
          ? '${monday.day} – ${DateFormat('d MMMM', locale).format(sunday)}'
          : '${short.format(monday)} – ${short.format(sunday)}';
    } else if (items.isNotEmpty) {
      final busy = busyMinutes(items, 0, 24 * 60);
      summary = [
        l10n.scheduleItemsCount(items.length),
        if (busy > 0) l10n.scheduleBusyShort(_fmtDuration(busy, context)),
      ].join(' · ');
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      children: [
        // Та же шапка, что у задач; кнопка показывает, куда переключит:
        // иконки одной пары «календарь-день / календарь-неделя».
        _DayMasthead(
          date: widget.date,
          title: weekTitle,
          actionIcon: _week
              ? Icons.calendar_view_day_outlined
              : Icons.calendar_view_week_outlined,
          actionLabel: _week ? l10n.scheduleViewDay : l10n.scheduleViewWeek,
          onAction: () => setState(() => _week = !_week),
        ),
        if (summary.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 0, 2, 6),
            child: Text(
              summary,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(color: muted),
            ),
          ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: _week
              ? _ScheduleWeek(
                  key: const ValueKey('week'),
                  all: all,
                  date: widget.date,
                  now: widget.now,
                  onPickDay: (d) {
                    setState(() => _week = false);
                    widget.onPickDay(d);
                  },
                )
              : Column(
                  key: const ValueKey('day'),
                  children: [
                    if (items.isEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: NotebookEmptyState(
                          icon: Icons.event_note_outlined,
                          text: l10n.scheduleEmptyState,
                        ),
                      ),
                      // Расписание пустое совсем — подсказываем, что пары
                      // и смены можно не вбивать руками, а взять из календаря.
                      if (all.isEmpty)
                        TextButton.icon(
                          onPressed: () =>
                              CalendarSection.importFile(context, ref),
                          icon: const Icon(Icons.event_note_outlined, size: 18),
                          label: Text(l10n.scheduleImportCta),
                        ),
                    ] else
                      for (final item in items)
                        _ScheduleTile(
                          item: item,
                          date: widget.date,
                          now: widget.now,
                          conflict: conflicts.contains(item.id),
                        ),
                  ],
                ),
        ),
      ],
    );
  }
}

/// Обзор недели выбранного дня: по дню на блок, пн–вс. Нажатие на день
/// открывает его ленту.
class _ScheduleWeek extends StatelessWidget {
  const _ScheduleWeek({
    super.key,
    required this.all,
    required this.date,
    required this.now,
    required this.onPickDay,
  });

  final List<ScheduleItem> all;
  final DateTime date;
  final DateTime now;
  final ValueChanged<DateTime> onPickDay;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final muted = dark ? AppColors.textSecondaryDark : AppColors.textSecondary;
    final locale = Localizations.localeOf(context).languageCode;
    final monday = DateTime(date.year, date.month, date.day - date.weekday + 1);
    return Column(
      children: [
        for (var d = 0; d < 7; d++)
          Builder(
            builder: (context) {
              final day = DateTime(monday.year, monday.month, monday.day + d);
              final items = scheduleForDay(all, day);
              final isToday = isSameDay(day, now);
              final selected = isSameDay(day, date);
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Card(
                  margin: EdgeInsets.zero,
                  clipBehavior: Clip.antiAlias,
                  shape: selected
                      ? RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: const BorderSide(color: AppColors.primary),
                        )
                      : null,
                  child: InkWell(
                    onTap: () => onPickDay(day),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _capitalize(
                              DateFormat('EEEE, d MMMM', locale).format(day),
                            ),
                            style: theme.textTheme.labelLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: isToday ? AppColors.primary : null,
                            ),
                          ),
                          if (items.isEmpty)
                            Text('—', style: TextStyle(color: muted))
                          else
                            for (final i in items)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 8,
                                      height: 8,
                                      decoration: BoxDecoration(
                                        color: _scheduleColor(i) ?? muted,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    SizedBox(
                                      width: 92,
                                      child: Text(
                                        _scheduleTimeLabel(i),
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(color: muted),
                                      ),
                                    ),
                                    Expanded(
                                      child: Text(
                                        i.location == null
                                            ? i.title
                                            : '${i.title} · ${i.location}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.bodyMedium,
                                      ),
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
            },
          ),
      ],
    );
  }
}

class _ScheduleTile extends ConsumerWidget {
  const _ScheduleTile({
    required this.item,
    required this.date,
    required this.now,
    this.conflict = false,
  });

  final ScheduleItem item;
  final DateTime date;
  final DateTime now;

  /// Пересекается по времени с другим пунктом дня.
  final bool conflict;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final dark = theme.brightness == Brightness.dark;
    final nowMin = now.hour * 60 + now.minute;
    final isToday = isSameDay(date, now);
    final end = item.endMinutes;
    final live =
        isToday && end != null && nowMin >= item.startMinutes && nowMin < end;
    // Пункт без конца — момент: прошёл, как только наступило его время.
    final over = dateOnly(date).isBefore(dateOnly(now)) ||
        (isToday && nowMin >= (end ?? item.startMinutes + 1));
    final muted = dark ? AppColors.textSecondaryDark : AppColors.textSecondary;
    final surface = theme.cardTheme.color ?? theme.cardColor;
    final spine = _scheduleColor(item) ??
        (live
            ? AppColors.primary
            : (dark ? AppColors.surfaceDarkMuted : AppColors.ringTrack));
    final duration = item.durationMinutes;

    final card = Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      color: live
          ? Color.alphaBlend(AppColors.primary.withValues(alpha: 0.12), surface)
          : null,
      child: InkWell(
        onTap: () => _showScheduleForm(context, date: date, existing: item),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 4, 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 48,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _fmtTime(item.startMinutes),
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        if (end != null)
                          Text(
                            _fmtTime(end),
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: muted),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          style: theme.textTheme.bodyLarge
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 2),
                        Wrap(
                          spacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (duration != null)
                              Text(
                                _fmtDuration(duration, context),
                                style: theme.textTheme.bodySmall
                                    ?.copyWith(color: muted),
                              ),
                            if (item.location != null)
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.place_outlined,
                                    size: 14,
                                    color: muted,
                                  ),
                                  const SizedBox(width: 2),
                                  Text(
                                    item.location!,
                                    style: theme.textTheme.bodySmall
                                        ?.copyWith(color: muted),
                                  ),
                                ],
                              ),
                            if (item.isSeries)
                              Icon(Icons.repeat, size: 14, color: muted),
                            if (item.reminderMinutes != null)
                              Icon(
                                Icons.notifications_none,
                                size: 14,
                                color: muted,
                              ),
                            if (conflict)
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.warning_amber_rounded,
                                    size: 14,
                                    color: AppColors.warning,
                                  ),
                                  const SizedBox(width: 2),
                                  Text(
                                    l10n.scheduleConflict,
                                    style: theme.textTheme.bodySmall
                                        ?.copyWith(color: AppColors.warning),
                                  ),
                                ],
                              ),
                          ],
                        ),
                        if (item.note != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              item.note!,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: muted),
                            ),
                          ),
                      ],
                    ),
                  ),
                  PopupMenuButton<_ScheduleAction>(
                    icon: Icon(Icons.more_vert, color: muted),
                    onSelected: (a) => switch (a) {
                      _ScheduleAction.makeTask =>
                        _makeScheduleTask(context, ref, item, date),
                      _ScheduleAction.duplicate =>
                        _showScheduleForm(context, date: date, template: item),
                      _ScheduleAction.delete =>
                        _deleteScheduleItem(context, ref, item, date),
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: _ScheduleAction.makeTask,
                        child: Text(l10n.scheduleMakeTask),
                      ),
                      PopupMenuItem(
                        value: _ScheduleAction.duplicate,
                        child: Text(l10n.scheduleDuplicate),
                      ),
                      PopupMenuItem(
                        value: _ScheduleAction.delete,
                        child: Text(
                          l10n.delete,
                          style: const TextStyle(color: AppColors.danger),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
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

    return Opacity(
      opacity: over ? 0.55 : 1,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        // Свайп спрашивает то же, что пункт меню, и убирает карточку, только
        // если удаление подтвердили. Список обычный (не AnimatedList), так что
        // диалог посреди свайпа, как у задач, ничего не ломает.
        child: Dismissible(
          key: ValueKey('${item.id}_${dateOnly(date)}'),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.symmetric(horizontal: 24),
            decoration: BoxDecoration(
              color: AppColors.danger.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.delete_outline, color: AppColors.danger),
          ),
          confirmDismiss: (_) => _deleteScheduleItem(context, ref, item, date),
          child: card,
        ),
      ),
    );
  }
}

enum _ScheduleAction { makeTask, duplicate, delete }

/// Компактная сводка расписания дня на вкладке «Задачи»: занятое время видно
/// там, где планируют задачи. Нажатие открывает вкладку «Расписание».
class _ScheduleStrip extends StatelessWidget {
  const _ScheduleStrip({required this.items, required this.onOpen});

  final List<ScheduleItem> items;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final muted = dark ? AppColors.textSecondaryDark : AppColors.textSecondary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.event_note_outlined, size: 16, color: muted),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${context.l10n.scheduleTab} · ${items.length}',
                        style:
                            theme.textTheme.labelMedium?.copyWith(color: muted),
                      ),
                    ),
                    Icon(Icons.chevron_right, size: 18, color: muted),
                  ],
                ),
                const SizedBox(height: 4),
                for (final i in items)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      '${_scheduleTimeLabel(i)}  ${i.title}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(color: muted),
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

// ─── Действия ────────────────────────────────────────────────────────────────

/// [template] — «Дублировать»: анкета нового пункта, заполненная по образцу.
Future<void> _showScheduleForm(
  BuildContext context, {
  required DateTime date,
  ScheduleItem? existing,
  ScheduleItem? template,
}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => EscDismissible(
        child: _ScheduleFormSheet(
          date: date,
          existing: existing,
          template: template,
        ),
      ),
    );

/// «Сделать задачей». У серии спрашивает: задача на один день или
/// повторяющаяся по тому же правилу. Пункт в расписании остаётся.
Future<void> _makeScheduleTask(
  BuildContext context,
  WidgetRef ref,
  ScheduleItem item,
  DateTime day,
) async {
  final tasks = ref.read(taskRepositoryProvider);
  final l10n = context.l10n;
  var series = false;
  if (item.isSeries) {
    final choice = await _askDayOrSeries(
      context,
      icon: Icons.task_alt_rounded,
      title: l10n.scheduleMakeTask,
      daySubtitle: l10n.scheduleMakeTaskDaySubtitle(
        DateFormat('d MMMM', Localizations.localeOf(context).languageCode)
            .format(day),
      ),
      seriesSubtitle: l10n.scheduleMakeTaskSeriesSubtitle,
    );
    if (choice == null) return;
    series = choice;
  }
  await addScheduleAsTask(tasks, item, day, series: series);
  if (context.mounted) {
    showFancyToast(context, message: l10n.scheduleTaskCreatedToast);
  }
}

/// Диалог «Только этот день / Вся серия»: false — день, true — серия,
/// null — отмена.
Future<bool?> _askDayOrSeries(
  BuildContext context, {
  required IconData icon,
  required String title,
  required String daySubtitle,
  required String seriesSubtitle,
  String? seriesTitle,
  bool danger = false,
}) {
  final l10n = context.l10n;
  return showFancyDialog<bool>(
    context: context,
    icon: icon,
    iconColor: danger ? AppColors.danger : AppColors.primary,
    title: title,
    contentBuilder: (ctx) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _RecurringChoiceRow(
          icon: Icons.today_outlined,
          title: l10n.scheduleMakeTaskDayTitle,
          subtitle: daySubtitle,
          onTap: () => Navigator.pop(ctx, false),
        ),
        _RecurringChoiceRow(
          icon: danger ? Icons.delete_sweep_outlined : Icons.repeat_rounded,
          title: seriesTitle ?? l10n.scheduleMakeTaskSeriesTitle,
          subtitle: seriesSubtitle,
          danger: danger,
          onTap: () => Navigator.pop(ctx, true),
        ),
      ],
    ),
  );
}

/// Удаление: у серии — «только этот день» или вся серия; разовый пункт —
/// после подтверждения. true — что-то удалили (для свайпа).
Future<bool> _deleteScheduleItem(
  BuildContext context,
  WidgetRef ref,
  ScheduleItem item,
  DateTime day,
) async {
  final repo = ref.read(scheduleRepositoryProvider);
  final l10n = context.l10n;
  final bool? whole;
  if (item.isSeries) {
    whole = await _askDayOrSeries(
      context,
      icon: Icons.event_busy_rounded,
      title: l10n.scheduleDeleteTitle,
      daySubtitle: l10n.scheduleDeleteDaySubtitle,
      seriesTitle: l10n.scheduleDeleteSeriesTitle,
      seriesSubtitle: l10n.scheduleDeleteSeriesSubtitle,
      danger: true,
    );
  } else {
    whole = await showFancyDialog<bool>(
      context: context,
      icon: Icons.event_busy_rounded,
      iconColor: AppColors.danger,
      title: l10n.scheduleDeleteTitle,
      content: item.title,
      actions: (ctx) => [
        TextButton(
          onPressed: () => Navigator.pop(ctx, null),
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
  }
  if (whole == null) return false;
  if (whole) {
    await repo.delete(item.id);
  } else {
    await repo.deleteOccurrence(item, day);
  }
  return true;
}

// ─── Анкета пункта ───────────────────────────────────────────────────────────

class _ScheduleFormSheet extends ConsumerStatefulWidget {
  const _ScheduleFormSheet({
    required this.date,
    this.existing,
    this.template,
  });

  /// День, с которого открыли анкету: дата нового пункта, день для
  /// «Сделать задачей» и для правки «только этого дня».
  final DateTime date;
  final ScheduleItem? existing;
  final ScheduleItem? template;

  @override
  ConsumerState<_ScheduleFormSheet> createState() => _ScheduleFormSheetState();
}

class _ScheduleFormSheetState extends ConsumerState<_ScheduleFormSheet> {
  static const _reminderOptions = <int?>[null, 0, 5, 10, 15, 30, 60];

  late final TextEditingController _title;
  late final TextEditingController _note;
  late final TextEditingController _location;
  int? _start;
  int? _end;
  RecurrenceKind? _repeat;
  final Set<int> _weekdays = {};
  final Set<int> _monthDays = {};
  int _intervalDays = 2;
  int _weekInterval = 1;
  int? _color;

  /// null — не трогать конец уже существующей серии.
  _RecDuration? _duration;
  int? _reminder;
  bool _showErrors = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    final src = e ?? widget.template;
    _title = TextEditingController(text: src?.title ?? '');
    _note = TextEditingController(text: src?.note ?? '');
    _location = TextEditingController(text: src?.location ?? '');
    _start = src?.startMinutes;
    _end = src?.endMinutes;
    _repeat = src?.repeat;
    _weekdays.addAll(
      src?.repeat == RecurrenceKind.weekly
          ? src!.weekdays
          : [widget.date.weekday],
    );
    _monthDays.addAll(
      src?.repeat == RecurrenceKind.monthly
          ? src!.monthDays
          : [widget.date.day],
    );
    if (src?.repeat == RecurrenceKind.interval) {
      _intervalDays = src!.intervalDays;
    }
    _weekInterval = src?.weekInterval ?? 1;
    _color = src?.colorIndex;
    _duration = (e?.isSeries ?? false) ? null : _RecDuration.year;
    _reminder = src == null
        ? ref.read(notificationControllerProvider).prefs.scheduleLeadMinutes
        : src.reminderMinutes;
  }

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    _location.dispose();
    super.dispose();
  }

  bool get _timeOk => _start != null && (_end == null || _end! > _start!);

  bool get _repeatOk => switch (_repeat) {
        null => true,
        RecurrenceKind.weekly => _weekdays.isNotEmpty,
        RecurrenceKind.monthly => _monthDays.isNotEmpty,
        RecurrenceKind.interval => _intervalDays > 0,
      };

  bool get _valid => _title.text.trim().isNotEmpty && _timeOk && _repeatOk;

  static String? _text(TextEditingController c) =>
      c.text.trim().isEmpty ? null : c.text.trim();

  /// Сохраняет анкету; null — анкета заполнена не до конца или правку серии
  /// отменили.
  Future<ScheduleItem?> _persist() async {
    if (!_valid) {
      setState(() => _showErrors = true);
      return null;
    }
    final repo = ref.read(scheduleRepositoryProvider);
    final l10n = context.l10n;
    final title = _title.text.trim();
    final note = _text(_note);
    final location = _text(_location);
    final weekdays = _repeat == RecurrenceKind.weekly
        ? (_weekdays.toList()..sort())
        : <int>[];
    final monthDays = _repeat == RecurrenceKind.monthly
        ? (_monthDays.toList()..sort())
        : <int>[];
    final e = widget.existing;

    Future<ScheduleItem> createNew(DateTime date, {required bool series}) =>
        repo.create(
          title: title,
          date: date,
          startMinutes: _start!,
          endMinutes: _end,
          note: note,
          location: location,
          colorIndex: _color,
          repeat: series ? _repeat : null,
          weekdays: series ? weekdays : const [],
          monthDays: series ? monthDays : const [],
          intervalDays: _intervalDays,
          weekInterval: _weekInterval,
          endDate: series && _repeat != null
              ? _recEndDate(date, _duration ?? _RecDuration.year)
              : null,
          reminderMinutes: _reminder,
        );

    if (e == null) return createNew(widget.date, series: true);

    // Правка серии: «только этот день» выносит день из серии в отдельный
    // разовый пункт с новыми значениями — так переносят одно занятие.
    if (e.isSeries) {
      final whole = await _askDayOrSeries(
        context,
        icon: Icons.edit_calendar_outlined,
        title: l10n.scheduleEditScopeTitle,
        daySubtitle: l10n.scheduleEditDaySubtitle,
        seriesSubtitle: l10n.scheduleEditSeriesSubtitle,
      );
      if (whole == null) return null;
      if (!whole) {
        await repo.deleteOccurrence(e, widget.date);
        return createNew(dateOnly(widget.date), series: false);
      }
    }

    // Серия, превращённая в разовый пункт, остаётся в том дне, где её правят.
    final date =
        _repeat != null || !e.isSeries ? e.date : dateOnly(widget.date);
    final endDate = _repeat == null
        ? null
        : (_duration == null ? e.endDate : _recEndDate(date, _duration!));
    final updated = e.copyWith(
      title: title,
      date: date,
      startMinutes: _start,
      endMinutes: _end,
      clearEndMinutes: _end == null,
      note: note,
      clearNote: note == null,
      location: location,
      clearLocation: location == null,
      colorIndex: _color,
      clearColor: _color == null,
      repeat: _repeat,
      clearRepeat: _repeat == null,
      weekdays: weekdays,
      monthDays: monthDays,
      intervalDays: _intervalDays,
      weekInterval: _weekInterval,
      endDate: endDate,
      clearEndDate: endDate == null,
      reminderMinutes: _reminder,
      clearReminder: _reminder == null,
    );
    await repo.update(updated);
    return updated;
  }

  Future<void> _save() async {
    if (await _persist() != null && mounted) Navigator.of(context).pop(true);
  }

  Future<void> _saveAndMakeTask() async {
    final item = await _persist();
    if (item == null || !mounted) return;
    await _makeScheduleTask(context, ref, item, widget.date);
    // Пункт уже сохранён: оставшись в анкете, повторное «Добавить»
    // создало бы дубль.
    if (mounted) Navigator.of(context).pop(true);
  }

  /// Чип дня недели / числа месяца: последний выбранный не снимается —
  /// серия без дней молча не сохранилась бы.
  Widget _dayChip(String label, int value, Set<int> set) => SegChip(
        label: label,
        selected: set.contains(value),
        onTap: () => setState(() {
          if (!set.add(value) && set.length > 1) set.remove(value);
        }),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final weekdayLabels = _weekdayLabels(context);
    final e = widget.existing;

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
              controller: _title,
              autofocus: e == null,
              decoration: InputDecoration(
                hintText: l10n.scheduleTitleHint,
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
                    minutes: _start,
                    onChanged: (v) => setState(() {
                      _start = v;
                      // Конец подтягивается за началом, чтобы не выставлять
                      // оба времени заново. Крестиком его можно убрать.
                      if (v != null && (_end == null || _end! <= v)) {
                        _end = v + 60 > 1439 ? 1439 : v + 60;
                      }
                    }),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _TimePicker(
                    label: l10n.timeToLabel,
                    minutes: _end,
                    onChanged: (v) => setState(() => _end = v),
                  ),
                ),
              ],
            ),
            if (_showErrors && !_timeOk)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  l10n.scheduleTimeError,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: AppColors.danger),
                ),
              ),
            const SizedBox(height: 12),
            TextField(
              controller: _location,
              decoration: InputDecoration(
                hintText: l10n.scheduleLocationHint,
                prefixIcon: const Icon(Icons.place_outlined, size: 20),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _note,
              minLines: 1,
              maxLines: 5,
              keyboardType: TextInputType.multiline,
              decoration: InputDecoration(
                hintText: l10n.scheduleNoteHint,
                prefixIcon: const Icon(Icons.notes, size: 20),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 14),
            Text(l10n.scheduleColorLabel, style: theme.textTheme.labelMedium),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var c = -1; c < _scheduleColors.length; c++)
                  _ColorDot(
                    color: c < 0 ? null : _scheduleColors[c],
                    selected: (_color ?? -1) == c,
                    onTap: () => setState(() => _color = c < 0 ? null : c),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Text(l10n.scheduleRepeatLabel, style: theme.textTheme.labelMedium),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final k in <RecurrenceKind?>[
                  null,
                  ...RecurrenceKind.values
                ])
                  SegChip(
                    label: switch (k) {
                      null => l10n.scheduleRepeatOnce,
                      RecurrenceKind.weekly => l10n.recKindWeekly,
                      RecurrenceKind.monthly => l10n.recKindMonthly,
                      RecurrenceKind.interval => l10n.recKindInterval,
                    },
                    selected: _repeat == k,
                    onTap: () => setState(() => _repeat = k),
                  ),
              ],
            ),
            if (_repeat != null) ...[
              const SizedBox(height: 8),
              switch (_repeat!) {
                RecurrenceKind.weekly => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          for (var i = 0; i < 7; i++)
                            _dayChip(weekdayLabels[i], i + 1, _weekdays),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          SegChip(
                            label: l10n.scheduleEveryWeek,
                            selected: _weekInterval == 1,
                            onTap: () => setState(() => _weekInterval = 1),
                          ),
                          SegChip(
                            label: l10n.scheduleEveryOtherWeek,
                            selected: _weekInterval == 2,
                            onTap: () => setState(() => _weekInterval = 2),
                          ),
                        ],
                      ),
                      if (_weekInterval == 2)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            l10n.scheduleEveryOtherWeekHint,
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                    ],
                  ),
                RecurrenceKind.monthly => Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      for (var d = 1; d <= 31; d++)
                        _dayChip('$d', d, _monthDays),
                    ],
                  ),
                RecurrenceKind.interval => Row(
                    children: [
                      Text(l10n.everyLabel),
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
                      Text(l10n.daysShort),
                    ],
                  ),
              },
              const SizedBox(height: 10),
              Text(
                l10n.recDurationSectionLabel,
                style: theme.textTheme.labelMedium,
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final d in _RecDuration.values)
                    SegChip(
                      label: _recDurationLabel(context, d),
                      selected: _duration == d,
                      onTap: () => setState(() => _duration = d),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 14),
            Text(
              l10n.scheduleReminderLabel,
              style: theme.textTheme.labelMedium,
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final m in _reminderOptions)
                  SegChip(
                    label: m == null
                        ? l10n.scheduleReminderNone
                        : m == 0
                            ? l10n.leadAtMoment
                            : l10n.leadMinutesShort(m),
                    selected: _reminder == m,
                    onTap: () => setState(() => _reminder = m),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _saveAndMakeTask,
                    icon: const Icon(Icons.task_alt, size: 18),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                    // Не «Сделать зада…»: если не влезает — текст ужимается.
                    label: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(l10n.scheduleMakeTask),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: _save,
                    child: Text(e == null ? l10n.addBtn : l10n.saveBtn),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Кружок выбора цвета; [color] == null — «без цвета».
class _ColorDot extends StatelessWidget {
  const _ColorDot({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color? color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).brightness == Brightness.dark
        ? AppColors.textSecondaryDark
        : AppColors.textSecondary;
    return InkWell(
      customBorder: const CircleBorder(),
      onTap: onTap,
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? AppColors.textPrimary : muted,
            width: selected ? 2.5 : 1,
          ),
        ),
        child: color == null
            ? Icon(Icons.block, size: 16, color: muted)
            : (selected
                ? const Icon(Icons.check, size: 16, color: Colors.white)
                : null),
      ),
    );
  }
}
