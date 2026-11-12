import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../l10n/app_localizations.dart';
import '../../../l10n/l10n_extensions.dart';
import '../../../widgets/fancy_dialog.dart';
import '../core/integration_command.dart';
import '../core/integration_settings.dart';
import '../inbox/inbox_host.dart';
import 'section_parts.dart';

/// Входы, которые есть на этой платформе. Виджет — наш собственный экран,
/// у него прав не спрашиваем.
List<CommandSource> platformSources() => switch (defaultTargetPlatform) {
      TargetPlatform.android => const [
          CommandSource.link,
          CommandSource.share,
          CommandSource.tasker,
        ],
      TargetPlatform.windows => const [
          CommandSource.link,
          CommandSource.cli,
          CommandSource.mcp,
        ],
      _ => const [CommandSource.link],
    };

/// Раздел «Права»: что каждому входу можно. Подписи объясняют последствия,
/// а включение чтения — только через диалог с предупреждением.
class PermissionsSection extends ConsumerWidget {
  const PermissionsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final settings = ref.watch(integrationSettingsProvider);
    final sources = platformSources();
    final rows = <Widget>[];
    for (final s in sources) {
      if (rows.isNotEmpty) rows.add(tileDivider);
      rows.addAll(_rowsFor(context, ref, s, settings.of(s), l10n));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(l10n.integrationsPermissionsTitle),
        SectionCard(children: rows),
        SectionNote(l10n.integrationsPermissionsNote),
      ],
    );
  }

  List<Widget> _rowsFor(
    BuildContext context,
    WidgetRef ref,
    CommandSource s,
    SourcePermission p,
    AppLocalizations l10n,
  ) {
    final ctrl = ref.read(integrationSettingsProvider.notifier);
    final name = sourceLabel(s, l10n);
    if (s.trust == CommandTrust.untrusted) {
      return [
        SwitchListTile(
          secondary: Icon(_icon(s)),
          title: TileTitle(name),
          subtitle: Text(
            s == CommandSource.share
                ? l10n.integrationsShareSubtitle
                : l10n.integrationsLinkSubtitle,
          ),
          value: p.add,
          onChanged: (v) => ctrl.setPermission(s, p.copyWith(add: v)),
        ),
      ];
    }
    return [
      SwitchListTile(
        secondary: Icon(_icon(s)),
        title: TileTitle(name),
        subtitle: Text(l10n.integrationsAddSubtitle),
        value: p.add,
        onChanged: (v) => ctrl.setPermission(s, p.copyWith(add: v)),
      ),
      SwitchListTile(
        // Отступ под иконку первой строки: вторая строка — тот же вход.
        secondary: const SizedBox(width: 24),
        title: Text(l10n.integrationsReadTitle),
        subtitle: Text(l10n.integrationsReadSubtitle),
        value: p.read,
        onChanged: (v) async {
          if (v && !await confirmEnableRead(context, s)) return;
          await ctrl.setPermission(s, p.copyWith(read: v));
        },
      ),
    ];
  }

  static IconData _icon(CommandSource s) => switch (s) {
        CommandSource.link => Icons.link_rounded,
        CommandSource.share => Icons.ios_share_rounded,
        CommandSource.tasker => Icons.bolt_rounded,
        CommandSource.cli => Icons.terminal_rounded,
        CommandSource.mcp => Icons.auto_awesome_outlined,
        CommandSource.widget => Icons.widgets_outlined,
      };
}

/// Включение чтения — осознанный шаг: список дел начнёт уходить наружу.
/// Для ИИ-ассистента — прямо сказано, куда: в модель ассистента.
Future<bool> confirmEnableRead(BuildContext context, CommandSource s) async {
  final l10n = context.l10n;
  final ok = await showFancyDialog<bool>(
    context: context,
    icon: Icons.visibility_outlined,
    iconColor: AppColors.warning,
    title: l10n.integrationsReadDialogTitle(sourceLabel(s, l10n)),
    content: s == CommandSource.mcp
        ? l10n.integrationsReadDialogMcp
        : l10n.integrationsReadDialogBody,
    actions: (ctx) => [
      TextButton(
        onPressed: () => Navigator.pop(ctx, false),
        child: Text(l10n.cancel),
      ),
      const SizedBox(width: 8),
      FilledButton(
        autofocus: true,
        onPressed: () => Navigator.pop(ctx, true),
        child: Text(l10n.integrationsReadDialogConfirm),
      ),
    ],
  );
  return ok == true;
}
