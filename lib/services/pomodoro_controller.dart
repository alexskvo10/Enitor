import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/task.dart';
import '../data/repositories/task_repository.dart';
import '../data/sources/local/local_storage.dart';
import 'notification_service.dart';
import 'pomodoro_prefs.dart';
import 'sound_service.dart';

enum PomodoroPhase { idle, focus, paused, breakTime, finished }

const _kPomodoroStateKey = 'pomodoro_state';

/// Глобальный таймер Помодоро, привязанный к одной задаче.
///
/// Ключевая идея: завершённый фокус АВТОМАТИЧЕСКИ пишется в
/// [Task.actualMinutes] (накопительно) — аналитика точности оценок получает
/// «факт» без ручного ввода. При ручной остановке фиксируются прошедшие
/// ПОЛНЫЕ минуты (≥1), чтобы не терять честно отработанное время.
///
/// Длины фокуса и перерыва берутся из [PomodoroPrefsController] в момент
/// СТАРТА отрезка. Смена настройки посреди отсчёта идущий таймер не трогает:
/// иначе он либо прыгнул бы, либо мгновенно «досрочно закончился», а в
/// [Task.actualMinutes] уехало бы не то время, которое человек отработал.
///
/// Отсчёт идёт ПО ЧАСАМ, а не тиками: хранится момент конца отрезка
/// [_endsAt], тик лишь пересчитывает остаток. Android замораживает свёрнутое
/// приложение — тики при этом не приходят, и счётчик «на тиках» вставал,
/// продолжая с того же числа после возврата. Состояние к тому же пишется в
/// хранилище: выгруженное из памяти приложение поднимает таймер при
/// следующем запуске, а не теряет его вместе с отработанными минутами.
class PomodoroController extends ChangeNotifier {
  PomodoroController(
    this._taskRepo,
    this._prefs,
    this._storage, {
    NotificationService? alarms,
    DateTime Function()? clock,
  })  : _alarms = alarms,
        _now = clock ?? DateTime.now {
    _restore();
    // Следим за задачами: если отслеживаемая выполнена/удалена — выключаемся
    // (с фиксацией наработанного). Покрывает ВСЕ пути завершения.
    _sub = _taskRepo.watchAllTasks().listen(_onTasks);
  }

  final TaskRepository _taskRepo;
  final PomodoroPrefsController _prefs;
  final LocalStorage _storage;

  /// Уведомления о конце отрезков. null — в тестах и там, где сервиса нет.
  final NotificationService? _alarms;
  final DateTime Function() _now;
  final SoundService _sound = SoundService();
  StreamSubscription<List<Task>>? _sub;

  Timer? _ticker;

  /// Момент конца идущего отрезка (фокус или перерыв). В паузе и вне отсчёта
  /// — null: на паузе остаток лежит в [remainingSeconds] и не тает.
  DateTime? _endsAt;

  PomodoroPhase phase = PomodoroPhase.idle;
  String? taskId;
  String taskTitle = '';
  int totalSeconds = 0;
  int remainingSeconds = 0;

  /// Сколько минут уже записано в actualMinutes за эту сессию.
  int sessionMinutes = 0;

  /// Номер фокус-сессии в текущей непрерывной серии по этой задаче (1, 2, 3…
  /// при повторных «Ещё фокус» без остановки). Сбрасывается при stop/новом
  /// startFocus — это не общий счётчик за день, а счётчик текущей серии.
  int sessionNumber = 0;

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
    sessionNumber = 1;
    _begin(PomodoroPhase.focus, _prefs.focusMinutes * 60);
  }

  /// Ещё один цикл фокуса по той же задаче (из состояния finished).
  void anotherFocus() {
    if (taskId == null) return;
    sessionNumber++;
    _begin(PomodoroPhase.focus, _prefs.focusMinutes * 60);
  }

  void pause() {
    if (phase != PomodoroPhase.focus) return;
    _ticker?.cancel();
    _syncRemaining();
    _endsAt = null;
    phase = PomodoroPhase.paused;
    _changed();
  }

  void resume() {
    if (phase != PomodoroPhase.paused) return;
    phase = PomodoroPhase.focus;
    _endsAt = _now().add(Duration(seconds: remainingSeconds));
    _startTicker();
    _changed();
  }

  void skipBreak() {
    if (phase != PomodoroPhase.breakTime) return;
    _ticker?.cancel();
    _endsAt = null;
    phase = PomodoroPhase.finished;
    _changed();
  }

  /// Стоп: в фокусе/паузе — фиксируем прошедшие полные минуты, закрываем.
  void stop() {
    _ticker?.cancel();
    _syncRemaining();
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

  /// Начинает отрезок. [startedAt] — когда он начался на самом деле: перерыв
  /// после фокуса, закончившегося в фоне, отсчитывается от конца фокуса, а
  /// не от момента, когда приложение снова открыли.
  void _begin(PomodoroPhase p, int seconds, {DateTime? startedAt}) {
    phase = p;
    totalSeconds = seconds;
    remainingSeconds = seconds;
    _endsAt = (startedAt ?? _now()).add(Duration(seconds: seconds));
    _startTicker();
    _changed();
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _advance());
  }

  /// Остаток идущего отрезка по часам. Округление вверх: «0» на экране —
  /// только когда время действительно вышло.
  void _syncRemaining() {
    final end = _endsAt;
    if (end == null) return;
    final ms = end.difference(_now()).inMilliseconds;
    remainingSeconds = ms <= 0 ? 0 : (ms / 1000).ceil();
  }

  /// Сверяется с часами и проводит все отрезки, которые успели закончиться:
  /// за время в фоне мог пройти и фокус, и следующий за ним перерыв.
  /// [sound] — false при подъёме из хранилища: сигнал о давно прошедшем
  /// конце прозвучал бы невпопад, прямо при запуске.
  void _advance({bool sound = true}) {
    var played = !sound;
    while (true) {
      final end = _endsAt;
      if (end == null) return;
      _syncRemaining();
      if (remainingSeconds > 0) {
        notifyListeners();
        return;
      }
      if (!played) {
        _sound.playPomodoroDone();
        played = true;
      }
      if (phase == PomodoroPhase.focus) {
        // Фокус завершён: пишем факт, авто-стартуем перерыв. Длина берётся из
        // totalSeconds, а не из настройки: настройку могли поменять посреди
        // отсчёта, и тогда в факт уехало бы не отработанное время.
        _commit(totalSeconds ~/ 60);
        _begin(
          PomodoroPhase.breakTime,
          _prefs.breakMinutes * 60,
          startedAt: end,
        );
      } else {
        _ticker?.cancel();
        _endsAt = null;
        phase = PomodoroPhase.finished;
        _changed();
        return;
      }
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
    sessionNumber = 0;
    _endsAt = null;
    _changed();
  }

  /// Смена фазы: сохранить состояние, переставить уведомления, перерисовать.
  /// Каждую секунду НЕ зовётся — тик меняет только остаток, а тот выводится
  /// из [_endsAt] и в хранилище не нужен.
  void _changed() {
    _persist();
    _syncAlarms();
    notifyListeners();
  }

  void _persist() {
    if (phase == PomodoroPhase.idle) {
      _storage.remove(_kPomodoroStateKey);
      return;
    }
    _storage.writeMap(_kPomodoroStateKey, {
      'phase': phase.name,
      'taskId': taskId,
      'taskTitle': taskTitle,
      'totalSeconds': totalSeconds,
      'remainingSeconds': remainingSeconds,
      'endsAtMs': _endsAt?.millisecondsSinceEpoch,
      'sessionMinutes': sessionMinutes,
      'sessionNumber': sessionNumber,
    });
  }

  void _restore() {
    try {
      final raw = _storage.readMap(_kPomodoroStateKey);
      if (raw == null) return;
      final p = PomodoroPhase.values.byName(raw['phase'] as String);
      final endsAtMs = raw['endsAtMs'] as int?;
      final running = p == PomodoroPhase.focus || p == PomodoroPhase.breakTime;
      // Идущий отрезок без момента конца досчитать не из чего.
      if (p == PomodoroPhase.idle || (running && endsAtMs == null)) {
        throw const FormatException('inconsistent pomodoro state');
      }
      phase = p;
      taskId = raw['taskId'] as String?;
      taskTitle = raw['taskTitle'] as String? ?? '';
      totalSeconds = raw['totalSeconds'] as int;
      remainingSeconds = raw['remainingSeconds'] as int;
      sessionMinutes = raw['sessionMinutes'] as int? ?? 0;
      sessionNumber = raw['sessionNumber'] as int? ?? 1;
      if (running) {
        _endsAt = DateTime.fromMillisecondsSinceEpoch(endsAtMs!);
        _startTicker();
        _advance(sound: false);
      }
    } catch (_) {
      // Битый или чужой ключ — не повод ронять старт: таймер просто пуст.
      _ticker?.cancel();
      _endsAt = null;
      phase = PomodoroPhase.idle;
      taskId = null;
      _storage.remove(_kPomodoroStateKey);
    }
  }

  /// Уведомления на конец фокуса и перерыва — чтобы свёрнутое приложение
  /// всё равно сказало, что отрезок кончился. Перерыв планируется сразу
  /// вместе с фокусом: он стартует сам, а приложение к тому моменту спит.
  void _syncAlarms() {
    final alarms = _alarms;
    if (alarms == null) return;
    final end = _endsAt;
    DateTime? focusEnd, breakEnd;
    if (end != null && phase == PomodoroPhase.focus) {
      focusEnd = end;
      breakEnd = end.add(Duration(minutes: _prefs.breakMinutes));
    } else if (end != null && phase == PomodoroPhase.breakTime) {
      breakEnd = end;
    }
    alarms.setPomodoroAlarms(
      focusEnd: focusEnd,
      breakEnd: breakEnd,
      taskTitle: taskTitle,
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    _ticker?.cancel();
    _sound.dispose();
    super.dispose();
  }
}

/// Сервис уведомлений для таймера. Отдельным провайдером с null по
/// умолчанию, а не [notificationServiceProvider] напрямую: тот без
/// переопределения бросает, а таймер поднимается и в тестах виджетов.
final pomodoroAlarmsProvider = Provider<NotificationService?>((ref) => null);

final pomodoroProvider = ChangeNotifierProvider<PomodoroController>((ref) {
  return PomodoroController(
    ref.read(taskRepositoryProvider),
    ref.read(pomodoroPrefsProvider),
    ref.read(localStorageProvider),
    alarms: ref.read(pomodoroAlarmsProvider),
  );
});
