import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/l10n_extensions.dart';
import '../services/battery_hint.dart';
import '../services/notification_controller.dart';

/// Карточка-подсказка: разрешить работу в фоне, чтобы напоминания приходили
/// вовремя (актуально для Transsion/Infinix). Показывается только когда это
/// реально нужно — см. [BatteryHintController].
class BatteryHintCard extends ConsumerWidget {
  const BatteryHintCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hint = ref.watch(batteryHintProvider);
    // Нет смысла, если уведомления выключены вовсе.
    final notifOn = ref.watch(
      notificationControllerProvider.select((c) => c.prefs.enabled),
    );
    if (!notifOn || !hint.shouldShow) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final l10n = context.l10n;
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.5),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.battery_saver_outlined,
                    size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(l10n.batteryHintTitle,
                      style: theme.textTheme.titleSmall),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              l10n.batteryHintBody,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () =>
                      ref.read(batteryHintProvider).dismiss(),
                  child: Text(l10n.hideBtn),
                ),
                FilledButton(
                  onPressed: () => ref.read(batteryHintProvider).allow(),
                  child: Text(l10n.allowBtn),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
