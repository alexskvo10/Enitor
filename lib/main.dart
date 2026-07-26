import 'dart:async';

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
import 'services/backup_service.dart';
import 'services/notification_service.dart';

/// Вычисляет следующий момент 4:00 утра (сегодня или завтра).
DateTime _nextFourAm() {
  final now = DateTime.now();
  final candidate = DateTime(now.year, now.month, now.day, 4, 0, 0);
  // Если 4:00 сегодня уже прошло — берём завтра.
  return now.isBefore(candidate)
      ? candidate
      : candidate.add(const Duration(days: 1));
}

/// Планирует тихое списание зависших копий (см. [TaskRepository.
/// demoteStaleTransferredCopies]) ровно в 4:00. Живой запрос-с-диалогами
/// «перенести или нет» для оригиналов живёт в _RootScaffoldState
/// (app_router.dart) — там есть BuildContext для баннеров.
/// После каждого срабатывания перепланирует себя на следующий день.
void _scheduleNightlyTransfer(ProviderContainer container) {
  final delay = _nextFourAm().difference(DateTime.now());
  Timer(delay, () async {
    final now = DateTime.now();
    await container
        .read(taskRepositoryProvider)
        .demoteStaleTransferredCopies(now: now);
    await container
        .read(goalRepositoryProvider)
        .demoteStaleTransferredCopies(now: now);
    // Перепланируем на следующий день.
    _scheduleNightlyTransfer(container);
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

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

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

  // Само планирование уведомлений (запрос разрешений + расписание) запускается
  // ПОСЛЕ старта UI — из корневого виджета, чтобы не блокировать запуск и не
  // упереться в системный диалог разрешений на сплеше.

  // Живой таймер: автоперенос ровно в 4:00 каждую ночь.
  // Самоперепланируется — не нужно перезапускать приложение.
  _scheduleNightlyTransfer(container);

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const EnitorApp(),
    ),
  );
}
