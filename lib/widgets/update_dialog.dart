import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_colors.dart';
import '../l10n/l10n_extensions.dart';
import '../services/update_service.dart';
import 'fancy_dialog.dart';
import 'fancy_toast.dart';

/// Проверяет обновления и, если нужно, ведёт пользователя через весь флоу:
/// диалог «доступно обновление» → прогресс скачивания → системный установщик
/// (Android) / самообновляющийся релонч (Windows).
///
/// [manual] — вызвано кнопкой «Проверить обновления» (игнорирует суточный
/// троттлинг и показывает результат в любом случае, включая «всё актуально»
/// и ошибки сети). Автопроверка при старте вызывает с `manual: false` и
/// молчит, если обновления нет или что-то пошло не так — не нужно дёргать
/// пользователя сетевой ошибкой на каждом запуске.
Future<void> checkAndShowUpdateDialog(
  BuildContext context,
  WidgetRef ref, {
  bool manual = false,
}) async {
  final service = ref.read(updateServiceProvider);
  final result = await service.checkForUpdate(force: manual);
  if (!context.mounted) return;
  final l10n = context.l10n;

  switch (result.status) {
    case UpdateCheckStatus.available:
      await _showUpdateAvailableDialog(
        context,
        ref,
        result.release!,
        result.currentVersion ?? '',
      );
    case UpdateCheckStatus.upToDate:
      if (manual) {
        showFancyToast(
          context,
          message: l10n.updateUpToDateToast(result.currentVersion ?? ''),
          tone: ToastTone.success,
        );
      }
    case UpdateCheckStatus.error:
      if (manual) {
        showFancyToast(
          context,
          message: l10n.updateCheckFailedToast(result.error ?? ''),
          tone: ToastTone.error,
        );
      }
    case UpdateCheckStatus.throttled:
      break;
  }
}

Future<void> _showUpdateAvailableDialog(
  BuildContext context,
  WidgetRef ref,
  ReleaseInfo release,
  String currentVersion,
) async {
  final l10n = context.l10n;
  final install = await showFancyDialog<bool>(
    context: context,
    icon: Icons.system_update_rounded,
    iconColor: AppColors.primary,
    title: l10n.updateAvailableTitle,
    contentBuilder: (ctx) {
      final notes = release.notes;
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l10n.updateAvailableBody(release.version, currentVersion),
            textAlign: TextAlign.center,
            style: Theme.of(ctx)
                .textTheme
                .bodyMedium
                ?.copyWith(color: AppColors.textSecondary),
          ),
          if (notes != null && notes.isNotEmpty) ...[
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 160),
              child: SingleChildScrollView(
                child: Text(
                  notes,
                  style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                ),
              ),
            ),
          ],
        ],
      );
    },
    actions: (ctx) => [
      TextButton(
        onPressed: () => Navigator.pop(ctx, false),
        child: Text(l10n.updateLaterBtn),
      ),
      const SizedBox(width: 8),
      FilledButton(
        autofocus: true,
        onPressed: () => Navigator.pop(ctx, true),
        child: Text(l10n.updateInstallBtn),
      ),
    ],
  );
  if (install != true || !context.mounted) return;
  await _downloadAndInstall(context, ref, release);
}

Future<void> _downloadAndInstall(
  BuildContext context,
  WidgetRef ref,
  ReleaseInfo release,
) async {
  final l10n = context.l10n;
  final asset =
      Platform.isAndroid ? release.androidAsset : release.windowsAsset;
  if (asset == null) {
    showFancyToast(context,
        message: l10n.updateNoBuildError, tone: ToastTone.error);
    return;
  }

  final progress = ValueNotifier<double>(0);
  final service = ref.read(updateServiceProvider);

  // Не Navigator.pop() (закрыл бы ЛЮБОЙ верхний диалог — например, если за
  // время скачивания разблокировалось достижение и showAchievementPopup
  // встал поверх нас). Держим ссылку на СВОЙ route и снимаем именно его,
  // где бы он ни оказался в стеке — removeRoute не требует, чтобы route был
  // текущим верхним.
  Route<void>? progressRoute;

  unawaited(showFancyRawDialog<void>(
    context: context,
    autofocusEsc: false,
    barrierLabel: l10n.updateDownloadingTitle,
    builder: (ctx) {
      progressRoute = ModalRoute.of(ctx);
      return PopScope(
        canPop: false,
        child: FancyDialogCard(
          icon: Icons.download_rounded,
          iconColor: AppColors.primary,
          title: l10n.updateDownloadingTitle,
          child: Padding(
            padding: const EdgeInsets.only(top: 16, bottom: 4),
            child: ValueListenableBuilder<double>(
              valueListenable: progress,
              builder: (_, value, __) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      value: value > 0 ? value : null,
                      minHeight: 6,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text('${(value * 100).clamp(0, 100).toStringAsFixed(0)}%'),
                ],
              ),
            ),
          ),
        ),
      );
    },
  ));

  void closeProgressDialog() {
    final route = progressRoute;
    if (route != null && route.isActive) {
      route.navigator?.removeRoute(route);
    }
  }

  try {
    final path = await service.downloadAsset(
      asset,
      onProgress: (v) => progress.value = v,
    );
    if (Platform.isAndroid) {
      closeProgressDialog();
      await service.installAndroidApk(path);
    } else {
      // installWindowsUpdate завершает процесс изнутри (exit(0)), чтобы
      // освободить exe/dll под замену — диалог закрывать не успеем и не
      // нужно, приложение исчезнет само.
      await service.installWindowsUpdate(path);
    }
  } catch (e) {
    closeProgressDialog();
    if (!context.mounted) return;
    showFancyToast(context,
        message: l10n.updateInstallFailedToast('$e'), tone: ToastTone.error);
  } finally {
    progress.dispose();
  }
}
