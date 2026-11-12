import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../l10n/l10n_extensions.dart';
import '../../../widgets/fancy_dialog.dart';
import '../../../widgets/fancy_toast.dart';
import '../core/integration_command.dart';
import '../core/integration_settings.dart';
import '../core/secret_store.dart';
import 'section_parts.dart';

/// Ключ Tasker. FutureProvider: секрет читается из защищённого хранилища
/// асинхронно и создаётся при первом обращении.
final taskerKeyProvider =
    FutureProvider<String>((ref) => ref.read(secretStoreProvider).taskerKey());

/// Пример действия Tasker «Send Intent» — копируется одним нажатием.
String taskerExample(String key) => '''Action: dev.enitor.app.COMMAND
Package: dev.enitor.app
Target: Broadcast Receiver
Extra: key:$key
Extra: command:{"command":"add_task","args":{"title":"%par1"}}''';

const _readExample = '''Extra: command:{"command":"list_today"}
Extra: reply_package:net.dinglisch.android.taskerm
— Event → Intent Received → Action: dev.enitor.app.REPLY, %reply''';

/// Android: Tasker, Automate и т.п. Ключ скрыт, пока его не попросили
/// показать; перевыпуск — с подтверждением, старый ключ сразу перестаёт
/// работать.
class TaskerSection extends ConsumerStatefulWidget {
  const TaskerSection({super.key});

  @override
  ConsumerState<TaskerSection> createState() => _TaskerSectionState();
}

class _TaskerSectionState extends ConsumerState<TaskerSection> {
  bool _shown = false;

  Future<void> _rotate() async {
    final l10n = context.l10n;
    final ok = await showFancyDialog<bool>(
      context: context,
      icon: Icons.key_off_outlined,
      iconColor: AppColors.danger,
      title: l10n.taskerRotateTitle,
      content: l10n.taskerRotateBody,
      actions: (ctx) => [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          autofocus: true,
          style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(l10n.taskerRotateConfirm),
        ),
      ],
    );
    if (ok != true) return;
    await ref.read(secretStoreProvider).rotateTaskerKey();
    ref.invalidate(taskerKeyProvider);
    if (mounted) showFancyToast(context, message: l10n.taskerRotatedToast);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final settings = ref.watch(integrationSettingsProvider);
    final enabled = settings.of(CommandSource.tasker).add ||
        settings.of(CommandSource.tasker).read;
    final key = ref.watch(taskerKeyProvider).valueOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(l10n.taskerTitle),
        SectionCard(
          children: [
            ListTile(
              leading: const Icon(Icons.key_rounded),
              title: TileTitle(l10n.taskerKeyTitle),
              subtitle: Text(
                key == null ? '…' : (_shown ? key : '•' * 12),
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontFamily: 'monospace',
                  fontFamilyFallback: const ['Consolas', 'Courier New'],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Wrap(
                spacing: 4,
                children: [
                  TextButton.icon(
                    onPressed: key == null
                        ? null
                        : () => setState(() => _shown = !_shown),
                    icon: Icon(
                      _shown
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size: 18,
                    ),
                    label: Text(_shown ? l10n.taskerHide : l10n.taskerShow),
                  ),
                  TextButton.icon(
                    onPressed:
                        key == null ? null : () => copyWithToast(context, key),
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    label: Text(l10n.copyAction),
                  ),
                  TextButton.icon(
                    onPressed: _rotate,
                    // Красная — только иконка: красный текст на бумаге не
                    // дотягивает до контраста 4.5:1.
                    icon: const Icon(
                      Icons.autorenew_rounded,
                      size: 18,
                      color: AppColors.danger,
                    ),
                    label: Text(l10n.taskerRotate),
                  ),
                ],
              ),
            ),
            tileDivider,
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Text(l10n.taskerExampleTitle,
                  style: theme.textTheme.titleSmall,),
            ),
            if (key != null)
              CopyBlock(
                text: taskerExample(key),
                label: l10n.taskerCopyExample,
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Text(l10n.taskerReadExampleTitle,
                  style: theme.textTheme.titleSmall,),
            ),
            const CopyBlock(text: _readExample),
            tileDivider,
            SwitchListTile(
              secondary: const Icon(Icons.notifications_none_rounded),
              title: TileTitle(l10n.taskerTraceTitle),
              subtitle: Text(l10n.taskerTraceSubtitle),
              value: settings.backgroundTrace,
              onChanged: (v) => ref
                  .read(integrationSettingsProvider.notifier)
                  .update(settings.copyWith(backgroundTrace: v)),
            ),
            tileDivider,
            ListTile(
              leading: const Icon(Icons.reply_rounded),
              title: TileTitle(l10n.taskerReplyTitle),
              subtitle: Text(
                settings.replyPackages.isEmpty
                    ? l10n.taskerReplyNone
                    : settings.replyPackages.join('\n'),
              ),
              trailing: const Icon(Icons.edit_outlined),
              onTap: () => _editPackages(settings),
            ),
          ],
        ),
        SectionNote(
          enabled ? l10n.taskerNote : l10n.taskerNoteDisabled,
        ),
      ],
    );
  }

  /// Список пакетов, которым можно отвечать: по одному в строке.
  Future<void> _editPackages(IntegrationSettings settings) async {
    final l10n = context.l10n;
    final ctrl = TextEditingController(text: settings.replyPackages.join('\n'));
    final saved = await showFancyDialog<bool>(
      context: context,
      icon: Icons.reply_rounded,
      iconColor: AppColors.clay,
      title: l10n.taskerReplyTitle,
      autofocusEsc: false,
      contentBuilder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.taskerReplyHint, textAlign: TextAlign.center),
          const SizedBox(height: 10),
          TextField(
            controller: ctrl,
            autofocus: true,
            minLines: 2,
            maxLines: 6,
            decoration: const InputDecoration(border: OutlineInputBorder()),
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
          child: Text(l10n.saveBtn),
        ),
      ],
    );
    final text = ctrl.text;
    ctrl.dispose();
    if (saved != true) return;
    // Имя пакета Android: латиница, цифры, «_» и точки, минимум две части.
    final valid = RegExp(r'^[a-zA-Z][\w]*(\.[a-zA-Z][\w]*)+$');
    final packages = {
      for (final line in text.split('\n'))
        if (valid.hasMatch(line.trim())) line.trim(),
    }.toList();
    await ref
        .read(integrationSettingsProvider.notifier)
        .update(settings.copyWith(replyPackages: packages));
  }
}
