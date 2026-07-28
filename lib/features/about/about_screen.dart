import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_fonts.dart';
import '../../l10n/l10n_extensions.dart';
import '../../widgets/update_dialog.dart';

/// Экран «О приложении»: логотип, название, версия и краткая справка.
class AboutScreen extends ConsumerWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.6);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.aboutTitle)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
        children: [
          // ── Логотип + название + версия ─────────────────────────────────
          Center(
            child: Column(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Image.asset(
                    'assets/icon/icon.png',
                    width: 96,
                    height: 96,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Enitor',
                  style: AppFonts.sourceSerif4(
                    textStyle: theme.textTheme.headlineSmall,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.appTagline,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(color: muted),
                ),
                const SizedBox(height: 10),
                FutureBuilder<PackageInfo>(
                  future: PackageInfo.fromPlatform(),
                  builder: (context, snapshot) {
                    final info = snapshot.data;
                    final label = info == null
                        ? '…'
                        : l10n.versionLabel(info.version, info.buildNumber);
                    return Text(
                      label,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),

          // ── Справка ─────────────────────────────────────────────────────
          Card(
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                _InfoTile(
                  icon: Icons.devices_outlined,
                  title: l10n.platformsLabel,
                  subtitle: 'Windows · Android',
                ),
                const Divider(height: 1),
                _InfoTile(
                  icon: Icons.lock_outline,
                  title: l10n.dataLabel,
                  subtitle: l10n.dataStoredLocally,
                ),
                const Divider(height: 1),
                _InfoTile(
                  icon: Icons.flutter_dash,
                  title: l10n.madeWithLabel,
                  subtitle: 'Flutter',
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),
          Card(
            margin: EdgeInsets.zero,
            child: ListTile(
              leading: Icon(Icons.system_update_alt_outlined,
                  color: theme.colorScheme.primary),
              title: Text(l10n.checkForUpdatesLabel),
              onTap: () => checkAndShowUpdateDialog(context, ref, manual: true),
            ),
          ),

          const SizedBox(height: 28),
          Center(
            child: Text(
              l10n.madeWithHeart,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.danger.withValues(alpha: 0.7),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
      title: Text(title),
      subtitle: Text(subtitle),
    );
  }
}
