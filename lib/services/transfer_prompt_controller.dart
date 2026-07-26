import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/goal.dart';
import '../data/models/task.dart';
import '../data/repositories/goal_repository.dart';
import '../data/repositories/task_repository.dart';
import '../data/sources/local/local_storage.dart';

const _kTransferCheckKey = 'transfer_check';

/// Отслеживает, обработана ли уже ближайшая прошедшая граница 4:00 —
/// «живым» баннером (пока приложение было открыто) или догоняющим списком
/// (если приложение было закрыто в момент границы). Один и тот же
/// [lastCheck] используется обоими путями, чтобы не спрашивать дважды за
/// один и тот же «дневной цикл».
class TransferPromptController {
  TransferPromptController(this._storage, this._tasks, this._goals);

  final LocalStorage _storage;
  final TaskRepository _tasks;
  final GoalRepository _goals;

  DateTime? get lastCheck {
    final raw = _storage.readMap(_kTransferCheckKey);
    final iso = raw?['lastCheck'] as String?;
    return iso == null ? null : DateTime.parse(iso);
  }

  Future<void> markChecked(DateTime now) =>
      _storage.writeMap(_kTransferCheckKey, {'lastCheck': now.toIso8601String()});

  /// Последняя уже наступившая граница 4:00 (сегодня, если сейчас позже
  /// 4:00 — иначе вчера).
  DateTime _lastFourAmBoundary(DateTime now) {
    final todayFourAm = DateTime(now.year, now.month, now.day, 4);
    return now.isBefore(todayFourAm)
        ? todayFourAm.subtract(const Duration(days: 1))
        : todayFourAm;
  }

  /// true — с прошлого раза, когда мы проверяли перенос, наступила (и мы её
  /// ещё не обработали) хотя бы одна граница 4:00. Значит, приложение было
  /// закрыто в этот момент — нужен догоняющий список, а не живой баннер.
  bool missedBoundary(DateTime now) {
    final last = lastCheck;
    return last == null || last.isBefore(_lastFourAmBoundary(now));
  }

  List<Task> collectTaskCandidates(DateTime now) =>
      _tasks.transferCandidates(now: now);

  List<Goal> collectGoalCandidates(DateTime now) =>
      _goals.transferCandidates(now: now);
}

final transferPromptControllerProvider = Provider<TransferPromptController>((ref) {
  return TransferPromptController(
    ref.read(localStorageProvider),
    ref.read(taskRepositoryProvider),
    ref.read(goalRepositoryProvider),
  );
});
