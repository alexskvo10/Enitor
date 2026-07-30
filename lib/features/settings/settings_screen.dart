import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/locale_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/appearance.dart';
import '../../l10n/l10n_extensions.dart';
import '../../services/backup_service.dart';
import '../../services/notification_controller.dart';
import '../../widgets/fancy_dialog.dart';
import '../../widgets/fancy_toast.dart';
import '../../widgets/pill_toggle.dart';

/// Настройки: оформление, уведомления, тихие часы, данные.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final appearance = ref.watch(appearanceProvider);
    final localeCtrl = ref.watch(localeControllerProvider);
    final notif = ref.watch(notificationControllerProvider);
    final prefs = notif.prefs;
    final on = prefs.enabled;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: ListView(
        padding: const EdgeInsets.only(top: 4, bottom: 24),
        children: [
          // ── Оформление ──────────────────────────────────────────────────
          _sectionTitle(context, l10n.sectionAppearance),
          _card([
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _tileTitle(context, l10n.themeLabel),
                  const SizedBox(height: 8),
                  PillToggle<ThemeMode>(
                    selected: appearance.themeMode,
                    segments: [
                      (ThemeMode.system, l10n.themeSystem),
                      (ThemeMode.light, l10n.themeLight),
                      (ThemeMode.dark, l10n.themeDark),
                    ],
                    onChanged: (v) =>
                        ref.read(appearanceProvider).setThemeMode(v),
                  ),
                  const SizedBox(height: 16),
                  _tileTitle(context, l10n.backgroundLabel),
                  const SizedBox(height: 8),
                  PillToggle<BackgroundStyle>(
                    selected: appearance.style,
                    segments: [
                      (BackgroundStyle.plain, l10n.bgPlain),
                      (BackgroundStyle.paper, l10n.bgPaper),
                      (BackgroundStyle.dots, l10n.bgDots),
                    ],
                    onChanged: (v) => ref.read(appearanceProvider).setStyle(v),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, indent: 16, endIndent: 16),
            SwitchListTile(
              title: _tileTitle(context, l10n.vignetteTitle),
              subtitle: Text(l10n.vignetteSubtitle),
              value: appearance.vignette,
              onChanged: (v) => ref.read(appearanceProvider).setVignette(v),
            ),
          ]),

          // ── Уведомления ─────────────────────────────────────────────────
          _sectionTitle(context, l10n.sectionNotifications),
          _card([
            SwitchListTile(
              title: _tileTitle(context, l10n.notificationsTitle),
              subtitle: Text(l10n.notificationsSubtitle),
              value: on,
              onChanged: (v) =>
                  ref.read(notificationControllerProvider).setEnabled(v),
            ),
            const Divider(height: 1, indent: 16, endIndent: 16),

            // Напоминания к задачам.
            SwitchListTile(
              title: _tileTitle(context, l10n.taskRemindersTitle),
              subtitle: Text(prefs.taskLeadMinutes > 0
                  ? l10n.taskRemindersLead(prefs.taskLeadMinutes)
                  : l10n.taskRemindersAtStart),
              value: prefs.taskReminders,
              onChanged: on
                  ? (v) => ref
                      .read(notificationControllerProvider)
                      .setTaskReminders(v)
                  : null,
            ),
            if (on && prefs.taskReminders)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: _miniLabel(context, l10n.leadBeforeStart),
                    ),
                    const SizedBox(width: 12),
                    _leadDropdown(
                      context,
                      value: prefs.taskLeadMinutes,
                      onChanged: (m) => ref
                          .read(notificationControllerProvider)
                          .setTaskLead(m),
                    ),
                  ],
                ),
              ),
            const Divider(height: 1, indent: 16, endIndent: 16),

            // Напоминание к концу задачи.
            SwitchListTile(
              title: _tileTitle(context, l10n.taskEndRemindersTitle),
              subtitle: Text(prefs.taskEndLeadMinutes > 0
                  ? l10n.taskEndRemindersLead(prefs.taskEndLeadMinutes)
                  : l10n.taskEndRemindersAtEnd),
              value: prefs.taskEndReminders,
              onChanged: on
                  ? (v) => ref
                      .read(notificationControllerProvider)
                      .setTaskEndReminders(v)
                  : null,
            ),
            if (on && prefs.taskEndReminders)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: _miniLabel(context, l10n.leadBeforeEnd),
                    ),
                    const SizedBox(width: 12),
                    _leadDropdown(
                      context,
                      value: prefs.taskEndLeadMinutes,
                      onChanged: (m) => ref
                          .read(notificationControllerProvider)
                          .setTaskEndLead(m),
                    ),
                  ],
                ),
              ),
            const Divider(height: 1, indent: 16, endIndent: 16),

            // «Требует внимания» — совпадает с бейджем в списке задач.
            SwitchListTile(
              title: _tileTitle(context, l10n.taskUrgentAlertsTitle),
              subtitle: Text(l10n.taskUrgentAlertsSubtitle),
              value: prefs.taskUrgentAlerts,
              onChanged: on
                  ? (v) => ref
                      .read(notificationControllerProvider)
                      .setTaskUrgentAlerts(v)
                  : null,
            ),
            const Divider(height: 1, indent: 16, endIndent: 16),

            // Просрочена.
            SwitchListTile(
              title: _tileTitle(context, l10n.taskOverdueAlertsTitle),
              subtitle: Text(l10n.taskOverdueAlertsSubtitle),
              value: prefs.taskOverdueAlerts,
              onChanged: on
                  ? (v) => ref
                      .read(notificationControllerProvider)
                      .setTaskOverdueAlerts(v)
                  : null,
            ),
            const Divider(height: 1, indent: 16, endIndent: 16),

            // Цели: «Требует внимания» — совпадает с бейджем в списке целей.
            SwitchListTile(
              title: _tileTitle(context, l10n.goalUrgentAlertsTitle),
              subtitle: Text(l10n.goalUrgentAlertsSubtitle),
              value: prefs.goalUrgentAlerts,
              onChanged: on
                  ? (v) => ref
                      .read(notificationControllerProvider)
                      .setGoalUrgentAlerts(v)
                  : null,
            ),
            const Divider(height: 1, indent: 16, endIndent: 16),

            // Цели: просрочена.
            SwitchListTile(
              title: _tileTitle(context, l10n.goalOverdueAlertsTitle),
              subtitle: Text(l10n.goalOverdueAlertsSubtitle),
              value: prefs.goalOverdueAlerts,
              onChanged: on
                  ? (v) => ref
                      .read(notificationControllerProvider)
                      .setGoalOverdueAlerts(v)
                  : null,
            ),
            const Divider(height: 1, indent: 16, endIndent: 16),

            // Утренний план.
            SwitchListTile(
              title: _tileTitle(context, l10n.morningPlanTitle),
              subtitle: Text(on && prefs.morningPlan
                  ? l10n.dailyAt(_fmt(prefs.morningMinutes))
                  : l10n.morningPlanSubtitleOff),
              value: prefs.morningPlan,
              onChanged: on
                  ? (v) =>
                      ref.read(notificationControllerProvider).setMorningPlan(v)
                  : null,
            ),
            if (on && prefs.morningPlan)
              _timeTile(
                context,
                minutes: prefs.morningMinutes,
                onPicked: (m) =>
                    ref.read(notificationControllerProvider).setMorningTime(m),
              ),
            const Divider(height: 1, indent: 16, endIndent: 16),

            // Вечерняя оценка.
            SwitchListTile(
              title: _tileTitle(context, l10n.eveningReviewTitle),
              subtitle: Text(on && prefs.eveningReview
                  ? l10n.dailyAt(_fmt(prefs.eveningMinutes))
                  : l10n.eveningReviewSubtitleOff),
              value: prefs.eveningReview,
              onChanged: on
                  ? (v) => ref
                      .read(notificationControllerProvider)
                      .setEveningReview(v)
                  : null,
            ),
            if (on && prefs.eveningReview)
              _timeTile(
                context,
                minutes: prefs.eveningMinutes,
                onPicked: (m) =>
                    ref.read(notificationControllerProvider).setEveningTime(m),
              ),
            const Divider(height: 1, indent: 16, endIndent: 16),

            // Общие напоминания.
            SwitchListTile(
              title: _tileTitle(context, l10n.generalRemindersTitle),
              subtitle: Text(l10n.generalRemindersSubtitle),
              value: prefs.generalReminders,
              onChanged: on
                  ? (v) => ref
                      .read(notificationControllerProvider)
                      .setGeneralReminders(v)
                  : null,
            ),
            const Divider(height: 1, indent: 16, endIndent: 16),

            // Разбор недели: уведомление + окно с итогами при первом открытии
            // после назначенного момента. День и время настраиваемые — 19:00
            // понедельника подходит большинству, но не всем.
            SwitchListTile(
              title: _tileTitle(context, l10n.weeklyRetroTitle),
              subtitle: Text(
                on && prefs.weeklyRetro
                    ? l10n.weeklyRetroSubtitleOn(
                        weekdayNames(l10n)[prefs.retroWeekday - 1],
                        _fmt(prefs.retroMinutes),
                      )
                    : l10n.weeklyRetroSubtitleOff,
              ),
              value: prefs.weeklyRetro,
              onChanged: on
                  ? (v) =>
                      ref.read(notificationControllerProvider).setWeeklyRetro(v)
                  : null,
            ),
            if (on && prefs.weeklyRetro)
              _weekdayAndTimeTile(
                context,
                weekday: prefs.retroWeekday,
                minutes: prefs.retroMinutes,
                onWeekdayPicked: (d) =>
                    ref.read(notificationControllerProvider).setRetroWeekday(d),
                onTimePicked: (m) =>
                    ref.read(notificationControllerProvider).setRetroTime(m),
              ),
            const Divider(height: 1, indent: 16, endIndent: 16),

            // Общие напоминания по целям (отдельно от общих напоминаний по
            // задачам выше) — пару раз в неделю, а не каждый день.
            SwitchListTile(
              title: _tileTitle(context, l10n.goalGeneralRemindersTitle),
              subtitle: Text(l10n.goalGeneralRemindersSubtitle),
              value: prefs.goalGeneralReminders,
              onChanged: on
                  ? (v) => ref
                      .read(notificationControllerProvider)
                      .setGoalGeneralReminders(v)
                  : null,
            ),
            const Divider(height: 1, indent: 16, endIndent: 16),

            // Уведомление о переносе.
            SwitchListTile(
              title: _tileTitle(context, l10n.transferReminderTitle),
              subtitle: Text(l10n.transferReminderSubtitle),
              value: prefs.transferReminder,
              onChanged: on
                  ? (v) => ref
                      .read(notificationControllerProvider)
                      .setTransferReminder(v)
                  : null,
            ),
            const Divider(height: 1, indent: 16, endIndent: 16),

            // Бэклог задач — единственное место, которое само о себе не
            // напоминает: попало туда и молчит, пока не вспомнят.
            SwitchListTile(
              title: _tileTitle(context, l10n.taskBacklogReminderTitle),
              subtitle: Text(l10n.taskBacklogReminderSubtitle),
              value: prefs.taskBacklogReminder,
              onChanged: on
                  ? (v) => ref
                      .read(notificationControllerProvider)
                      .setTaskBacklogReminder(v)
                  : null,
            ),
            const Divider(height: 1, indent: 16, endIndent: 16),

            // Бэклог целей — реже: он и наполняется несравнимо медленнее.
            SwitchListTile(
              title: _tileTitle(context, l10n.goalBacklogReminderTitle),
              subtitle: Text(l10n.goalBacklogReminderSubtitle),
              value: prefs.goalBacklogReminder,
              onChanged: on
                  ? (v) => ref
                      .read(notificationControllerProvider)
                      .setGoalBacklogReminder(v)
                  : null,
            ),
            const Divider(height: 1, indent: 16, endIndent: 16),

            // Тихие часы: тумблер вкл/выкл + отдельная кликабельная пилюля
            // для изменения времени (та же пилюля-с-часами, что у утра/вечера
            // — иначе было не очевидно, что тут вообще есть настройка).
            SwitchListTile(
              secondary: const Icon(Icons.bedtime_outlined),
              title: _tileTitle(context, l10n.quietHoursTitle),
              subtitle: Text(prefs.quietHoursEnabled
                  ? l10n.quietHoursSubtitle(
                      _fmt(prefs.quietStart), _fmt(prefs.quietEnd))
                  : l10n.quietHoursDisabledSubtitle),
              value: prefs.quietHoursEnabled,
              onChanged: on
                  ? (v) => ref
                      .read(notificationControllerProvider)
                      .setQuietHoursEnabled(v)
                  : null,
            ),
            if (on && prefs.quietHoursEnabled)
              _timeRangeTile(
                context,
                start: prefs.quietStart,
                end: prefs.quietEnd,
                onTap: () => _editQuietHours(context, ref),
              ),
          ]),
          _note(context, l10n.quietHoursNote),

          // ── Язык ────────────────────────────────────────────────────────
          _sectionTitle(context, l10n.sectionLanguage),
          _card([
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Expanded(child: _tileTitle(context, l10n.sectionLanguage)),
                  // Более аккуратная пилюля-список: скругление крупнее,
                  // паддинг просторнее, стрелка — настоящая иконка-шеврон
                  // (не текстовый символ), чуть светлее основного текста.
                  Container(
                    decoration: BoxDecoration(
                      color:
                          Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.12),
                      ),
                    ),
                    padding: const EdgeInsets.fromLTRB(13, 8, 15, 8),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<AppLocaleOption>(
                        value: localeCtrl.option,
                        isDense: true,
                        borderRadius: BorderRadius.circular(12),
                        icon: Icon(
                          Icons.expand_more,
                          size: 20,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.5),
                        ),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context).colorScheme.onSurface,
                              fontWeight: FontWeight.w600,
                            ),
                        items: [
                          DropdownMenuItem(
                            value: AppLocaleOption.system,
                            child: Text(l10n.localeSystem),
                          ),
                          const DropdownMenuItem(
                            value: AppLocaleOption.ru,
                            child: Text('Русский'),
                          ),
                          const DropdownMenuItem(
                            value: AppLocaleOption.en,
                            child: Text('English'),
                          ),
                        ],
                        onChanged: (v) {
                          if (v != null) {
                            ref.read(localeControllerProvider).setOption(v);
                          }
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ]),

          // ── Данные (бэкап) ──────────────────────────────────────────────
          _sectionTitle(context, l10n.sectionData),
          _card([
            ListTile(
              leading: const Icon(Icons.upload_file_outlined),
              title: _tileTitle(context, l10n.exportTitle),
              subtitle: Text(l10n.exportSubtitle),
              onTap: () => _export(context, ref),
            ),
            const Divider(height: 1, indent: 16, endIndent: 16),
            ListTile(
              leading: const Icon(Icons.download_outlined),
              title: _tileTitle(context, l10n.importTitle),
              subtitle: Text(l10n.importSubtitle),
              onTap: () => _import(context, ref),
            ),
            const Divider(height: 1, indent: 16, endIndent: 16),
            ListTile(
              leading: const Icon(Icons.settings_backup_restore),
              title: _tileTitle(context, l10n.resetSettingsTitle),
              subtitle: Text(l10n.resetSettingsSubtitle),
              onTap: () => _resetSettings(context, ref),
            ),
            const Divider(height: 1, indent: 16, endIndent: 16),
            ListTile(
              leading: const Icon(Icons.delete_forever_outlined,
                  color: AppColors.danger),
              title: _tileTitle(context, l10n.wipeDataTitle),
              subtitle: Text(l10n.wipeDataSubtitle),
              onTap: () => _wipeData(context, ref),
            ),
          ]),
          _note(context, l10n.backupNote),

          // ── Прочее ──────────────────────────────────────────────────────
          const SizedBox(height: 4),
          _card([
            ListTile(
              leading: const Icon(Icons.help_outline),
              title: _tileTitle(context, l10n.helpFaqTitle),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/faq'),
            ),
            const Divider(height: 1, indent: 16, endIndent: 16),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: _tileTitle(context, l10n.aboutTitle),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/about'),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
        child: Text(
          text.toUpperCase(),
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                letterSpacing: 0.8,
                fontWeight: FontWeight.w700,
              ),
        ),
      );

  /// Карточка-секция: оборачивает строки настроек, скругляет и клипает (чтобы
  /// разделители и нажатия не вылезали за углы).
  Widget _card(List<Widget> children) => Card(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        clipBehavior: Clip.antiAlias,
        child: Column(mainAxisSize: MainAxisSize.min, children: children),
      );

  /// Заголовок строки настройки — чуть жирнее обычного titleMedium (w600),
  /// чтобы сильнее выделяться на фоне подписи под ним.
  Widget _tileTitle(BuildContext context, String text) => Text(
        text,
        style: Theme.of(context)
            .textTheme
            .titleMedium
            ?.copyWith(fontWeight: FontWeight.w700),
      );

  /// Мелкая приглушённая подпись сбоку от пилюли-дропдауна («За сколько...»).
  Widget _miniLabel(BuildContext context, String text) => Text(
        text,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurface.withValues(
                    alpha: 0.7,
                  ),
            ),
      );

  /// Компактная пилюля-список «за сколько минут» — общий стиль для
  /// напоминаний и к началу, и к концу задачи (скругление и паддинг чуть
  /// меньше, чем у «Язык», но стрелка — та же иконка-шеврон).
  Widget _leadDropdown(
    BuildContext context, {
    required int value,
    required ValueChanged<int> onChanged,
  }) {
    final l10n = context.l10n;
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(
          color:
              Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.12),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: value,
          isDense: true,
          borderRadius: BorderRadius.circular(9),
          icon: Icon(
            Icons.expand_more,
            size: 20,
            color:
                Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
          ),
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
          items: const [0, 5, 10, 15, 30, 60]
              .map((m) => DropdownMenuItem(
                    value: m,
                    child: Text(
                        m == 0 ? l10n.leadAtMoment : l10n.leadMinutesShort(m)),
                  ))
              .toList(),
          onChanged: (m) {
            if (m != null) onChanged(m);
          },
        ),
      ),
    );
  }

  /// Пояснительная подпись под карточкой (мелким приглушённым текстом).
  Widget _note(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 2, 20, 8),
        child: Text(
          text,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurface.withValues(
                      alpha: 0.5,
                    ),
              ),
        ),
      );

  /// Пилюля с часиками и временем (акцентный тинт) — тап открывает пикер.
  Widget _timeTile(
    BuildContext context, {
    required int minutes,
    required ValueChanged<int> onPicked,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Align(
        alignment: Alignment.centerLeft,
        child: _pill(
          context,
          icon: Icons.schedule,
          label: _fmt(minutes),
          onTap: () async {
            final picked = await _pickTime(context, minutes);
            if (picked != null) onPicked(picked);
          },
        ),
      ),
    );
  }

  /// Пара пилюль «день недели + время» для настроек, которые срабатывают раз
  /// в неделю (разбор недели). Wrap, а не Row: на узком экране длинное имя
  /// дня («воскресенье») вместе со временем в строку не влезает.
  Widget _weekdayAndTimeTile(
    BuildContext context, {
    required int weekday,
    required int minutes,
    required ValueChanged<int> onWeekdayPicked,
    required ValueChanged<int> onTimePicked,
  }) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _pill(
            context,
            icon: Icons.event_outlined,
            label: _capitalize(weekdayNames(l10n)[weekday - 1]),
            showChevron: true,
            onTap: () async {
              final picked = await _pickWeekday(context, weekday);
              if (picked != null) onWeekdayPicked(picked);
            },
          ),
          _pill(
            context,
            icon: Icons.schedule,
            label: _fmt(minutes),
            onTap: () async {
              final picked = await _pickTime(context, minutes);
              if (picked != null) onTimePicked(picked);
            },
          ),
        ],
      ),
    );
  }

  /// Выбор дня недели: семь строк с галочкой у текущего. Свои строки, а не
  /// RadioListTile — тот в новых версиях Flutter требует RadioGroup, да и
  /// высотой не влезал бы в карточку диалога.
  Future<int?> _pickWeekday(BuildContext context, int current) {
    final l10n = context.l10n;
    final names = weekdayNames(l10n);
    return showFancyDialog<int>(
      context: context,
      icon: Icons.event_outlined,
      iconColor: AppColors.primary,
      title: l10n.retroDayPickerTitle,
      contentBuilder: (ctx) {
        final theme = Theme.of(ctx);
        final accent = theme.colorScheme.primary;
        // Потолок 340 — чтобы на большом экране список не растягивал окно;
        // под низкий экран его дожимает Flexible внутри showFancyDialog.
        return ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 340),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var d = 1; d <= 7; d++)
                  InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => Navigator.pop(ctx, d),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _capitalize(names[d - 1]),
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: d == current ? accent : null,
                                fontWeight: d == current
                                    ? FontWeight.w700
                                    : FontWeight.w400,
                              ),
                            ),
                          ),
                          if (d == current)
                            Icon(Icons.check, size: 18, color: accent),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
      actions: (ctx) => [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(l10n.cancel),
        ),
      ],
    );
  }

  /// Пилюля с иконкой и текстом (акцентный тинт) — общая основа для
  /// [_timeTile] и выбора дня недели.
  Widget _pill(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool showChevron = false,
  }) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    return Material(
      color: accent.withValues(alpha: 0.10),
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: accent),
              const SizedBox(width: 8),
              Text(
                label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (showChevron)
                Icon(Icons.chevron_right, size: 18, color: accent),
            ],
          ),
        ),
      ),
    );
  }

  /// Русские названия дней недели в l10n лежат строчными («понедельник») —
  /// в пилюле и списке выбора нужна заглавная. Для английского это no-op.
  static String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  /// Пилюля с часиками и диапазоном времени («23:00 – 08:00») — тот же стиль,
  /// что и [_timeTile], плюс шеврон: тихие часы — единственная настройка с
  /// диапазоном (start+end), а не одним временем, и раньше было совсем не
  /// очевидно, что строка вообще кликабельна.
  Widget _timeRangeTile(
    BuildContext context, {
    required int start,
    required int end,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Material(
          color: accent.withValues(alpha: 0.10),
          shape: const StadiumBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.schedule, size: 18, color: accent),
                  const SizedBox(width: 8),
                  Text(
                    '${_fmt(start)} – ${_fmt(end)}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Icon(Icons.chevron_right, size: 18, color: accent),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _editQuietHours(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final prefs = ref.read(notificationControllerProvider).prefs;
    final start = await _pickTime(context, prefs.quietStart,
        help: l10n.quietHoursStartHelp);
    if (start == null || !context.mounted) return;
    final end =
        await _pickTime(context, prefs.quietEnd, help: l10n.quietHoursEndHelp);
    if (end == null) return;
    await ref.read(notificationControllerProvider).setQuietHours(start, end);
  }

  /// Возвращает true, только если файл РЕАЛЬНО сохранён: отмена диалога
  /// сохранения и ошибка записи дают false. От этого зависит удаление данных
  /// в [_wipeData] — стереть всё после несостоявшегося экспорта нельзя.
  Future<bool> _export(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    try {
      final path = await ref.read(backupServiceProvider).exportToFile();
      if (path == null) return false; // отмена
      if (context.mounted) {
        showFancyToast(
          context,
          message: l10n.exportedToast(path),
          tone: ToastTone.success,
        );
      }
      return true;
    } catch (e) {
      if (context.mounted) {
        showFancyToast(
          context,
          message: l10n.exportFailedToast('$e'),
          tone: ToastTone.error,
        );
      }
      return false;
    }
  }

  /// Сброс настроек: только оформление, язык и уведомления. Данные не трогаем,
  /// поэтому перезапуск не нужен — контроллеры обновляют экраны сами.
  Future<void> _resetSettings(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final confirmed = await showFancyDialog<bool>(
      context: context,
      icon: Icons.settings_backup_restore,
      iconColor: AppColors.warning,
      title: l10n.resetSettingsConfirmTitle,
      content: l10n.resetSettingsConfirmContent,
      actions: (ctx) => [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(l10n.cancel),
        ),
        const SizedBox(width: 8),
        FilledButton(
          autofocus: true,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(l10n.resetSettingsBtn),
        ),
      ],
    );
    if (confirmed != true) return;
    await ref.read(appearanceProvider).resetToDefaults();
    await ref.read(localeControllerProvider).setOption(AppLocaleOption.system);
    await ref.read(notificationControllerProvider).resetToDefaults();
    if (!context.mounted) return;
    showFancyToast(
      context,
      message: l10n.resetSettingsDoneToast,
      tone: ToastTone.success,
    );
  }

  /// Полное удаление данных. Диалог предлагает сначала экспортировать — после
  /// удаления восстанавливать будет неоткуда: авто-бэкап стирается вместе с
  /// остальным, иначе `main()` поднял бы его на следующем запуске.
  Future<void> _wipeData(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final choice = await showFancyDialog<String>(
      context: context,
      icon: Icons.delete_forever_outlined,
      iconColor: AppColors.danger,
      title: l10n.wipeDataConfirmTitle,
      // contentBuilder, а не content: нужно выделить жирным только последнюю
      // строку — она здесь важнее всего остального текста.
      contentBuilder: (ctx) {
        final base = Theme.of(ctx)
            .textTheme
            .bodyMedium
            ?.copyWith(color: AppColors.textSecondary);
        return Text.rich(
          TextSpan(
            style: base,
            children: [
              TextSpan(text: '${l10n.wipeDataConfirmContent}\n\n'),
              TextSpan(
                text: l10n.cannotUndo,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          textAlign: TextAlign.center,
        );
      },
      // Раскладка тут намеренно своя, а не общая для диалогов: безопасные
      // действия в одну строку, а необратимое «удалить» — отдельной строкой
      // ниже, с большим отступом. Так его не задеть, целясь в соседнюю
      // кнопку, и оно требует отдельного осознанного движения.
      actions: (ctx) => [
        SizedBox(
          width: double.infinity,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  TextButton(
                    // Фокус по умолчанию — на безопасной кнопке, чтобы Enter
                    // не оказался «удалить».
                    autofocus: true,
                    onPressed: () => Navigator.pop(ctx, 'cancel'),
                    child: Text(l10n.cancel),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, 'export'),
                    child: Text(l10n.wipeDataExportThenWipeBtn),
                  ),
                ],
              ),
              // Отступ ровно в высоту кнопочной строки — «ещё на строку ниже».
              const SizedBox(height: 48),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
                onPressed: () => Navigator.pop(ctx, 'wipe'),
                child: Text(l10n.wipeDataConfirmBtn),
              ),
            ],
          ),
        ),
      ],
    );
    if (choice == null || choice == 'cancel') return;
    if (choice == 'export') {
      // Экспорт и удаление одним действием. Удаляем ТОЛЬКО если файл
      // действительно сохранён: отмена диалога сохранения или ошибка записи
      // означают, что копии нет, и стирать данные в этот момент нельзя.
      if (!context.mounted) return;
      final saved = await _export(context, ref);
      if (!saved) return;
    }
    // Между открытием диалога и этим моментом экран мог быть закрыт.
    if (!context.mounted) return;
    await _performWipe(context, ref);
  }

  /// Собственно удаление + сообщение о результате. Вынесено отдельно, потому
  /// что путей сюда два: «удалить всё» сразу и «экспорт и удаление».
  Future<void> _performWipe(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    try {
      await ref.read(backupServiceProvider).wipeEverything();
      if (!context.mounted) return;
      await showFancyDialog<void>(
        context: context,
        icon: Icons.check_circle_outline,
        iconColor: AppColors.success,
        title: l10n.wipeDataDoneTitle,
        content: l10n.wipeDataDoneContent,
        actions: (ctx) => [
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.ok),
          ),
        ],
      );
    } catch (e) {
      if (!context.mounted) return;
      showFancyToast(context,
          message: l10n.wipeDataFailedToast('$e'), tone: ToastTone.error);
    }
  }

  Future<void> _import(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final confirmed = await showFancyDialog<bool>(
      context: context,
      icon: Icons.warning_amber_rounded,
      iconColor: AppColors.warning,
      title: l10n.importConfirmTitle,
      content: l10n.importConfirmContent,
      actions: (ctx) => [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(l10n.cancel),
        ),
        const SizedBox(width: 8),
        FilledButton(
          autofocus: true,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(l10n.replace),
        ),
      ],
    );
    if (confirmed != true) return;
    try {
      final done = await ref.read(backupServiceProvider).importFromFile();
      if (!done || !context.mounted) return;
      await showFancyDialog<void>(
        context: context,
        icon: Icons.cloud_done_rounded,
        iconColor: AppColors.success,
        title: l10n.importDoneTitle,
        content: l10n.importDoneContent,
        actions: (ctx) => [
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.ok),
          ),
        ],
      );
    } on FormatException catch (e) {
      if (!context.mounted) return;
      showFancyToast(context, message: e.message, tone: ToastTone.error);
    } catch (e) {
      if (!context.mounted) return;
      showFancyToast(context,
          message: l10n.importFailedToast('$e'), tone: ToastTone.error);
    }
  }

  Future<int?> _pickTime(BuildContext context, int minutes,
      {String? help}) async {
    final res = await showTimePicker(
      context: context,
      helpText: help,
      initialTime: TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60),
    );
    return res == null ? null : res.hour * 60 + res.minute;
  }

  static String _fmt(int m) =>
      '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
}

// Сегментный переключатель «пилюля» вынесен в widgets/pill_toggle.dart.
