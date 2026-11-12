import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/appearance.dart';
import '../../../l10n/app_localizations.dart';
import '../../../l10n/l10n_extensions.dart';
import '../../../widgets/fancy_dialog.dart';
import '../../../widgets/fancy_toast.dart';
import '../../../widgets/pill_toggle.dart';
import '../core/secret_store.dart';
import '../webhooks/webhooks.dart';
import 'section_parts.dart';

String eventLabel(WebhookEvent e, AppLocalizations l10n) => switch (e) {
      WebhookEvent.taskCompleted => l10n.hookEventTaskCompleted,
      WebhookEvent.dayClosed => l10n.hookEventDayClosed,
      WebhookEvent.goalAchieved => l10n.hookEventGoalAchieved,
      WebhookEvent.ping => l10n.hookEventPing,
    };

/// Вебхуки: адреса, которые человек ввёл сам. Без адресов — ни одного
/// запроса наружу.
class WebhooksSection extends ConsumerWidget {
  const WebhooksSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final endpoints = ref.watch(webhookEndpointsProvider);
    final log = ref.watch(webhookDeliveriesProvider).reversed.take(20).toList();
    final service = ref.read(webhookServiceProvider);
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    final time = DateFormat('d MMM, HH:mm', locale);
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.7);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(l10n.hookSectionTitle),
        SectionCard(
          children: [
            for (final e in endpoints) ...[
              ListTile(
                leading: Icon(
                  e.enabled ? Icons.webhook_rounded : Icons.link_off_rounded,
                  color: e.enabled ? null : muted,
                ),
                title: Text(
                  e.url,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  e.enabled
                      ? e.events.map((x) => eventLabel(x, l10n)).join(', ')
                      : l10n.hookDisabledGone,
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => editEndpoint(context, ref, e),
              ),
              tileDivider,
            ],
            ListTile(
              leading: const Icon(Icons.add_rounded),
              title: TileTitle(l10n.hookAdd),
              onTap: () => editEndpoint(context, ref, null),
            ),
          ],
        ),
        SectionNote(l10n.hookNote),
        if (endpoints.isNotEmpty) ...[
          SectionTitle(l10n.hookLogTitle),
          SectionCard(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.hookRetention),
                    const SizedBox(height: 8),
                    PillToggle<int>(
                      selected: service.retentionDays,
                      segments: [
                        (7, l10n.hookDays(7)),
                        (30, l10n.hookDays(30)),
                      ],
                      onChanged: service.setRetentionDays,
                    ),
                  ],
                ),
              ),
              if (log.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: NotebookEmptyState(
                    text: l10n.hookLogEmpty,
                    icon: Icons.outbox_outlined,
                  ),
                )
              else ...[
                for (final d in log)
                  ListTile(
                    dense: true,
                    leading: Icon(
                      switch (d.status) {
                        DeliveryStatus.delivered => Icons.check_circle_outline,
                        DeliveryStatus.pending => Icons.schedule_rounded,
                        DeliveryStatus.failed => Icons.error_outline_rounded,
                      },
                      size: 20,
                      color: d.status == DeliveryStatus.delivered
                          ? AppColors.success
                          : muted,
                    ),
                    title: Text(eventLabel(d.type, l10n)),
                    subtitle: Text(
                      [
                        time.format(d.createdAt),
                        if (d.lastCode != null)
                          d.lastCode == 0
                              ? l10n.hookNoAnswer
                              : 'HTTP ${d.lastCode}',
                        if (d.status == DeliveryStatus.pending)
                          l10n.hookRetryAt(DateFormat.Hm(locale).format(d.nextAt)),
                      ].join(' · '),
                    ),
                    trailing: d.status == DeliveryStatus.pending
                        ? null
                        : IconButton(
                            tooltip: l10n.hookResend,
                            icon: const Icon(Icons.replay_rounded, size: 20),
                            onPressed: () => service.resend(d.id),
                          ),
                  ),
                tileDivider,
                ListTile(
                  leading: const Icon(Icons.delete_sweep_outlined),
                  title: Text(l10n.hookClearLog),
                  onTap: service.clearLog,
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }
}

/// Добавить или изменить адрес: URL, события, секрет, «Проверить», удалить.
Future<void> editEndpoint(
  BuildContext context,
  WidgetRef ref,
  WebhookEndpoint? existing,
) async {
  await Navigator.of(context).push<void>(
    MaterialPageRoute(builder: (_) => _EndpointScreen(existing: existing)),
  );
}

class _EndpointScreen extends ConsumerStatefulWidget {
  const _EndpointScreen({this.existing});
  final WebhookEndpoint? existing;

  @override
  ConsumerState<_EndpointScreen> createState() => _EndpointScreenState();
}

class _EndpointScreenState extends ConsumerState<_EndpointScreen> {
  late final _url = TextEditingController(text: widget.existing?.url ?? '');
  late final Set<WebhookEvent> _events = {
    ...?widget.existing?.events,
    if (widget.existing == null) ...[
      WebhookEvent.taskCompleted,
      WebhookEvent.dayClosed,
      WebhookEvent.goalAchieved,
    ],
  };
  late final String _id = widget.existing?.id ??
      'wh-${DateTime.now().microsecondsSinceEpoch}';
  String? _secret;
  bool _showSecret = false;
  bool _testing = false;

  @override
  void initState() {
    super.initState();
    ref.read(secretStoreProvider).webhookSecret(_id).then((s) {
      if (mounted) setState(() => _secret = s);
    });
  }

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  /// null — адрес принят; иначе — что не так.
  Future<bool> _validUrl() async {
    final l10n = context.l10n;
    final uri = Uri.tryParse(_url.text.trim());
    if (uri == null || !uri.hasAuthority ||
        !(uri.scheme == 'https' || uri.scheme == 'http')) {
      showFancyToast(context, message: l10n.hookBadUrl, tone: ToastTone.error);
      return false;
    }
    if (uri.scheme == 'https') return true;
    final ok = await showFancyDialog<bool>(
      context: context,
      icon: Icons.lock_open_rounded,
      iconColor: AppColors.warning,
      title: l10n.calHttpTitle,
      content: l10n.hookHttpBody,
      actions: (ctx) => [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(l10n.hookHttpContinue),
        ),
      ],
    );
    return ok == true;
  }

  Future<bool> _save() async {
    if (!await _validUrl()) return false;
    final service = ref.read(webhookServiceProvider);
    final ep = WebhookEndpoint(
      id: _id,
      url: _url.text.trim(),
      events: _events,
    );
    final list = service.endpoints;
    final idx = list.indexWhere((e) => e.id == _id);
    if (idx == -1) {
      list.add(ep);
    } else {
      list[idx] = ep;
    }
    await service.saveEndpoints(list);
    return true;
  }

  Future<void> _test() async {
    final l10n = context.l10n;
    if (!await _save()) return;
    setState(() => _testing = true);
    final ok = await ref.read(webhookServiceProvider).test(_id);
    if (!mounted) return;
    setState(() => _testing = false);
    showFancyToast(
      context,
      message: ok ? l10n.hookTestOk : l10n.hookTestFailed,
      tone: ok ? ToastTone.success : ToastTone.error,
    );
  }

  Future<void> _rotate() async {
    final l10n = context.l10n;
    final ok = await showFancyDialog<bool>(
      context: context,
      icon: Icons.key_off_outlined,
      iconColor: AppColors.danger,
      title: l10n.hookRotateTitle,
      content: l10n.hookRotateBody,
      actions: (ctx) => [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(l10n.taskerRotateConfirm),
        ),
      ],
    );
    if (ok != true) return;
    final s = await ref.read(secretStoreProvider).rotateWebhookSecret(_id);
    if (mounted) setState(() => _secret = s);
  }

  Future<void> _delete() async {
    final l10n = context.l10n;
    final ok = await showFancyDialog<bool>(
      context: context,
      icon: Icons.delete_outline_rounded,
      iconColor: AppColors.danger,
      title: l10n.hookDeleteTitle,
      content: l10n.hookDeleteBody,
      actions: (ctx) => [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(l10n.delete),
        ),
      ],
    );
    if (ok != true) return;
    final service = ref.read(webhookServiceProvider);
    await service.saveEndpoints([
      for (final e in service.endpoints)
        if (e.id != _id) e,
    ]);
    await ref.read(secretStoreProvider).deleteWebhookSecret(_id);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final secret = _secret;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? l10n.hookAdd : l10n.hookEdit),
        actions: [
          if (widget.existing != null)
            IconButton(
              tooltip: l10n.delete,
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: _delete,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _url,
              autofocus: widget.existing == null,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                labelText: l10n.hookUrlLabel,
                hintText: 'https://…',
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          SectionTitle(l10n.hookEventsTitle),
          SectionCard(
            children: [
              for (final e in [
                WebhookEvent.taskCompleted,
                WebhookEvent.dayClosed,
                WebhookEvent.goalAchieved,
              ])
                CheckboxListTile(
                  value: _events.contains(e),
                  title: Text(eventLabel(e, l10n)),
                  onChanged: (v) => setState(
                    () => v == true ? _events.add(e) : _events.remove(e),
                  ),
                ),
            ],
          ),
          SectionTitle(l10n.hookSecretTitle),
          SectionCard(
            children: [
              ListTile(
                title: Text(
                  secret == null ? '…' : (_showSecret ? secret : '•' * 12),
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
                      onPressed: () => setState(() => _showSecret = !_showSecret),
                      icon: Icon(
                        _showSecret
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        size: 18,
                      ),
                      label: Text(_showSecret ? l10n.taskerHide : l10n.taskerShow),
                    ),
                    TextButton.icon(
                      onPressed: secret == null
                          ? null
                          : () => copyWithToast(context, secret),
                      icon: const Icon(Icons.copy_rounded, size: 18),
                      label: Text(l10n.copyAction),
                    ),
                    TextButton.icon(
                      onPressed: _rotate,
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
            ],
          ),
          SectionNote(l10n.hookSecretNote),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Wrap(
              spacing: 12,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              children: [
                OutlinedButton.icon(
                  onPressed: _testing ? null : _test,
                  icon: _testing
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send_rounded, size: 18),
                  label: Text(l10n.hookTest),
                ),
                FilledButton(
                  onPressed: () async {
                    if (await _save() && context.mounted) {
                      Navigator.of(context).pop();
                    }
                  },
                  child: Text(l10n.saveBtn),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
