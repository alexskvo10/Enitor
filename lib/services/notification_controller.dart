import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories/backlog_repository.dart';
import '../data/repositories/goal_repository.dart';
import '../data/repositories/task_repository.dart';
import '../data/sources/local/local_storage.dart';
import 'notification_prefs.dart';
import 'notification_service.dart';

const _kNotifPrefsKey = 'notif_prefs';

/// Держит [NotificationPrefs], персистит их и пересобирает расписание
/// уведомлений (из текущих задач) при любом изменении. Источник правды для
/// экрана настроек.
class NotificationController extends ChangeNotifier {
  NotificationController(
    this._storage,
    this._service,
    this._tasks,
    this._goals,
    this._backlog,
    this._goalBacklog,
  ) {
    final raw = _storage.readMap(_kNotifPrefsKey);
    if (raw != null) _prefs = NotificationPrefs.fromJson(raw);
  }

  final LocalStorage _storage;
  final NotificationService _service;
  final TaskRepository _tasks;
  final GoalRepository _goals;
  final BacklogRepository _backlog;
  final GoalBacklogRepository _goalBacklog;

  NotificationPrefs _prefs = const NotificationPrefs();
  NotificationPrefs get prefs => _prefs;

  Timer? _debounce;

  /// Пересобирает расписание под текущие настройки и список задач.
  /// Дебаунс — частые изменения задач не дёргают планировщик подряд.
  Future<void> reschedule() async {
    _debounce?.cancel();
    final completer = Completer<void>();
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      try {
        final now = DateTime.now();
        await _service.applySchedule(
          prefs: _prefs,
          tasks: _tasks.timedTasks(),
          goals: _goals.activeGoals(),
          pendingTransferCount: _tasks.transferCandidates(now: now).length +
              _goals.transferCandidates(now: now).length,
          unfinishedByDay: _tasks.unfinishedCountsByDay(),
          taskBacklogCount: _backlog.all.length,
          goalBacklogCount: _goalBacklog.all.length,
        );
      } catch (e, st) {
        // Планирование не критично — не роняем приложение. Но раньше ошибка
        // глоталась молча, из-за чего на Windows было не видно, что расписание
        // вообще падает. Теперь хотя бы логируем (debug-only).
        debugPrint('NotificationController.reschedule failed: $e\n$st');
      }
      if (!completer.isCompleted) completer.complete();
    });
    return completer.future;
  }

  /// Возвращает все настройки уведомлений к значениям по умолчанию и
  /// пересобирает расписание под них.
  Future<void> resetToDefaults() => _update(const NotificationPrefs());

  Future<void> _update(NotificationPrefs next) async {
    if (next == _prefs) return;
    _prefs = next;
    notifyListeners();
    await _storage.writeMap(_kNotifPrefsKey, _prefs.toJson());
    await reschedule();
  }

  // ── Сеттеры для экрана настроек ──────────────────────────────────────────
  Future<void> setEnabled(bool v) => _update(_prefs.copyWith(enabled: v));
  Future<void> setTaskReminders(bool v) =>
      _update(_prefs.copyWith(taskReminders: v));
  Future<void> setTaskLead(int minutes) =>
      _update(_prefs.copyWith(taskLeadMinutes: minutes));
  Future<void> setTaskEndReminders(bool v) =>
      _update(_prefs.copyWith(taskEndReminders: v));
  Future<void> setTaskEndLead(int minutes) =>
      _update(_prefs.copyWith(taskEndLeadMinutes: minutes));
  Future<void> setTaskUrgentAlerts(bool v) =>
      _update(_prefs.copyWith(taskUrgentAlerts: v));
  Future<void> setTaskOverdueAlerts(bool v) =>
      _update(_prefs.copyWith(taskOverdueAlerts: v));
  Future<void> setMorningPlan(bool v) =>
      _update(_prefs.copyWith(morningPlan: v));
  Future<void> setMorningTime(int minutes) =>
      _update(_prefs.copyWith(morningMinutes: minutes));
  Future<void> setEveningReview(bool v) =>
      _update(_prefs.copyWith(eveningReview: v));
  Future<void> setEveningTime(int minutes) =>
      _update(_prefs.copyWith(eveningMinutes: minutes));
  Future<void> setGeneralReminders(bool v) =>
      _update(_prefs.copyWith(generalReminders: v));
  Future<void> setWeeklyRetro(bool v) =>
      _update(_prefs.copyWith(weeklyRetro: v));
  Future<void> setRetroWeekday(int weekday) =>
      _update(_prefs.copyWith(retroWeekday: weekday.clamp(1, 7)));
  Future<void> setRetroTime(int minutes) =>
      _update(_prefs.copyWith(retroMinutes: minutes));
  Future<void> setTransferReminder(bool v) =>
      _update(_prefs.copyWith(transferReminder: v));
  Future<void> setTaskBacklogReminder(bool v) =>
      _update(_prefs.copyWith(taskBacklogReminder: v));
  Future<void> setGoalBacklogReminder(bool v) =>
      _update(_prefs.copyWith(goalBacklogReminder: v));
  Future<void> setGoalUrgentAlerts(bool v) =>
      _update(_prefs.copyWith(goalUrgentAlerts: v));
  Future<void> setGoalOverdueAlerts(bool v) =>
      _update(_prefs.copyWith(goalOverdueAlerts: v));
  Future<void> setGoalGeneralReminders(bool v) =>
      _update(_prefs.copyWith(goalGeneralReminders: v));
  Future<void> setQuietHoursEnabled(bool v) =>
      _update(_prefs.copyWith(quietHoursEnabled: v));
  Future<void> setQuietHours(int start, int end) =>
      _update(_prefs.copyWith(quietStart: start, quietEnd: end));

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }
}

final notificationControllerProvider =
    ChangeNotifierProvider<NotificationController>((ref) {
  return NotificationController(
    ref.read(localStorageProvider),
    ref.read(notificationServiceProvider),
    ref.read(taskRepositoryProvider),
    ref.read(goalRepositoryProvider),
    ref.read(backlogRepositoryProvider),
    ref.read(goalBacklogRepositoryProvider),
  );
});
