import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'data/repositories/goal_repository.dart';
import 'data/repositories/profile_repository.dart';
import 'data/repositories/stats_repository.dart';
import 'data/repositories/task_repository.dart';
import 'data/sources/local/local_storage.dart';
import 'features/integrations/core/command_handler.dart';
import 'features/integrations/core/command_journal.dart';
import 'features/integrations/core/integration_gateway.dart';
import 'features/integrations/core/integration_settings.dart';
import 'features/integrations/ics/ics_subscription.dart';
import 'features/integrations/sync/lan/lan_service.dart';
import 'features/integrations/sync/sync_background.dart';
import 'features/integrations/sync/sync_service.dart';
import 'features/integrations/webhooks/webhooks.dart';
import 'features/integrations/widget/day_snapshot.dart';
import 'features/integrations/windows/link_registration.dart';
import 'core/utils/date_utils.dart';
import 'services/backup_service.dart';
import 'services/notification_service.dart';
import 'services/pomodoro_controller.dart';
import 'services/update_service.dart';

/// Вычисляет следующий момент 4:00 утра (сегодня или завтра).
DateTime _nextFourAm() {
  final now = DateTime.now();
  final candidate = DateTime(now.year, now.month, now.day, 4, 0, 0);
  // Если 4:00 сегодня уже прошло — берём завтра.
  return now.isBefore(candidate)
      ? candidate
      : addDays(candidate, 1);
}

/// Планирует тихое списание зависших копий (см. [TaskRepository.
/// demoteStaleTransferredCopies]) ровно в 4:00. Живой запрос-с-диалогами
/// «перенести или нет» для оригиналов живёт в _RootScaffoldState
/// (app_router.dart) — там есть BuildContext для баннеров.
/// После каждого срабатывания перепланирует себя на следующий день.
void _scheduleNightlyTransfer(ProviderContainer container) {
  final delay = _nextFourAm().difference(DateTime.now());
  Timer(delay, () async {
    try {
      final now = DateTime.now();
      final tasks = container.read(taskRepositoryProvider);
      await tasks.demoteStaleTransferredCopies(now: now);
      await container
          .read(goalRepositoryProvider)
          .demoteStaleTransferredCopies(now: now);
      // Вчерашний день закрылся: повторы, которых в нём нет, — в статистику.
      await tasks.backfillPastRecurrences(now: now);
    } finally {
      // Перепланируем на следующий день — даже если что-то упало, иначе
      // ночное списание молча перестало бы работать до перезапуска.
      _scheduleNightlyTransfer(container);
    }
  });
}

/// Гонка холодного старта (особенно на Android после установки): нативный
/// обработчик pigeon-канала плагина может быть ещё не зарегистрирован в момент
/// первого вызова → `PlatformException(channel-error)`. Ретраим, пока канал не
/// поднимется (обычно сотни мс). Без этого `main()` падает до `runApp` и
/// приложение виснет на сплеше.
Future<SharedPreferences> _initPrefs() async {
  for (var attempt = 0; ; attempt++) {
    try {
      return await SharedPreferences.getInstance();
    } on PlatformException catch (e) {
      if (e.code == 'channel-error' && attempt < 10) {
        await Future<void>.delayed(const Duration(milliseconds: 120));
        continue;
      }
      rethrow;
    }
  }
}

/// [args] — аргументы запуска. На Windows среди них бывает ссылка
/// `enitor://…`: так Windows открывает приложение по зарегистрированной схеме.
Future<void> main(List<String> args) async {
  // Сигнал UnifiedPush, когда приложение закрыто: система запускает движок
  // без окна — только обмен с сервером, без интерфейса.
  if (args.contains('--unifiedpush-bg')) return runPushBackground();
  updateFailedOnLaunch = args.contains(kUpdateFailedArg);
  WidgetsFlutterBinding.ensureInitialized();
  // До чтения хранилища: см. claimForegroundSync.
  claimForegroundSync();

  final prefs = await _initPrefs();
  final storage = LocalStorage(prefs);

  // Авто-восстановление: если локальных данных нет (свежая установка/«очистить
  // данные»), но в папке приложения лежит авто-бэкап — поднимаем его ДО сборки
  // репозиториев (они читают хранилище в конструкторе). Безопасно: срабатывает
  // только на пустом старте, поэтому ничего не затирает.
  if (!storage.hasData) {
    final backup = BackupService(storage);
    final saved = await backup.readAutoBackup();
    if (saved != null) {
      try {
        await backup.restoreFromJson(saved);
      } catch (_) {}
    }
  }

  // Уведомления не критичны для запуска — не даём им уронить старт.
  final notifications = NotificationService();
  try {
    await notifications.init();
  } catch (_) {}

  final container = ProviderContainer(
    overrides: [
      localStorageProvider.overrideWithValue(storage),
      notificationServiceProvider.overrideWithValue(notifications),
      pomodoroAlarmsProvider.overrideWithValue(notifications),
    ],
  );

  // Гарантируем, что профиль создан при первом запуске.
  await container.read(profileRepositoryProvider).ensureProfile();

  // Недельная дельта: если началась новая неделя, фиксируем текущие средние
  // как базу. Делаем это до runApp — пользователь ещё не действовал на этой
  // неделе, поэтому значение соответствует концу прошлой недели.
  final stats = container.read(statsRepositoryProvider);
  await container.read(profileRepositoryProvider).maybeRollWeeklyDelta(
        currentProductivity: await stats.averageAllTime(),
        currentOnTime: await stats.onTimeAverageAllTime(),
      );

  // Тихое списание зависших копий (перенесённых, но так и не выполненных)
  // из прошлых дней/периодов — безопасно делать до runApp, не требует UI.
  // Живой перенос ОРИГИНАЛОВ (с подтверждением у пользователя) обрабатывается
  // отдельно, уже внутри дерева виджетов — см. app.dart/app_router.dart.
  final now = DateTime.now();
  final isAfter4am = now.hour >= 4;
  if (isAfter4am) {
    await container
        .read(taskRepositoryProvider)
        .demoteStaleTransferredCopies(now: now);
    await container
        .read(goalRepositoryProvider)
        .demoteStaleTransferredCopies(now: now);
  }
  // Прошедшие дни, когда приложение не открывали: их повторы — в статистику.
  unawaited(
    container.read(taskRepositoryProvider).backfillPastRecurrences(now: now),
  );

  // Само планирование уведомлений (запрос разрешений + расписание) запускается
  // ПОСЛЕ старта UI — из корневого виджета, чтобы не блокировать запуск и не
  // упереться в системный диалог разрешений на сплеше.

  // Живой таймер: автоперенос ровно в 4:00 каждую ночь.
  // Самоперепланируется — не нужно перезапускать приложение.
  _scheduleNightlyTransfer(container);

  // Внешние входы (ссылки, «Поделиться», Tasker, консоль, MCP). Подключаем
  // до runApp: команды, пришедшие раньше, ждут в очереди CommandInbox, а
  // анкету InboxHost откроет после первого кадра.
  final gateway = container.read(integrationGatewayProvider);
  await gateway.attach();
  watchExecutedCommands(container);
  if (defaultTargetPlatform == TargetPlatform.android) {
    WidgetSnapshotWriter(container).start();
  }
  // Вебхуки: события от действий на этом устройстве + досылка накопленного.
  final hooks = container.read(webhookServiceProvider)
    ..onGone = (ep) => notifications.showTrace(
          currentL10n().hookGoneNotifTitle,
          ep.url,
        );
  hooks.listen();
  unawaited(hooks.process());
  AppLifecycleListener(onResume: () => unawaited(hooks.retryNow()));
  // Уведомления о конце отрезка таймера — только пока приложение свёрнуто.
  AppLifecycleListener(
    onStateChange: (s) => container.read(pomodoroProvider).setForeground(
          s == AppLifecycleState.resumed || s == AppLifecycleState.inactive,
        ),
  );
  // Свой сервер (если подключён): обмен при запуске, после правок, при
  // возврате в приложение и по событиям сервера.
  final sync = container.read(syncServiceProvider);
  sync
    ..onBackground = ((on) => setBackgroundSync(on, service: sync))
    ..start();
  attachForegroundSync(sync);
  // Синхронизация по сети — только если есть группа своих устройств.
  container.read(lanSyncServiceProvider).start();
  if (sync.settings.connected) {
    unawaited(setBackgroundSync(true, service: sync).catchError((Object _) {}));
  }
  // Календарь по ссылке — только если человек сам включил «обновлять».
  unawaited(refreshIcsSubscription(container));
  if (defaultTargetPlatform == TargetPlatform.windows) {
    // Схема enitor:// — на путь этого exe: папку могли перенести.
    unawaited(
      container
          .read(linkRegistrationProvider)
          .sync(enabled: container.read(integrationSettingsProvider).windowsLinks)
          .then((s) => container.read(linkSyncResultProvider.notifier).state = s),
    );
  }
  for (final a in args) {
    if (a.toLowerCase().startsWith('enitor:')) gateway.receiveLink(a);
  }

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const EnitorApp(),
    ),
  );
}
