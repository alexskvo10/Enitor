import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/date_utils.dart';
import '../models/achievement.dart';
import '../models/task.dart';
import '../sources/local/local_storage.dart';
import 'goal_repository.dart';
import 'profile_repository.dart';
import 'rating_repository.dart';
import 'stats_repository.dart';
import 'task_repository.dart';

const _kUnlockedKey = 'unlocked_achievements';

/// Хранит множество уже разблокированных ачивок — только для де-дупликации
/// уведомлений. Текущий статус для отображения выводится из статистики.
class AchievementsRepository {
  AchievementsRepository(this._storage) {
    final raw = _storage.readMap(_kUnlockedKey);
    if (raw != null) {
      _seeded = raw['seeded'] as bool? ?? false;
      _ids = ((raw['ids'] as List?) ?? const [])
          .map((e) => e as String)
          .toSet();
    }
  }

  final LocalStorage _storage;
  Set<String> _ids = {};
  bool _seeded = false;

  Future<void> _save() => _storage.writeMap(_kUnlockedKey, {
        'seeded': _seeded,
        'ids': _ids.toList(),
      });

  /// Сверяет текущий набор разблокированных id с сохранённым.
  /// • Первый вызов (после установки) — «посев»: запоминаем всё молча, чтобы
  ///   не сыпать плашками о ранее заработанном. Возвращает пустой список.
  /// • Дальше — возвращает только НОВЫЕ разблокированные id (для уведомлений).
  Future<List<String>> sync(Set<String> currentlyUnlocked) async {
    if (!_seeded) {
      _ids = {...currentlyUnlocked};
      _seeded = true;
      await _save();
      return const [];
    }
    final newly =
        currentlyUnlocked.where((id) => !_ids.contains(id)).toList();
    if (newly.isEmpty) return const [];
    _ids.addAll(newly);
    await _save();
    return newly;
  }
}

final achievementsRepositoryProvider = Provider<AchievementsRepository>((ref) {
  return AchievementsRepository(ref.watch(localStorageProvider));
});

// ─── Агрегат статистики для ачивок ───────────────────────────────────────────

/// Единая логика «в срок» — см. [StatsRepository.taskIsOnTime].
bool _taskOnTime(Task t) => StatsRepository.taskIsOnTime(t);

/// Снимок агрегатов для ачивок. null — пока не все источники загрузились
/// (важно: на null НЕ запускаем «посев», иначе спам плашками на старте).
final achievementStatsProvider = Provider<AchievementStats?>((ref) {
  final tasks = ref.watch(allTasksProvider).value;
  final goals = ref.watch(allGoalsProvider).value;
  final streaks = ref.watch(streaksProvider).value;
  final profile = ref.watch(profileProvider).value;
  final dayStats = ref.watch(allDayStatsProvider).value;
  final dayRatings = ref.watch(allDayRatingsProvider).value;

  if (tasks == null ||
      goals == null ||
      streaks == null ||
      profile == null ||
      dayStats == null ||
      dayRatings == null) {
    return null;
  }

  final completed = tasks.where((t) => t.isCompleted).toList();
  final todayDate = today();

  return AchievementStats(
    tasksDone: completed.length,
    onTimeTasks: completed.where(_taskOnTime).length,
    quality10Tasks: completed.where((t) => t.quality == 10).length,
    goalsDone: goals.where((g) => g.completed).length,
    currentStreak: streaks.current,
    bestStreak: streaks.best,
    daysUsing: todayDate.difference(dateOnly(profile.startedAt)).inDays + 1,
    perfectDays: dayStats
        .where((s) =>
            s.totalTasks > 0 &&
            s.productivity != null &&
            s.productivity! >= 1.0 - 1e-9 &&
            !s.date.isAfter(todayDate))
        .length,
    day10Ratings: dayRatings.where((r) => r == 10).length,
  );
});

/// Все ачивки с вычисленным прогрессом. Пустой список — пока статистика грузится.
final achievementsProvider = Provider<List<EvaluatedAchievement>>((ref) {
  final stats = ref.watch(achievementStatsProvider);
  if (stats == null) return const [];
  return evaluateAchievements(stats);
});
