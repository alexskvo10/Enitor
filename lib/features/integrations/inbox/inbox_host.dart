import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/models/schedule_item.dart';
import '../../../data/models/task.dart';
import '../../../l10n/app_localizations.dart';
import '../../../l10n/l10n_extensions.dart';
import '../../../services/notification_controller.dart';
import '../../../widgets/fancy_toast.dart';
import '../../../widgets/tag_mini.dart';
import '../../today/today_screen.dart';
import '../core/command_handler.dart';
import '../core/integration_command.dart';
import '../sync/lan/lan_service.dart';
import 'command_inbox.dart';

/// Разбирает [CommandInbox] по одному: анкета «Добавить?», переход на экран
/// или тост. Стоит в корневом каркасе — там есть Navigator и тосты.
class InboxHost extends ConsumerStatefulWidget {
  const InboxHost({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<InboxHost> createState() => _InboxHostState();
}

class _InboxHostState extends ConsumerState<InboxHost> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // Команда могла прийти раньше, чем построилось дерево (холодный старт).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _drain();
      _openSyncForPairLink();
    });
  }

  /// Ссылка `enitor://pair…` из QR-кода: её разбирает экран синхронизации —
  /// открыть его, если ссылку никто не забрал. Открытый экран забирает её
  /// сразу и показывает окно «Подключиться?»; второй экран поверх спрятал
  /// бы это окно под собой. Поэтому — через кадр и только если ссылка ещё
  /// лежит.
  void _openSyncForPairLink() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || ref.read(lanPairLinkProvider) == null) return;
      GoRouter.of(context).push('/settings/sync');
    });
    // Ссылка могла прийти, когда кадров не ждут: колбэк ждал бы следующего.
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> _drain() async {
    if (_busy) return;
    _busy = true;
    try {
      while (mounted) {
        final items = ref.read(commandInboxProvider);
        if (items.isEmpty) break;
        await _show(items.first);
        ref.read(commandInboxProvider.notifier).pop();
      }
    } finally {
      _busy = false;
    }
  }

  Future<void> _show(InboxItem item) async {
    final l10n = context.l10n;
    switch (item) {
      case InboxError(:final error, :final source):
        showFancyToast(
          context,
          message: inboxErrorText(error, source, l10n),
          tone: ToastTone.error,
        );
      case InboxCommand(command: final OpenScreen c):
        openTarget(context, ref, c.target);
      case InboxCommand(command: final AddTask c):
        final saved = await showPrefilledTaskSheet(
          context,
          template: _taskFrom(c),
          header: ConfirmHeader(command: c),
        );
        if (saved && mounted) _addedToast(l10n);
      case InboxCommand(command: final AddScheduleItem c):
        final saved = await showPrefilledScheduleSheet(
          context,
          // Напоминание — как у пункта, созданного вручную: по настройке.
          template: _scheduleFrom(
            c,
            ref.read(notificationControllerProvider).prefs.scheduleLeadMinutes,
          ),
          header: ConfirmHeader(command: c),
        );
        if (saved && mounted) _addedToast(l10n);
      case InboxCommand():
        // Чтение и отметки недоверенным входам не разрешены — сюда они не
        // попадают (IntegrationGateway отклоняет их раньше).
        break;
    }
  }

  /// «Добавлено» — только после последней анкеты очереди: следующая анкета
  /// сама по себе ответ «сохранено», а тост поверх неё закрыл бы её кнопку.
  void _addedToast(AppLocalizations l10n) {
    if (ref.read(commandInboxProvider).length > 1) return;
    showFancyToast(context, message: l10n.inboxAddedToast);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(commandInboxProvider, (_, next) {
      if (next.isNotEmpty) _drain();
    });
    ref.listen(lanPairLinkProvider, (_, next) {
      if (next != null) _openSyncForPairLink();
    });
    return widget.child;
  }
}

Task _taskFrom(AddTask c) {
  final now = DateTime.now();
  return Task(
    id: '',
    title: c.title,
    description: c.description,
    date: c.date,
    createdAt: now,
    updatedAt: now,
    startMinutes: c.startMinutes,
    endMinutes: c.endMinutes,
    priority: c.priority,
    tags: c.tags,
  );
}

ScheduleItem _scheduleFrom(AddScheduleItem c, int? reminder) {
  final now = DateTime.now();
  return ScheduleItem(
    id: '',
    title: c.title,
    date: c.date,
    startMinutes: c.startMinutes,
    endMinutes: c.endMinutes,
    location: c.location,
    note: c.note,
    reminderMinutes: reminder,
    createdAt: now,
    updatedAt: now,
  );
}

/// Переход по `enitor://open?screen=…`.
void openTarget(BuildContext context, WidgetRef ref, OpenTarget t) {
  switch (t) {
    case OpenTarget.today:
      ref.read(todayTabRequestProvider.notifier).state = 0;
      context.go('/today');
    case OpenTarget.schedule:
      ref.read(todayTabRequestProvider.notifier).state = 1;
      context.go('/today');
    case OpenTarget.goals:
      context.go('/goals');
    case OpenTarget.settings:
      context.push('/settings');
    case OpenTarget.integrations:
      context.push('/settings/integrations');
  }
}

String sourceLabel(CommandSource s, AppLocalizations l10n) => switch (s) {
      CommandSource.link => l10n.integrationsSourceLink,
      CommandSource.share => l10n.integrationsSourceShare,
      CommandSource.tasker => l10n.integrationsSourceTasker,
      CommandSource.cli => l10n.integrationsSourceCli,
      CommandSource.mcp => l10n.integrationsSourceMcp,
      CommandSource.widget => l10n.integrationsSourceWidget,
    };

/// Тост для ссылки, которую не удалось принять. Для ссылки — «проверь
/// адрес», для «Поделиться» — «нечего добавить»; запрет — куда идти.
String inboxErrorText(
  CommandError e,
  CommandSource source,
  AppLocalizations l10n,
) {
  if (e.code == CommandErrorCode.forbidden) {
    return source == CommandSource.share
        ? l10n.inboxShareOff
        : l10n.inboxLinksOff;
  }
  if (source == CommandSource.share) return l10n.inboxShareEmpty;
  if (e.field == 'link' || e.code == CommandErrorCode.unknownCommand) {
    return l10n.inboxLinkUnknown;
  }
  return '${l10n.inboxLinkInvalid} ${commandErrorText(e, l10n)}';
}

/// Шапка анкеты, открытой из ссылки или «Поделиться»: откуда пришло,
/// какие поля пропущены и сколько ещё ждёт своей очереди. Пометки — нейтральные
/// пилюли, без акцента Clay: это служебная информация, а не действие.
class ConfirmHeader extends ConsumerWidget {
  const ConfirmHeader({super.key, required this.command});
  final IntegrationCommand command;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    // Сама эта анкета — первый элемент очереди.
    final waiting = ref.watch(commandInboxProvider).length - 1;
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.65);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              TagMini(
                label: command.source == CommandSource.share
                    ? l10n.inboxFromShare
                    : l10n.inboxFromLink,
                hash: false,
              ),
              if (waiting > 0)
                Text(
                  l10n.inboxMoreWaiting(waiting),
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
            ],
          ),
          if (command.warnings.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              l10n.inboxUnknownFields(command.warnings.join(', ')),
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
          ],
        ],
      ),
    );
  }
}
