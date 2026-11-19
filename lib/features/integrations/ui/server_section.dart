import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../l10n/app_localizations.dart';
import '../../../l10n/l10n_extensions.dart';
import '../../../widgets/fancy_dialog.dart';
import '../../../widgets/fancy_toast.dart';
import '../../../data/sources/local/local_storage.dart';
import '../sync/sync_background.dart';
import '../sync/sync_client.dart';
import '../sync/sync_service.dart';
import 'section_parts.dart';

/// Текст ошибки обмена по коду из [SyncException] или из журнала настроек.
/// Для `http` без статуса (в настройках он не хранится) — текст сервера.
String _serverErrorText(
  AppLocalizations l10n,
  String code, {
  int? status,
  String? message,
}) =>
    switch (code) {
      'unauthorized' => l10n.serverErrUnauthorized,
      'network' => l10n.serverErrNetwork,
      'bad_response' => l10n.serverErrBadResponse,
      'http' when status != null => l10n.serverErrHttp(status),
      'refused' => l10n.serverErrRefused(status ?? int.tryParse(message ?? '') ?? 0),
      _ => message == null || message.isEmpty ? l10n.serverErrUnknown : message,
    };

/// Значок устройства по имени из [syncDeviceName]: «Android»,
/// «Android tablet · …», «Windows · …»; пустое имя — нейтральный значок.
IconData syncDeviceIcon(String name) {
  final tablet = RegExp(r'^(Android|iOS) tablet').hasMatch(name);
  final phone = !tablet && RegExp(r'^(Android|iOS)\b').hasMatch(name);
  return name.isEmpty
      ? Icons.devices_other_rounded
      : tablet
          ? Icons.tablet_android_rounded
          : phone
              ? Icons.smartphone_rounded
              : Icons.computer_rounded;
}

/// Имя устройства для списка: «tablet» — по-русски, пустое — «Без имени».
String syncDeviceTitle(AppLocalizations l10n, String name) => name.isEmpty
    ? l10n.serverDeviceUnnamed
    : RegExp(r'^(Android|iOS) tablet').hasMatch(name)
        ? name.replaceFirst(' tablet', ' · ${l10n.serverDeviceTablet}')
        : name;

/// Настройки → Синхронизация → «Свой сервер»: подключение, состояние обмена,
/// журнал. Данные уходят только на введённый адрес; без него ничего не
/// отправляется.
class ServerSection extends ConsumerStatefulWidget {
  const ServerSection({super.key});

  @override
  ConsumerState<ServerSection> createState() => _ServerSectionState();
}

class _ServerSectionState extends ConsumerState<ServerSection> {
  bool _syncing = false;
  bool _logAll = false;

  /// Список устройств с сервера; перезапрашивается после каждого обмена.
  Future<List<SyncDevice>?>? _devices;
  DateTime? _devicesFor;

  Future<void> _forget(SyncDevice d) async {
    await ref.read(syncServiceProvider).forgetDevice(d.id);
    if (mounted) setState(() => _devices = null);
  }

  Widget _devicesList(SyncSettings settings, DateFormat time) {
    if (_devices == null || _devicesFor != settings.lastSyncAt) {
      _devicesFor = settings.lastSyncAt;
      _devices = ref.read(syncServiceProvider).devices();
    }
    return FutureBuilder<List<SyncDevice>?>(
      future: _devices,
      builder: (context, snap) {
        final data = snap.data;
        // Старый сервер без списка или нет связи — раздела нет.
        if (data == null || data.isEmpty) return const SizedBox.shrink();
        // Это устройство — первым, остальные как пришли (свежие выше).
        final list = [
          ...data.where((d) => d.id == settings.deviceId),
          ...data.where((d) => d.id != settings.deviceId),
        ];
        final l10n = context.l10n;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionTitle(l10n.serverDevicesTitle),
            SectionCard(
              children: [
                for (final (i, d) in list.indexed) ...[
                  if (i > 0) tileDivider,
                  _deviceTile(d, d.id == settings.deviceId, time),
                ],
              ],
            ),
            SectionNote(l10n.serverDevicesNote),
          ],
        );
      },
    );
  }

  Widget _deviceTile(SyncDevice d, bool self, DateFormat time) {
    final l10n = context.l10n;
    return ListTile(
      leading: Icon(syncDeviceIcon(d.name)),
      title: Text(syncDeviceTitle(l10n, d.name)),
      subtitle: Text(
        self
            ? l10n.serverDeviceThis
            : d.lastSeen == null
                ? ''
                : l10n.serverDeviceSeen(time.format(d.lastSeen!)),
      ),
      trailing: self
          ? null
          : IconButton(
              tooltip: l10n.serverDeviceForget,
              icon: const Icon(Icons.close_rounded),
              onPressed: () => _forget(d),
            ),
    );
  }

  Future<void> _sync() async {
    setState(() => _syncing = true);
    try {
      await ref.read(syncServiceProvider).syncNow();
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _connect() async {
    final ok = await showFancyRawDialog<bool>(
      context: context,
      autofocusEsc: false,
      builder: (_) => const _ConnectDialog(),
    );
    if (ok == true && mounted) {
      showFancyToast(
        context,
        message: context.l10n.serverConnected,
        tone: ToastTone.success,
      );
    }
  }

  Future<void> _disconnect() async {
    final l10n = context.l10n;
    final ok = await showFancyDialog<bool>(
      context: context,
      icon: Icons.link_off_rounded,
      iconColor: AppColors.warning,
      title: l10n.serverDisconnectTitle,
      content: l10n.serverDisconnectBody,
      actions: (ctx) => [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(l10n.serverDisconnect),
        ),
      ],
    );
    if (ok != true) return;
    await ref.read(syncServiceProvider).disconnect();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final settings = ref.watch(syncSettingsProvider);
    final fullLog = ref.watch(syncLogProvider).take(20).toList();
    // Свёрнутый журнал: иначе 20 строк уталкивают остальные разделы вниз.
    final log = _logAll ? fullLog : fullLog.take(3).toList();
    final service = ref.read(syncServiceProvider);
    final busy = _syncing || service.syncing;
    final locale = Localizations.localeOf(context).languageCode;
    final time = DateFormat('d MMM, HH:mm', locale);
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.7);
    final url = settings.url;
    final errorCode = settings.lastErrorCode;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(l10n.serverTitle),
        if (url == null) ...[
          SectionCard(
            children: [
              ListTile(
                leading: const Icon(Icons.cloud_outlined),
                title: TileTitle(l10n.serverConnect),
                trailing: const Icon(Icons.chevron_right),
                onTap: _connect,
              ),
            ],
          ),
          SectionNote(l10n.serverNote),
        ] else ...[
          SectionCard(
            children: [
              ListTile(
                leading: const Icon(Icons.dns_rounded),
                title: Text(url),
                subtitle: Text(
                  errorCode != null
                      ? _serverErrorText(
                          l10n,
                          errorCode,
                          message: settings.lastError,
                        )
                      : settings.lastSyncAt != null
                          ? l10n
                              .serverSyncedAt(time.format(settings.lastSyncAt!))
                          : l10n.serverNotSynced,
                  style: errorCode != null
                      ? TextStyle(color: theme.colorScheme.error)
                      : null,
                ),
              ),
              if (defaultTargetPlatform == TargetPlatform.android) ...[
                tileDivider,
                _PushTile(storage: ref.read(localStorageProvider)),
              ],
              tileDivider,
              ListTile(
                leading: busy
                    ? const SizedBox.square(
                        dimension: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sync_rounded),
                title: TileTitle(l10n.serverSyncNow),
                onTap: busy ? null : _sync,
              ),
              tileDivider,
              ListTile(
                leading: const Icon(Icons.link_off_rounded),
                title: TileTitle(l10n.serverDisconnect),
                onTap: _disconnect,
              ),
            ],
          ),
          _devicesList(settings, time),
          SectionTitle(l10n.serverLogTitle),
          SectionCard(
            children: [
              if (log.isEmpty)
                ListTile(
                  dense: true,
                  leading: Icon(Icons.history_rounded, size: 20, color: muted),
                  title: Text(l10n.serverLogEmpty),
                )
              else ...[
                for (final e in log)
                  ListTile(
                    dense: true,
                    leading: Icon(
                      e.error == null
                          ? Icons.check_circle_outline
                          : Icons.error_outline_rounded,
                      size: 20,
                      color: e.error == null
                          ? AppColors.success
                          : theme.colorScheme.error,
                    ),
                    title: Text(time.format(e.at)),
                    subtitle: Text(
                      e.error == null
                          ? l10n.serverExchange(e.sent, e.received)
                          : e.code == null
                              ? e.error!
                              : _serverErrorText(
                                  l10n,
                                  e.code!,
                                  status: e.status,
                                  message: e.error,
                                ),
                      style: e.error == null
                          ? null
                          : TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
                if (fullLog.length > 3) ...[
                  tileDivider,
                  ListTile(
                    leading: Icon(
                      _logAll
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                    ),
                    title: Text(
                      _logAll
                          ? l10n.serverLogCollapse
                          : l10n.serverLogShowAll(fullLog.length),
                    ),
                    onTap: () => setState(() => _logAll = !_logAll),
                  ),
                ],
                tileDivider,
                ListTile(
                  leading: const Icon(Icons.delete_sweep_outlined),
                  title: Text(l10n.serverClearLog),
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

/// Диалог подключения: адрес, токен, объединить или заменить данные.
class _ConnectDialog extends ConsumerStatefulWidget {
  const _ConnectDialog();

  @override
  ConsumerState<_ConnectDialog> createState() => _ConnectDialogState();
}

class _ConnectDialogState extends ConsumerState<_ConnectDialog> {
  final _url = TextEditingController();
  final _token = TextEditingController();
  bool _showToken = false;
  bool _takeServer = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _url.dispose();
    _token.dispose();
    super.dispose();
  }

  /// Адрес принят; для http:// сначала спрашиваем, как у вебхуков.
  Future<bool> _confirmUrl(Uri uri) async {
    final l10n = context.l10n;
    if (uri.scheme == 'https') return true;
    final ok = await showFancyDialog<bool>(
      context: context,
      icon: Icons.lock_open_rounded,
      iconColor: AppColors.warning,
      title: l10n.calHttpTitle,
      content: l10n.serverHttpBody,
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

  Future<void> _submit() async {
    final l10n = context.l10n;
    final url = _url.text.trim();
    final token = _token.text.trim();
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !uri.hasAuthority ||
        !(uri.scheme == 'https' || uri.scheme == 'http')) {
      setState(() => _error = l10n.hookBadUrl);
      return;
    }
    if (token.isEmpty) {
      setState(() => _error = l10n.serverTokenEmpty);
      return;
    }
    if (!await _confirmUrl(uri) || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(syncServiceProvider).connect(
            url: url,
            token: token,
            takeServer: _takeServer,
          );
      if (mounted) Navigator.of(context).pop(true);
    } on SyncException catch (e) {
      if (mounted) {
        setState(
          () => _error = _serverErrorText(
            l10n,
            e.code,
            status: e.status,
            message: e.message,
          ),
        );
      }
    } catch (_) {
      if (mounted) setState(() => _error = l10n.serverErrUnknown);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final optionStyle =
        theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600);
    final noteStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
    );
    return FancyDialogCard(
      icon: Icons.cloud_outlined,
      iconColor: AppColors.warning,
      title: l10n.serverConnect,
      // Отступ — внутри прокрутки: подпись поля в фокусе поднимается на
      // рамку, и снаружи её срезал бы край SingleChildScrollView.
      // Кнопки — вне прокрутки: при открытой клавиатуре их не обрезает.
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(top: 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _url,
                    autofocus: true,
                    keyboardType: TextInputType.url,
                    decoration: InputDecoration(
                      labelText: l10n.serverUrlLabel,
                      hintText: 'https://…',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _token,
                    obscureText: !_showToken,
                    enableSuggestions: false,
                    autocorrect: false,
                    decoration: InputDecoration(
                      labelText: l10n.serverTokenLabel,
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        tooltip: _showToken ? l10n.taskerHide : l10n.taskerShow,
                        icon: Icon(
                          _showToken
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                        ),
                        onPressed: () =>
                            setState(() => _showToken = !_showToken),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  RadioGroup<bool>(
                    groupValue: _takeServer,
                    onChanged: (v) => setState(() => _takeServer = v ?? false),
                    // Material: строки-радио рисуют подложку и ink на ближайшем
                    // Material, а карточка диалога кладёт над ним декорацию.
                    child: Material(
                      type: MaterialType.transparency,
                      child: Column(
                        children: [
                          RadioListTile<bool>(
                            contentPadding: EdgeInsets.zero,
                            value: false,
                            title:
                                Text(l10n.serverModeMerge, style: optionStyle),
                          ),
                          RadioListTile<bool>(
                            contentPadding: EdgeInsets.zero,
                            value: true,
                            title: Text(l10n.serverModeReplace,
                                style: optionStyle),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(l10n.serverModeReplaceNote,
                                  style: noteStyle),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
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
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
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
                label: Text(l10n.serverConnectButton),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Android: придут ли изменения в фоне сразу (есть доставщик UnifiedPush и
/// адрес отправлен) или только по WorkManager раз в 15 минут.
class _PushTile extends StatelessWidget {
  const _PushTile({required this.storage});

  final LocalStorage storage;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final on = storage.readMap(kSyncPushKey)?['endpoint'] != null;
    return ListTile(
      leading: Icon(
        on ? Icons.bolt_rounded : Icons.schedule_rounded,
        color: on ? AppColors.success : null,
      ),
      title: Text(on ? l10n.serverPushOn : l10n.serverPushOff),
    );
  }
}
