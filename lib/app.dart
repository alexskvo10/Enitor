import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' as intl;

import 'core/create_action.dart';
import 'core/l10n/locale_controller.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/appearance.dart';
import 'l10n/app_localizations.dart';
import 'data/repositories/task_repository.dart';
import 'services/backup_service.dart';
import 'services/notification_controller.dart';
import 'services/notification_service.dart';

/// Корневой виджет приложения.
class EnitorApp extends ConsumerStatefulWidget {
  const EnitorApp({super.key});

  @override
  ConsumerState<EnitorApp> createState() => _EnitorAppState();
}

class _EnitorAppState extends ConsumerState<EnitorApp> with WidgetsBindingObserver {
  Timer? _backupDebounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // ПОСЛЕ первого кадра: спрашиваем разрешения (не на сплеше) и собираем
    // первичное расписание уведомлений из текущих задач.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await ref.read(notificationServiceProvider).requestPermissions();
      if (!mounted) return;
      await ref.read(notificationControllerProvider).reschedule();
    });
  }

  @override
  void dispose() {
    _backupDebounce?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Уходим в фон/закрываемся — пишем финальный авто-бэкап (гарантированный
    // полный снимок всех данных).
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      ref.read(backupServiceProvider).writeAutoBackup();
    }
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);
    final themeMode =
        ref.watch(appearanceProvider.select((a) => a.themeMode));
    final locale = ref.watch(localeControllerProvider.select((c) => c.locale));

    // Задачи изменились (добавили/удалили/перенесли со временем) — пересобираем
    // расписание. Контроллер дебаунсит, так что серия правок = один проход.
    ref.listen(allTasksProvider, (_, __) {
      ref.read(notificationControllerProvider).reschedule();
      // Авто-бэкап с дебаунсом: снимок берётся целиком (все ключи), поэтому
      // изменения целей/шаблонов тоже попадут при ближайшей правке задач.
      _backupDebounce?.cancel();
      _backupDebounce = Timer(const Duration(seconds: 3), () {
        ref.read(backupServiceProvider).writeAutoBackup();
      });
    });
    // Смена языка — переставляем уже запланированные уведомления новым текстом.
    ref.listen(localeControllerProvider.select((c) => c.option), (_, __) {
      ref.read(notificationControllerProvider).reschedule();
    });

    return MaterialApp.router(
      title: 'Enitor',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      locale: locale,
      routerConfig: router,
      // Фон (цвет + текстура) сплошной под всеми экранами; scaffold'ы
      // прозрачны (см. AppTheme). Плюс глобальный Ctrl+N — «создать» для
      // активной вкладки (задача/цель). Focus(autofocus) гарантирует, что
      // событие клавиши дойдёт до CallbackShortcuts, даже когда ничего не
      // сфокусировано.
      builder: (context, child) {
        // Часть форматирования (месяцы/сезоны в GoalPeriodRef) живёт в чистых
        // Dart-моделях без BuildContext — синхронизируем глобальную локаль
        // intl с уже разрешённой Flutter-локалью на каждой перестройке дерева.
        intl.Intl.defaultLocale = Localizations.localeOf(context).languageCode;
        return CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.keyN, control: true): () =>
                ref.read(createActionProvider)?.call(),
          },
          child: Focus(
            autofocus: true,
            // На широком окне (десктоп) контент не растягиваем на всю ширину —
            // ограничиваем «страницей» по центру (≤720px), бумажная текстура
            // заполняет бока. На телефоне (<720px) ConstrainedBox прозрачен.
            child: AppBackground(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: child ?? const SizedBox.shrink(),
                ),
              ),
            ),
          ),
        );
      },
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
    );
  }
}
