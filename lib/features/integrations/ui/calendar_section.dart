import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../../core/theme/app_colors.dart';
import '../../../data/repositories/backlog_repository.dart';
import '../../../data/repositories/recurrence_repository.dart';
import '../../../data/repositories/schedule_repository.dart';
import '../../../data/repositories/task_repository.dart';
import '../../../data/sources/local/local_storage.dart';
import '../../../l10n/l10n_extensions.dart';
import '../../../widgets/fancy_dialog.dart';
import '../../../widgets/fancy_toast.dart';
import '../export/full_export.dart';
import '../ics/ics_export.dart';
import '../ics/ics_parser.dart';
import '../ics/ics_subscription.dart';
import '../ics/ics_writer.dart';
import '../import/formats/google_tasks.dart';
import '../import/formats/ticktick.dart';
import '../import/formats/todoist.dart';
import '../import/import_plan.dart';
import '../import/import_preview_screen.dart';
import '../import/imported_task.dart';
import '../../../services/web_bits.dart';
import 'section_parts.dart';

/// Календари (.ics). Переезд из других приложений и полный экспорт —
/// в Настройки → Данные (методы здесь общие). Всё — файлом; ссылка на
/// календарь — ровно один запрос по нажатию, на адрес, который ввёл сам
/// человек.
class CalendarSection extends ConsumerWidget {
  const CalendarSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final sub = ref.watch(icsSubscriptionProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(l10n.calSectionTitle),
        SectionCard(
          children: [
            ListTile(
              leading: const Icon(Icons.event_note_outlined),
              title: TileTitle(l10n.calImportFile),
              subtitle: Text(l10n.calImportFileSubtitle),
              onTap: () => importFile(context, ref),
            ),
            tileDivider,
            ListTile(
              leading: const Icon(Icons.link_rounded),
              title: TileTitle(l10n.calImportLink),
              subtitle: Text(sub?.url ?? l10n.calImportLinkSubtitle),
              onTap: () => _importLink(context, ref),
            ),
            if (sub != null)
              SwitchListTile(
                secondary: const SizedBox(width: 24),
                title: Text(l10n.calAutoTitle),
                subtitle: Text(l10n.calAutoSubtitle),
                value: sub.auto,
                onChanged: (v) => ref
                    .read(icsSubscriptionProvider.notifier)
                    .set(sub.copyWith(auto: v)),
              ),
            if (sub != null)
              ListTile(
                leading: const Icon(Icons.refresh_rounded),
                title: TileTitle(l10n.calRefreshNow),
                onTap: () => _refreshNow(context, ref),
              ),
            tileDivider,
            ListTile(
              leading: const Icon(Icons.ios_share_rounded),
              title: TileTitle(l10n.calExport),
              subtitle: Text(l10n.calExportSubtitle),
              onTap: () => _export(context, ref),
            ),
          ],
        ),
        SectionNote(l10n.calNote),
      ],
    );
  }

  /// «Обновить сейчас»: тот же путь, что ежедневное обновление, без ожидания.
  static Future<void> _refreshNow(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final n = await refreshIcsSubscription(
      ProviderScope.containerOf(context),
      force: true,
    );
    if (!context.mounted) return;
    showFancyToast(
      context,
      message: n == null
          ? l10n.calLinkFailed
          : n == 0
              ? l10n.calRefreshNothing
              : l10n.importDoneToast(n),
      tone: n == null ? ToastTone.error : ToastTone.success,
    );
  }

  /// Импорт .ics из файла — отсюда и из пустого «Расписания».
  static Future<void> importFile(BuildContext context, WidgetRef ref) async {
    final text = await _pickText(context, const ['ics']);
    if (text == null || !context.mounted) return;
    await _previewIcs(context, ref, text);
  }

  static Future<void> _previewIcs(
    BuildContext context,
    WidgetRef ref,
    String text,
  ) async {
    final cal = parseIcs(
      text,
      local: tz.local,
      ru: Localizations.localeOf(context).languageCode == 'ru',
    );
    final seen = IcsSeen(ref.read(localStorageProvider));
    final plan = planIcsImport(
      cal,
      schedule: ref.read(scheduleRepositoryProvider),
      now: DateTime.now(),
      seen: seen,
    );
    await seen.save();
    if (!context.mounted) return;
    // Поверх всего приложения: из пустого «Расписания» (внутри вкладок)
    // иначе под экраном оставалась бы нижняя панель.
    await Navigator.of(context, rootNavigator: true).push<int>(
      MaterialPageRoute(
        builder: (_) => ImportPreviewScreen(
          title: context.l10n.calPreviewTitle,
          entries: plan,
          warningsCount: cal.warnings.length,
          notes: cal.warnings,
        ),
      ),
    );
  }

  static Future<void> _importLink(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final ctrl = TextEditingController(
      text: ref.read(icsSubscriptionProvider)?.url ?? '',
    );
    final ok = await showFancyDialog<bool>(
      context: context,
      icon: Icons.link_rounded,
      iconColor: AppColors.clay,
      title: l10n.calImportLink,
      autofocusEsc: false,
      contentBuilder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.calLinkHint, textAlign: TextAlign.center),
          const SizedBox(height: 10),
          TextField(
            controller: ctrl,
            autofocus: true,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'https://…/calendar.ics',
            ),
            onSubmitted: (_) => Navigator.pop(ctx, true),
          ),
        ],
      ),
      actions: (ctx) => [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(l10n.calLinkLoad),
        ),
      ],
    );
    final url = ctrl.text.trim().replaceFirst(RegExp('^webcal://'), 'https://');
    ctrl.dispose();
    if (ok != true || !context.mounted) return;
    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.scheme == 'https' || uri.scheme == 'http')) {
      showFancyToast(context, message: l10n.calLinkBad, tone: ToastTone.error);
      return;
    }
    if (uri.scheme == 'http' && !await _confirmHttp(context)) return;
    String text;
    try {
      text = await fetchIcs(url);
    } catch (_) {
      if (context.mounted) {
        showFancyToast(
          context,
          message: l10n.calLinkFailed,
          tone: ToastTone.error,
        );
      }
      return;
    }
    final prev = ref.read(icsSubscriptionProvider);
    await ref.read(icsSubscriptionProvider.notifier).set(
          IcsSubscription(
            url: url,
            auto: prev?.url == url && prev!.auto,
            lastAt: DateTime.now(),
          ),
        );
    if (context.mounted) await _previewIcs(context, ref, text);
  }

  static Future<bool> _confirmHttp(BuildContext context) async {
    final l10n = context.l10n;
    final ok = await showFancyDialog<bool>(
      context: context,
      icon: Icons.lock_open_rounded,
      iconColor: AppColors.warning,
      title: l10n.calHttpTitle,
      content: l10n.calHttpBody,
      actions: (ctx) => [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(l10n.calHttpContinue),
        ),
      ],
    );
    return ok == true;
  }

  static Future<void> _export(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final now = DateTime.now();
    final text = writeIcs(
      buildIcsExport(
        schedule: ref.read(scheduleRepositoryProvider).all,
        rules: ref.read(recurrenceRepositoryProvider).all,
        tasks: ref.read(taskRepositoryProvider).allTasks,
        now: now,
      ),
      zone: tz.local,
      now: now,
    );
    final saved = await _saveText(context, 'enitor.ics', text, 'ics');
    if (saved && context.mounted) {
      showFancyToast(context, message: l10n.calExportedToast);
    }
  }

  static Future<void> fullExport(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final info = await PackageInfo.fromPlatform();
    if (!context.mounted) return;
    final now = DateTime.now();
    final text = buildFullExport(
      ref.read(localStorageProvider),
      now: now,
      appVersion: info.version,
    );
    final stamp = '${now.year}${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}';
    final saved =
        await _saveText(context, 'enitor-export-$stamp.json', text, 'json');
    if (saved && context.mounted) {
      showFancyToast(context, message: l10n.fullExportDone);
    }
  }

  static Future<void> importApp(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final source = await showFancyDialog<ImportSource>(
      context: context,
      icon: Icons.move_down_rounded,
      iconColor: AppColors.clay,
      title: l10n.appImportTitle,
      contentBuilder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (s, name, hint) in [
            (ImportSource.todoist, 'Todoist', l10n.appImportTodoistHint),
            (
              ImportSource.googleTasks,
              'Google Tasks',
              l10n.appImportGoogleHint
            ),
            (ImportSource.tickTick, 'TickTick', l10n.appImportTickTickHint),
          ])
            ListTile(
              title: Text(name),
              subtitle: Text(hint),
              onTap: () => Navigator.pop(ctx, s),
            ),
        ],
      ),
      actions: (ctx) => [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(l10n.cancel),
        ),
      ],
    );
    if (source == null || !context.mounted) return;
    var fileName = '';
    final text = await _pickText(
      context,
      source == ImportSource.googleTasks ? const ['json'] : const ['csv'],
      onName: (n) => fileName = n,
    );
    if (text == null || !context.mounted) return;
    final result = switch (source) {
      // Todoist выгружает по проекту на файл, а имя проекта есть только в
      // имени файла.
      ImportSource.todoist => parseTodoistCsv(text, project: fileName),
      ImportSource.googleTasks => parseGoogleTasksJson(text),
      ImportSource.tickTick => parseTickTickCsv(text),
    };
    final plan = planTaskImport(
      result,
      tasks: ref.read(taskRepositoryProvider),
      rules: ref.read(recurrenceRepositoryProvider),
      backlog: ref.read(backlogRepositoryProvider),
      now: DateTime.now(),
    );
    await Navigator.of(context, rootNavigator: true).push<int>(
      MaterialPageRoute(
        builder: (_) => ImportPreviewScreen(
          title: l10n.appImportPreviewTitle,
          entries: plan,
          warningsCount: result.warnings.length,
        ),
      ),
    );
  }

  /// Текст выбранного файла; null — отмена. Нечитаемый — тост.
  static Future<String?> _pickText(
    BuildContext context,
    List<String> ext, {
    void Function(String name)? onName,
  }) async {
    final l10n = context.l10n;
    try {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ext,
        withData: true,
      );
      if (res == null || res.files.isEmpty) return null;
      final f = res.files.first;
      onName?.call(f.name);
      final bytes = f.bytes ?? await File(f.path!).readAsBytes();
      return utf8.decode(bytes, allowMalformed: true);
    } catch (_) {
      if (context.mounted) {
        showFancyToast(
          context,
          message: l10n.importFileUnreadable,
          tone: ToastTone.error,
        );
      }
      return null;
    }
  }

  /// Сохраняет текст в файл через системный диалог (как бэкап).
  static Future<bool> _saveText(
    BuildContext context,
    String name,
    String text,
    String ext,
  ) async {
    if (kIsWeb) {
      downloadText(name, text, 'application/octet-stream');
      return true;
    }
    final bytes = Uint8List.fromList(utf8.encode(text));
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      final path = await FilePicker.platform.saveFile(
        fileName: name,
        type: FileType.custom,
        allowedExtensions: [ext],
        bytes: bytes,
      );
      return path != null;
    }
    final path = await FilePicker.platform.saveFile(
      fileName: name,
      type: FileType.custom,
      allowedExtensions: [ext],
    );
    if (path == null) return false;
    final fixed = path.toLowerCase().endsWith('.$ext') ? path : '$path.$ext';
    await File(fixed).writeAsBytes(bytes);
    return true;
  }
}
