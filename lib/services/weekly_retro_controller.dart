import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/utils/date_utils.dart';
import '../data/sources/local/local_storage.dart';
import 'notification_controller.dart';
import 'notification_prefs.dart';

const _kWeeklyRetroKey = 'weekly_retro_check';

/// Понедельник недели, которую разбираем на момент [now]: последняя
/// ПОЛНОСТЬЮ завершённая.
///
/// Текущая неделя не закрыта по определению, поэтому это всегда предыдущая.
/// Через [effectiveDay] — по правилу дня приложения ночь до 4:00 ещё
/// принадлежит уходящему дню, а значит и уходящей неделе.
DateTime retroReviewWeekStart(DateTime now) =>
    startOfWeek(effectiveDay(now)).subtract(const Duration(days: 7));

/// Момент, с которого разбор недели [retroReviewWeekStart] становится
/// доступен: настроенные [weekday] (1..7) и [minutes] внутри ТЕКУЩЕЙ (ещё
/// идущей) недели.
DateTime retroDueAt(
  DateTime now, {
  required int weekday,
  required int minutes,
}) {
  final currentWeekMonday =
      retroReviewWeekStart(now).add(const Duration(days: 7));
  final day = currentWeekMonday.add(Duration(days: weekday - 1));
  return DateTime(day.year, day.month, day.day)
      .add(Duration(minutes: minutes));
}

/// Решает, пора ли показать окно с разбором прошедшей недели, и помнит,
/// разбор какой недели уже показывали.
///
/// Пара к уведомлению «Итоги недели» (см. [NotificationPrefs.weeklyRetro]):
/// уведомление зовёт в приложение в назначенный момент, окно встречает при
/// первом же открытии после него. Один и тот же день/время управляют обоими.
class WeeklyRetroController {
  WeeklyRetroController(this._storage, this._notifications);

  final LocalStorage _storage;
  final NotificationController _notifications;

  NotificationPrefs get _prefs => _notifications.prefs;

  /// Понедельник недели, разбор которой уже показывали. null — ещё ни разу.
  DateTime? get lastShownWeek {
    final raw = _storage.readMap(_kWeeklyRetroKey);
    final iso = raw?['lastShownWeek'] as String?;
    if (iso == null) return null;
    return dateOnly(DateTime.parse(iso));
  }

  Future<void> markShown(DateTime weekStart) => _storage.writeMap(
        _kWeeklyRetroKey,
        {'lastShownWeek': dateOnly(weekStart).toIso8601String()},
      );

  /// См. [retroReviewWeekStart].
  DateTime reviewWeekStart(DateTime now) => retroReviewWeekStart(now);

  /// См. [retroDueAt] — с текущими настройками дня и времени.
  DateTime dueAt(DateTime now) => retroDueAt(
        now,
        weekday: _prefs.retroWeekday,
        minutes: _prefs.retroMinutes,
      );

  /// Пора ли показывать окно.
  ///
  /// Показ «догоняющий»: если в назначенный вечер приложение не открывали,
  /// окно дождётся следующего открытия — хоть в среду. Иначе разбор просто
  /// не случался бы у всех, у кого другой ритм. Со сменой недели цель
  /// сдвигается сама, и пропущенная неделя больше не всплывает.
  bool shouldShow(DateTime now) {
    if (!_prefs.enabled || !_prefs.weeklyRetro) return false;
    final week = reviewWeekStart(now);
    final last = lastShownWeek;
    if (last != null && !last.isBefore(week)) return false;
    return !now.isBefore(dueAt(now));
  }
}

final weeklyRetroControllerProvider = Provider<WeeklyRetroController>((ref) {
  return WeeklyRetroController(
    ref.read(localStorageProvider),
    ref.read(notificationControllerProvider),
  );
});
