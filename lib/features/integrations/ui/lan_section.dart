import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../l10n/app_localizations.dart';
import '../../../l10n/l10n_extensions.dart';
import '../../../widgets/fancy_dialog.dart';
import '../../../widgets/fancy_toast.dart';
import '../sync/lan/lan_crypto.dart';
import '../sync/lan/lan_group.dart' show LanMember;
import '../sync/lan/lan_node.dart';
import '../sync/lan/lan_service.dart';
import 'section_parts.dart';
import 'server_section.dart' show syncDeviceIcon, syncDeviceTitle;

/// Текст ошибки знакомства или обмена по коду [LanException].
String lanErrorText(AppLocalizations l10n, String code) => switch (code) {
      'not_found' || 'no_pairing' => l10n.lanErrNotFound,
      'bad_code' => l10n.lanErrBadCode,
      'declined' => l10n.lanErrDeclined,
      'connect' => l10n.lanErrConnect,
      'timeout' => l10n.lanErrTimeout,
      'pin' => l10n.lanErrPin,
      'unauthorized' => l10n.lanErrUnauthorized,
      _ => l10n.lanErrUnknown,
    };

/// Настройки → Синхронизация → «Устройства в сети»: знакомство по коду,
/// группа, обмен.
class LanSection extends ConsumerStatefulWidget {
  const LanSection({super.key});

  @override
  ConsumerState<LanSection> createState() => _LanSectionState();
}

class _LanSectionState extends ConsumerState<LanSection> {
  bool _syncing = false;

  // В dispose ref уже нельзя трогать — служба запоминается здесь.
  late final LanSyncService _service = ref.read(lanSyncServiceProvider);

  void _revokedToast() {
    if (mounted) {
      showFancyToast(context, message: context.l10n.lanRevokedToast);
    }
  }

  @override
  void initState() {
    super.initState();
    _service.onRevoked = _revokedToast;
    // Ссылку из QR-кода могли открыть до того, как построился экран.
    WidgetsBinding.instance.addPostFrameCallback((_) => _takeLink());
  }

  @override
  void dispose() {
    if (_service.onRevoked == _revokedToast) _service.onRevoked = null;
    super.dispose();
  }

  void _takeLink() {
    final uri = ref.read(lanPairLinkProvider);
    if (uri == null || !mounted) return;
    ref.read(lanPairLinkProvider.notifier).state = null;
    final q = uri.queryParameters;
    unawaited(
      _join(
        code: q['code'],
        hosts: (q['h'] ?? '').split(',').where((h) => h.isNotEmpty).toList(),
        port: int.tryParse(q['p'] ?? ''),
        fingerprint: q['fp'],
      ),
    );
  }

  Future<void> _addDevice() async {
    final name = await showFancyRawDialog<String>(
      context: context,
      builder: (_) => const _PairHostDialog(),
    );
    if (name != null && mounted) {
      showFancyToast(
        context,
        message: context.l10n.lanPairDone(name),
        tone: ToastTone.success,
      );
    }
  }

  Future<void> _join({
    String? code,
    List<String> hosts = const [],
    int? port,
    String? fingerprint,
  }) async {
    final name = await showFancyRawDialog<String>(
      context: context,
      autofocusEsc: false,
      builder: (_) => _JoinDialog(
        code: code,
        hosts: hosts,
        port: port,
        fingerprint: fingerprint,
      ),
    );
    if (name != null && mounted) {
      showFancyToast(
        context,
        message: context.l10n.lanJoinedToast(name),
        tone: ToastTone.success,
      );
    }
  }

  Future<void> _sync() async {
    setState(() => _syncing = true);
    try {
      await ref.read(lanSyncServiceProvider).syncNow();
    } catch (_) {
      // Ошибки обмена видны в строках устройств.
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _revoke(LanMember m) async {
    final l10n = context.l10n;
    final ok = await showFancyDialog<bool>(
      context: context,
      icon: Icons.phonelink_erase_rounded,
      iconColor: AppColors.warning,
      title: l10n.lanRevokeTitle(syncDeviceTitle(l10n, m.name)),
      content: l10n.lanRevokeBody,
      actions: (ctx) => [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(l10n.lanRevokeButton),
        ),
      ],
    );
    if (ok == true) await ref.read(lanSyncServiceProvider).revoke(m.id);
  }

  Future<void> _leave() async {
    final l10n = context.l10n;
    final ok = await showFancyDialog<bool>(
      context: context,
      icon: Icons.logout_rounded,
      iconColor: AppColors.warning,
      title: l10n.lanLeaveTitle,
      content: l10n.lanLeaveBody,
      actions: (ctx) => [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(l10n.lanLeaveButton),
        ),
      ],
    );
    if (ok == true) await ref.read(lanSyncServiceProvider).leave();
  }

  String _status(AppLocalizations l10n, LanPeer? p, DateFormat time) {
    if (p == null) return l10n.lanNeverSynced;
    final now = DateTime.now();
    if (p.error != null && p.online(now)) return lanErrorText(l10n, p.error!);
    final synced = p.lastSync;
    if (p.online(now)) {
      return synced == null
          ? l10n.lanOnline
          : l10n.lanOnlineSynced(time.format(synced));
    }
    return synced == null ? l10n.lanNeverSynced : l10n.lanSyncedAt(time.format(synced));
  }

  Widget _addTiles(AppLocalizations l10n) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            leading: const Icon(Icons.qr_code_2_rounded),
            title: TileTitle(l10n.lanAddDevice),
            subtitle: Text(l10n.lanAddDeviceSubtitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: _addDevice,
          ),
          tileDivider,
          ListTile(
            leading: const Icon(Icons.keyboard_rounded),
            title: TileTitle(l10n.lanEnterCode),
            subtitle: Text(l10n.lanEnterCodeSubtitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _join(),
          ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    ref.listen(lanPairLinkProvider, (_, next) {
      if (next != null) _takeLink();
    });
    ref.watch(lanRevisionProvider);
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final service = ref.read(lanSyncServiceProvider);
    final node = service.node;
    final locale = Localizations.localeOf(context).languageCode;
    final time = DateFormat('d MMM, HH:mm', locale);
    final windowsNote = defaultTargetPlatform == TargetPlatform.windows
        ? SectionNote(l10n.lanFirewallNote)
        : const SizedBox.shrink();

    if (!service.hasGroup) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionTitle(l10n.lanTitle),
          SectionCard(children: [_addTiles(l10n)]),
          SectionNote(l10n.lanNote),
          windowsNote,
        ],
      );
    }

    final members = service.members;
    final selfId = service.deviceId;
    final others = [
      for (final m in members)
        if (m.id != selfId && !m.revoked) m,
    ];
    final self = members.where((m) => m.id == selfId).firstOrNull;
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.7);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(l10n.lanTitle),
        SectionCard(
          children: [
            if (self != null)
              ListTile(
                leading: Icon(syncDeviceIcon(self.name)),
                title: Text(syncDeviceTitle(l10n, self.name)),
                subtitle: Text(l10n.serverDeviceThis),
              ),
            for (final m in others) ...[
              tileDivider,
              Builder(
                builder: (context) {
                  final p = node?.peer(m.id);
                  final online = p?.online(DateTime.now()) ?? false;
                  final error = p?.error != null && online;
                  return ListTile(
                    leading: Icon(syncDeviceIcon(m.name)),
                    title: Text(syncDeviceTitle(l10n, m.name)),
                    subtitle: Text(
                      _status(l10n, p, time),
                      style: TextStyle(
                        color: error
                            ? theme.colorScheme.error
                            : online
                                ? AppColors.success
                                : muted,
                      ),
                    ),
                    trailing: IconButton(
                      tooltip: l10n.lanRevoke,
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => _revoke(m),
                    ),
                  );
                },
              ),
            ],
            tileDivider,
            ListTile(
              leading: _syncing
                  ? const SizedBox.square(
                      dimension: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sync_rounded),
              title: TileTitle(l10n.serverSyncNow),
              onTap: _syncing ? null : _sync,
            ),
          ],
        ),
        SectionNote(l10n.lanGroupNote),
        windowsNote,
        SectionCard(children: [_addTiles(l10n)]),
        SectionCard(
          children: [
            ListTile(
              leading: const Icon(Icons.logout_rounded),
              title: TileTitle(l10n.lanLeave),
              onTap: _leave,
            ),
          ],
        ),
      ],
    );
  }
}

/// «Добавить устройство»: QR-код и код. Закрывается сам, когда второе
/// устройство подключено, — возвращает его имя.
class _PairHostDialog extends ConsumerStatefulWidget {
  const _PairHostDialog();

  @override
  ConsumerState<_PairHostDialog> createState() => _PairHostDialogState();
}

class _PairHostDialogState extends ConsumerState<_PairHostDialog> {
  LanPairing? _pairing;
  String _link = '';
  String? _error;
  Timer? _clock;
  Set<String> _before = {};
  late final LanSyncService _service = ref.read(lanSyncServiceProvider);

  @override
  void initState() {
    super.initState();
    _service.confirmJoin = _confirm;
    unawaited(_open());
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _open() async {
    try {
      final p = await _service.openPairing();
      _before = {for (final m in _service.node!.members) m.id};
      final link = await _service.pairingLink();
      if (mounted) {
        setState(() {
          _pairing = p;
          _link = link;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = context.l10n.lanErrUnknown);
    }
  }

  Future<bool> _confirm(String name) async {
    if (!mounted) return false;
    final l10n = context.l10n;
    final ok = await showFancyDialog<bool>(
      context: context,
      icon: Icons.devices_rounded,
      iconColor: AppColors.warning,
      title: l10n.lanPairConfirmTitle(syncDeviceTitle(l10n, name)),
      content: l10n.lanPairConfirmBody,
      actions: (ctx) => [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(l10n.lanPairConfirm),
        ),
      ],
    );
    return ok == true;
  }

  @override
  void dispose() {
    _clock?.cancel();
    if (_service.confirmJoin == _confirm) _service.confirmJoin = null;
    // Не в самом dispose: закрытие меняет провайдер, а дерево сейчас
    // разбирается.
    scheduleMicrotask(_service.closePairing);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(lanRevisionProvider);
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final node = _service.node;
    // Подключилось новое устройство — готово.
    final joined = node?.members
        .where((m) => !_before.contains(m.id) && !m.revoked)
        .firstOrNull;
    if (_pairing != null && joined != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context, syncDeviceTitle(l10n, joined.name));
      });
    }
    final p = node?.pairing;
    final left = p == null ? Duration.zero : p.expires.difference(DateTime.now());
    final expired = _pairing != null && (p == null || left.isNegative);
    final mm = left.inMinutes, ss = (left.inSeconds % 60).toString().padLeft(2, '0');
    final codeStyle = theme.textTheme.headlineSmall?.copyWith(
      fontFamily: 'monospace',
      fontFamilyFallback: const ['Consolas', 'Courier New'],
      fontWeight: FontWeight.w700,
      letterSpacing: 2,
    );
    return FancyDialogCard(
      icon: Icons.qr_code_2_rounded,
      iconColor: AppColors.warning,
      title: l10n.lanAddDevice,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(top: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(l10n.lanPairHowTo, style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 16),
                  if (_error != null)
                    Text(
                      _error!,
                      style: TextStyle(color: theme.colorScheme.error),
                    )
                  else if (_pairing == null)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator(),
                    )
                  else if (expired)
                    Text(l10n.lanPairExpired)
                  else ...[
                    // Белая подложка и в тёмной теме: камеры плохо читают
                    // светлый код на тёмном.
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: QrImageView(
                        data: _link,
                        size: 200,
                        backgroundColor: Colors.white,
                        semanticsLabel: l10n.lanQrLabel,
                      ),
                    ),
                    const SizedBox(height: 16),
                    SelectableText(formatPairCode(p!.code), style: codeStyle),
                    const SizedBox(height: 6),
                    Text(
                      l10n.lanPairExpires('$mm:$ss'),
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox.square(
                          dimension: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 8),
                        Flexible(child: Text(l10n.lanPairWaiting)),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: [
              if (expired)
                TextButton(onPressed: _open, child: Text(l10n.lanPairNewCode)),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(l10n.close),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// «Ввести код» (или подтверждение ссылки из QR-кода). Возвращает имя
/// устройства, к которому подключились.
class _JoinDialog extends ConsumerStatefulWidget {
  const _JoinDialog({
    this.code,
    this.hosts = const [],
    this.port,
    this.fingerprint,
  });

  final String? code;
  final List<String> hosts;
  final int? port;
  final String? fingerprint;

  @override
  ConsumerState<_JoinDialog> createState() => _JoinDialogState();
}

class _JoinDialogState extends ConsumerState<_JoinDialog> {
  late final _code = TextEditingController(
    text: widget.code == null ? '' : formatPairCode(widget.code!),
  );
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final l10n = context.l10n;
    final code = normalizePairCode(_code.text);
    if (code == null) {
      setState(() => _error = l10n.lanErrBadFormat);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final host = await ref.read(lanSyncServiceProvider).join(
            code,
            hosts: widget.hosts,
            port: widget.port,
            fingerprint: widget.fingerprint,
          );
      if (mounted) Navigator.pop(context, syncDeviceTitle(l10n, host.name));
    } on LanException catch (e) {
      if (mounted) setState(() => _error = lanErrorText(l10n, e.code));
    } catch (_) {
      if (mounted) setState(() => _error = l10n.lanErrUnknown);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return FancyDialogCard(
      icon: Icons.keyboard_rounded,
      iconColor: AppColors.warning,
      title: l10n.lanEnterCode,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(top: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    widget.code == null ? l10n.lanJoinHint : l10n.lanJoinFromQr,
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _code,
                    autofocus: widget.code == null,
                    enabled: !_busy,
                    autocorrect: false,
                    enableSuggestions: false,
                    textCapitalization: TextCapitalization.characters,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontFamilyFallback: ['Consolas', 'Courier New'],
                      letterSpacing: 1.5,
                    ),
                    decoration: InputDecoration(
                      labelText: l10n.lanCodeLabel,
                      hintText: 'XXXX-XXXX-XXXX',
                      border: const OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _busy ? null : _submit(),
                  ),
                  if (_busy) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const SizedBox.square(
                          dimension: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 8),
                        Flexible(child: Text(l10n.lanJoinWaiting)),
                      ],
                    ),
                  ],
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        _error!,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.error),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(l10n.cancel),
              ),
              FilledButton.icon(
                onPressed: _busy ? null : _submit,
                icon: _busy
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.link_rounded, size: 18),
                label: Text(l10n.lanJoinButton),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
