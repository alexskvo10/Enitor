import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../l10n/l10n_extensions.dart';
import '../../../core/theme/appearance.dart';
import '../core/command_journal.dart';
import '../core/integration_settings.dart';
import '../windows/link_registration.dart';
import 'section_parts.dart';

/// Путь к `enitor-cli.exe` — он лежит рядом с `enitor.exe` в папке релиза.
String cliPath() =>
    cliPathForTests ??
    '${File(Platform.resolvedExecutable).parent.path}\\enitor-cli.exe';

/// В тестах «программа» — тестовый движок из папки Flutter SDK: без
/// постоянного пути снимок экрана зависел бы от того, где лежит SDK.
@visibleForTesting
String? cliPathForTests;

/// Готовая настройка MCP (формат `mcpServers`).
String claudeDesktopConfig(String cli) =>
    const JsonEncoder.withIndent('  ').convert({
      'mcpServers': {
        'enitor': {
          'command': cli,
          'args': ['mcp'],
        },
      },
    });

/// Windows: ссылки `enitor://` и консоль.
class WindowsSection extends ConsumerWidget {
  const WindowsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final settings = ref.watch(integrationSettingsProvider);
    final synced = ref.watch(linkSyncResultProvider);
    final cli = cliPath();
    final status = !settings.windowsLinks
        ? l10n.winLinksOff
        : synced == LinkRegistrationState.stale
            ? l10n.winLinksFixed
            : l10n.winLinksOn;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(l10n.winSectionTitle),
        SectionCard(
          children: [
            SwitchListTile(
              secondary: const Icon(Icons.link_rounded),
              title: TileTitle(l10n.winLinksTitle),
              subtitle: Text(status),
              value: settings.windowsLinks,
              onChanged: (v) async {
                await ref
                    .read(integrationSettingsProvider.notifier)
                    .update(settings.copyWith(windowsLinks: v));
                await ref.read(linkRegistrationProvider).sync(enabled: v);
                ref.read(linkSyncResultProvider.notifier).state = null;
              },
            ),
            tileDivider,
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Text(
                l10n.winCliTitle,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            CopyBlock(text: cli, label: l10n.winCopyPath),
            CopyBlock(
              text: [
                'enitor-cli add "${l10n.winCliExampleTask}" --at 18:00',
                'enitor-cli today',
                'enitor-cli done 3f9a',
                'enitor-cli --help',
              ].join('\n'),
            ),
          ],
        ),
        SectionNote(l10n.winCliNote),
      ],
    );
  }
}

/// Windows: ИИ-ассистенты (MCP) — настройка MCP и журнал
/// последних вызовов, чтобы было видно, что делал ассистент.
class AssistantsSection extends ConsumerWidget {
  const AssistantsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final log = ref.watch(mcpLogProvider);
    final locale = Localizations.localeOf(context).languageCode;
    final time = DateFormat('d MMM, HH:mm', locale);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(l10n.mcpSectionTitle),
        SectionCard(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Text(l10n.mcpConfigTitle, style: theme.textTheme.titleSmall),
            ),
            CopyBlock(
              text: claudeDesktopConfig(cliPath()),
              label: l10n.mcpCopyConfig,
            ),
            tileDivider,
            ListTile(
              leading: const Icon(Icons.history_rounded),
              title: TileTitle(l10n.mcpLogTitle),
              trailing: log.isEmpty
                  ? null
                  : TextButton(
                      onPressed: () =>
                          ref.read(mcpLogProvider.notifier).clear(),
                      child: Text(l10n.mcpLogClear),
                    ),
            ),
            if (log.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: NotebookEmptyState(
                  text: l10n.mcpLogEmpty,
                  icon: Icons.history_rounded,
                ),
              )
            else
              for (final e in log)
                ListTile(
                  dense: true,
                  leading: Icon(
                    e.ok ? Icons.check_circle_outline : Icons.block_rounded,
                    size: 20,
                    color: e.ok
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                  title: Text(
                    e.detail == null ? e.command : '${e.command} · ${e.detail}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(time.format(e.at)),
                ),
          ],
        ),
        SectionNote(l10n.mcpNote),
      ],
    );
  }
}
