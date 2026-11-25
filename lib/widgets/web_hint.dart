import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_colors.dart';
import '../data/sources/local/local_storage.dart';
import '../l10n/l10n_extensions.dart';
import '../services/backup_service.dart';
import '../services/web_bits.dart';
import 'fancy_dialog.dart';

// Состояние этого браузера, в бэкап не идёт (см. kDeviceKeyPrefix).
const _key = '${kDeviceKeyPrefix}web_hint';

/// Веб: данные только в браузере, а Safari стирает их через 7 дней без
/// визитов. Раз в две недели (и при первом запуске) просим установить на
/// «Домой» и сохранить копию — автобэкапа в браузере нет.
Future<void> maybeShowWebHint(BuildContext context, WidgetRef ref) async {
  if (!kIsWeb) return;
  final storage = ref.read(localStorageProvider);
  final last = DateTime.tryParse(storage.readMap(_key)?['at'] as String? ?? '');
  if (last != null && DateTime.now().difference(last).inDays < 14) return;
  await storage.writeMap(_key, {'at': DateTime.now().toIso8601String()});
  if (!context.mounted) return;
  final l10n = context.l10n;
  final save = await showFancyDialog<bool>(
    context: context,
    icon: Icons.save_alt_rounded,
    iconColor: AppColors.primary,
    title: l10n.webHintTitle,
    content: isInstalledApp ? l10n.webHintBodyInstalled : l10n.webHintBody,
    actions: (ctx) => [
      TextButton(
        onPressed: () => Navigator.pop(ctx, false),
        child: Text(l10n.webHintLater),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(ctx, true),
        child: Text(l10n.webHintSave),
      ),
    ],
  );
  if (save == true) await ref.read(backupServiceProvider).exportToFile();
}
