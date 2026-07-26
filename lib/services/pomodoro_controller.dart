import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/task.dart';
import '../data/repositories/task_repository.dart';
import 'sound_service.dart';

/// Длительности цикла. Вынесены в константы — при желании легко сделать
/// настраиваемыми (экран настроек, этап 7).
const kPomodoroFocusMinutes = 25;
const kPomodoroBreakMinutes = 5;

enum PomodoroPhase { idle, focus, paused, breakTime, finished }

/// Глобальный таймер Помодоро, привязанный к одной задаче.
///
/// Ключевая идея: завершённый фокус АВТОМАТИЧЕСКИ пишется в
/// [Task.actualMinutes] (накопительно) — аналитика точности оценок получает
/// «факт» без ручного ввода. При ручной остановке фиксируются прошедшие
/// ПОЛНЫЕ минуты (≥1), чтобы не терять честно отработанное время.
class PomodoroController extends ChangeNotifier {
  PomodoroController(this._taskRepo) {
    // Следим за задачами: если отслеживаемая выполнена/удалена — выключаемся
    // (с фиксацией наработанного). Покрывает ВСЕ пути завершения.
    _sub = _taskRepo.watchAllTasks().listen(_onTasks);
  }

  final TaskRepository _taskRepo;
  final SoundService _sound = SoundService();
  StreamSubscription<List<Task>>? _sub;

  Timer? _ticker;
  PomodoroPhase phase = PomodoroPhase.idle;
  String? taskId;
  String taskTitle = '';
  int totalSeconds = 0;
  int remainingSeconds = 0;

  /// Сколько минут уже записано в actualMinutes за эту сессию.
  int sessionMinutes = 0;

  bool get isActive => phase != PomodoroPhase.idle;

  double get progress =>
      totalSeconds == 0 ? 0 : 1 - remainingSeconds / totalSeconds;

  /// Запускает фокус по задаче. Если шёл таймер по другой задаче —
  /// останавливаем его (с фиксацией частичного фокуса).
  void startFocus(Task task) {
    stop();
    taskId = task.id;
    taskTitle = task.title;
    sessionMinutes = 0;
    _begin(PomodoroPhase.focus, kPomodoroFocusMinutes * 60);
  }

  /// Ещё один цикл фокуса по той же задаче (из состояния finished).
  void anotherFocus() {
    if (taskId == null) return;
    _begin(PomodoroPhase.focus, kPomodoroFocusMinutes * 60);
  }

  void pause() {
    if (phase != PomodoroPhase.focus) return;
    _ticker?.cancel();
    phase = PomodoroPhase.paused;
    notifyListeners();
  }

  void resume() {
    if (phase != PomodoroPhase.paused) return;
    phase = PomodoroPhase.focus;
    _startTicker();
    notifyListeners();
  }

  void skipBreak() {
    if (phase != PomodoroPhase.breakTime) return;
    _ticker?.cancel();
    phase = PomodoroPhase.finished;
    notifyListeners();
  }

  /// Стоп: в фокусе/паузе — фиксируем прошедшие полные минуты, закрываем.
  void stop() {
    _ticker?.cancel();
    if (phase == PomodoroPhase.focus || phase == PomodoroPhase.paused) {
      final elapsedMin = (totalSeconds - remainingSeconds) ~/ 60;
      if (elapsedMin >= 1) _commit(elapsedMin);
    }
    _reset();
  }

  /// Закрыть баннер из состояния «Готово».
  void dismiss() => _reset();

  /// Останавливает таймер, если он отслеживает задачу [id]. Возвращает true,
  /// если что-то остановили. Для явного вызова из обработчика завершения,
  /// чтобы факт был зафиксирован ДО решения «спрашивать ли время».
  bool stopIfTracking(String id) {
    if (taskId != id || phase == PomodoroPhase.idle) return false;
    stop();
    return true;
  }

  /// Реакция на изменения задач: отслеживаемая выполнена/удалена → выключаемся.
  void _onTasks(List<Task> tasks) {
    final id = taskId;
    if (id == null || phase == PomodoroPhase.idle) return;
    final t = tasks.cast<Task?>().firstWhere(
          (t) => t?.id == id,
          orElse: () => null,
        );
    if (t == null || t.isCompleted) stop();
  }

  void _begin(PomodoroPhase p, int seconds) {
    phase = p;
    totalSeconds = seconds;
    remainingSeconds = seconds;
    _startTicker();
    notifyListeners();
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    if (remainingSeconds > 0) {
      remainingSeconds--;
      notifyListeners();
      return;
    }
    _ticker?.cancel();
    _sound.playPomodoroDone();
    if (phase == PomodoroPhase.focus) {
      // Фокус завершён: пишем факт, авто-стартуем перерыв.
      _commit(kPomodoroFocusMinutes);
      _begin(PomodoroPhase.breakTime, kPomodoroBreakMinutes * 60);
    } else if (phase == PomodoroPhase.breakTime) {
      phase = PomodoroPhase.finished;
      notifyListeners();
    }
  }

  void _commit(int minutes) {
    final id = taskId;
    if (id == null) return;
    sessionMinutes += minutes;
    // Задача могла быть удалена — addActualMinutes тогда no-op.
    _taskRepo.addActualMinutes(id, minutes);
  }

  void _reset() {
    phase = PomodoroPhase.idle;
    taskId = null;
    taskTitle = '';
    totalSeconds = 0;
    remainingSeconds = 0;
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _ticker?.cancel();
    _sound.dispose();
    super.dispose();
  }
}

final pomodoroProvider = ChangeNotifierProvider<PomodoroController>((ref) {
  return PomodoroController(ref.read(taskRepositoryProvider));
});
