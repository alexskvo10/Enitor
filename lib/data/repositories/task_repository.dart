import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/utils/date_utils.dart';
import '../../core/utils/haptics.dart';
import '../models/backlog_item.dart';
import '../models/day_template.dart';
import '../models/recurrence_rule.dart';
import '../models/task.dart';
import '../sources/local/local_storage.dart';
import 'backlog_repository.dart';
import 'goal_repository.dart';
import 'recurrence_repository.dart';
import 'stats_repository.dart';

const _kTasksKey = 'tasks';
const _uuid = Uuid();

/// Ключ сортировки: сначала задачи с временем (по startMinutes или endMinutes),
/// затем задачи без времени — по приоритету (высокий выше), внутри — по order.
int _sortKey(Task t) {
  final primary = t.startMinutes ?? t.endMinutes;
  if (primary != null) return primary;
  final prioritySlot = TaskPriority.high.index - t.priority.index; // 0..3
  return 1440 + prioritySlot * 100000 + t.order;
}

class TaskRepository {
  TaskRepository(
    this._storage,
    this._statsRepo,
    this._recurrenceRepo,
    this._goalRepo,
    this._backlogRepo,
  ) {
    _reload();
  }

  final LocalStorage _storage;
  final StatsRepository _statsRepo;
  final RecurrenceRepository _recurrenceRepo;
  final GoalRepository _goalRepo;
  final BacklogRepository _backlogRepo;

  /// Пересчитывает вклад привязанных задач в цель [goalId] (сумма вкладов).
  Future<void> _syncGoal(String? goalId) async {
    if (goalId == null) return;
    final sum = _cache
        .where((t) => t.goalId == goalId)
        .fold<int>(0, (s, t) => s + t.goalContribution);
    await _goalRepo.setLinkedProgress(goalId, sum);
  }

  final _controller = StreamController<List<Task>>.broadcast();
  List<Task> _cache = [];

  void _reload() {
    _cache = _storage.readList(_kTasksKey).map(Task.fromJson).toList()
      ..sort((a, b) => _sortKey(a).compareTo(_sortKey(b)));
    _controller.add(_cache);
  }

  Future<void> _save() async {
    await _storage.writeList(
      _kTasksKey,
      _cache.map((t) => t.toJson()).toList(),
    );
    _controller.add(List.unmodifiable(_cache));
  }

  Stream<List<Task>> watchAllTasks() async* {
    yield List.unmodifiable(_cache);
    await for (final all in _controller.stream) {
      yield all;
    }
  }

  Stream<List<Task>> watchTasksForDay(DateTime date) async* {
    final day = dateOnly(date);
    // Перед первым yield досоздаём задачи из активных правил повторения.
    // Это ленивая материализация: мы не плодим задачи на годы вперёд,
    // а создаём их только когда пользователь реально открывает день.
    await ensureRecurrencesForDay(day);

    List<Task> filter(List<Task> all) =>
        all.where((t) => dateOnly(t.date) == day).toList()
          ..sort((a, b) => _sortKey(a).compareTo(_sortKey(b)));

    yield filter(_cache);
    await for (final all in _controller.stream) {
      yield filter(all);
    }
  }

  /// Лениво материализует задачи из правил повторения для указанного дня.
  /// Идемпотентно: если для правила уже есть задача в этот день, ничего
  /// не делает. Не трогает прошлые дни без правил.
  Future<void> ensureRecurrencesForDay(DateTime date) async {
    final day = dateOnly(date);
    final existingRuleIds = <String>{};
    for (final t in _cache) {
      if (t.recurrenceRuleId != null && dateOnly(t.date) == day) {
        existingRuleIds.add(t.recurrenceRuleId!);
      }
    }
    final now = DateTime.now();
    var added = false;
    var order = _cache.where((t) => dateOnly(t.date) == day).length;
    for (final rule in _recurrenceRepo.all) {
      if (existingRuleIds.contains(rule.id)) continue;
      if (!rule.occursOn(day)) continue;
      _cache.add(Task(
        id: _uuid.v4(),
        title: rule.taskTitle,
        description: rule.taskDescription,
        date: day,
        order: order++,
        createdAt: now,
        updatedAt: now,
        recurrenceRuleId: rule.id,
        startMinutes: rule.startMinutes,
        endMinutes: rule.endMinutes,
        estimatedMinutes: rule.estimatedMinutes,
        targetCount: rule.targetCount,
        subtasks: [
          for (final t in rule.subtaskTitles) SubTask(id: _uuid.v4(), title: t),
        ],
        priority: rule.priority,
        tags: rule.tags,
      ));
      added = true;
    }
    if (added) {
      await _save();
      await _statsRepo.recompute(day, tasksForDay(day));
    }
  }

  /// «Эту и все будущие» — обрезаем правило датой (день до текущего),
  /// удаляем будущие невыполненные экземпляры. Прошлая статистика остаётся.
  Future<void> deleteOccurrencesFrom(Task task) async {
    final ruleId = task.recurrenceRuleId;
    if (ruleId == null) return;
    final fromDay = dateOnly(task.date);
    final rule = _recurrenceRepo.byId(ruleId);
    if (rule != null) {
      await _recurrenceRepo.update(rule.copyWith(
        endDate: fromDay.subtract(const Duration(days: 1)),
        updatedAt: DateTime.now(),
      ));
    }
    final affectedDays = <DateTime>{};
    _cache.removeWhere((t) {
      if (t.recurrenceRuleId != ruleId) return false;
      if (t.isCompleted) return false;
      if (dateOnly(t.date).isBefore(fromDay)) return false;
      affectedDays.add(dateOnly(t.date));
      return true;
    });
    await _save();
    for (final d in affectedDays) {
      await _statsRepo.recompute(d, tasksForDay(d));
    }
  }

  /// «Всю серию» — удаляем правило и все экземпляры начиная с [cutoffDate].
  /// Экземпляры в прошлых (read-only) днях — до [cutoffDate] — не трогаем:
  /// историю редактировать нельзя независимо от статуса выполнения.
  /// Статистика пересчитывается для затронутых дней.
  Future<void> deleteEntireSeries(
      String ruleId, {required DateTime cutoffDate}) async {
    await _recurrenceRepo.delete(ruleId);
    final fromDay = dateOnly(cutoffDate);
    final affectedDays = <DateTime>{};
    _cache.removeWhere((t) {
      if (t.recurrenceRuleId != ruleId) return false;
      if (dateOnly(t.date).isBefore(fromDay)) return false; // прошлый день
      affectedDays.add(dateOnly(t.date));
      return true;
    });
    await _save();
    for (final d in affectedDays) {
      await _statsRepo.recompute(d, tasksForDay(d));
    }
  }

  /// Создаёт правило и сразу материализует экземпляр на стартовый день,
  /// если правило срабатывает в этот день.
  Future<RecurrenceRule> createRecurrence({
    required String title,
    String? description,
    required RecurrenceKind kind,
    required DateTime startDate,
    List<int> weekdays = const [],
    List<int> monthDays = const [],
    int intervalDays = 1,
    int? startMinutes,
    int? endMinutes,
    int? estimatedMinutes,
    int? targetCount,
    DateTime? endDate,
    List<String> subtaskTitles = const [],
    TaskPriority priority = TaskPriority.none,
    List<String> tags = const [],
  }) async {
    final now = DateTime.now();
    final rule = RecurrenceRule(
      id: _uuid.v4(),
      taskTitle: title,
      taskDescription: description,
      kind: kind,
      startDate: dateOnly(startDate),
      endDate: endDate == null ? null : dateOnly(endDate),
      createdAt: now,
      updatedAt: now,
      weekdays: weekdays,
      monthDays: monthDays,
      intervalDays: intervalDays,
      startMinutes: startMinutes,
      endMinutes: endMinutes,
      estimatedMinutes: estimatedMinutes,
      targetCount: targetCount,
      subtaskTitles: subtaskTitles,
      priority: priority,
      tags: tags,
    );
    await _recurrenceRepo.add(rule);
    await ensureRecurrencesForDay(startDate);
    return rule;
  }

  /// Актуальная задача из кэша по id (или null). Синхронно.
  Task? taskById(String id) {
    for (final t in _cache) {
      if (t.id == id) return t;
    }
    return null;
  }

  List<Task> tasksForDay(DateTime date) {
    final day = dateOnly(date);
    return _cache.where((t) => dateOnly(t.date) == day).toList()
      ..sort((a, b) => _sortKey(a).compareTo(_sortKey(b)));
  }

  /// Невыполненные задачи с временем начала на ближайшие [days] дней — без
  /// фильтра «старт ещё впереди» (нужны не только напоминания к началу, но и
  /// к концу / «требует внимания» / «просрочена», которые должны сработать и
  /// для уже начавшейся задачи). Каждый конкретный момент проверяется на
  /// стороне планировщика уведомлений. Отсортированы по моменту старта.
  List<Task> timedTasks({int days = 2}) {
    final now = DateTime.now();
    final result = <Task>[];
    for (var d = 0; d < days; d++) {
      final day = dateOnly(now.add(Duration(days: d)));
      for (final t in tasksForDay(day)) {
        if (t.isCompleted || t.isTransferred) continue;
        if (t.startMinutes == null) continue;
        result.add(t);
      }
    }
    result.sort((a, b) {
      final byDate = dateOnly(a.date).compareTo(dateOnly(b.date));
      return byDate != 0 ? byDate : a.startMinutes!.compareTo(b.startMinutes!);
    });
    return result;
  }

  /// Задачи дня для МАРКЕРОВ календаря: реальные + «виртуальные» из активных
  /// правил повторения (в пределах endDate). Так точка появляется сразу, без
  /// материализации, и не плодится за пределами «В течение».
  List<Task> plannedForDay(DateTime date) {
    final day = dateOnly(date);
    final actual = _cache.where((t) => dateOnly(t.date) == day).toList();
    final existingRuleIds = actual
        .where((t) => t.recurrenceRuleId != null)
        .map((t) => t.recurrenceRuleId!)
        .toSet();
    final now = DateTime.now();
    final result = List<Task>.from(actual);
    for (final rule in _recurrenceRepo.all) {
      if (existingRuleIds.contains(rule.id)) continue;
      if (!rule.occursOn(day)) continue;
      result.add(Task(
        id: 'virtual-${rule.id}-${day.millisecondsSinceEpoch}',
        title: rule.taskTitle,
        date: day,
        createdAt: now,
        updatedAt: now,
        targetCount: rule.targetCount,
      ));
    }
    return result;
  }

  Future<void> addTask(Task task) async {
    _cache.add(task);
    await _save();
    await _statsRepo.recompute(task.date, tasksForDay(task.date));
    await _syncGoal(task.goalId);
  }

  Future<Task> createAndAdd({
    required String title,
    required DateTime date,
    String? description,
    int? startMinutes,
    int? endMinutes,
    int? estimatedMinutes,
    int? targetCount,
    String? goalId,
    List<String> subtaskTitles = const [],
    TaskPriority priority = TaskPriority.none,
    List<String> tags = const [],
  }) async {
    final now = DateTime.now();
    final task = Task(
      id: _uuid.v4(),
      title: title,
      description: description,
      date: dateOnly(date),
      order: tasksForDay(date).length,
      createdAt: now,
      updatedAt: now,
      startMinutes: startMinutes,
      endMinutes: endMinutes,
      estimatedMinutes: estimatedMinutes,
      targetCount: targetCount,
      goalId: goalId,
      subtasks: [
        for (final t in subtaskTitles) SubTask(id: _uuid.v4(), title: t),
      ],
      priority: priority,
      tags: tags,
    );
    await addTask(task);
    return task;
  }

  /// Изменяет счётчик задачи на [delta] (обычно +1/−1).
  Future<void> incrementCounter(Task task, int delta) =>
      setCounterProgress(task, task.progressCount + delta);

  /// Устанавливает счётчик в точное [value] (для ручного ввода), зажимая в
  /// [0, target]. При достижении цели задача помечается выполненной, при
  /// опускании ниже — снова невыполненной.
  Future<void> setCounterProgress(Task task, int value) async {
    final idx = _cache.indexWhere((t) => t.id == task.id);
    if (idx == -1) return;
    final cur = _cache[idx];
    if (!cur.isCounter) return;
    final newCount = value.clamp(0, cur.targetCount!);
    if (newCount == cur.progressCount) return;
    final now = DateTime.now();
    final reached = newCount >= cur.targetCount!;
    if (reached && !cur.isCompleted) Haptics.completed(); // счётчик добит до цели
    _cache[idx] = cur.copyWith(
      progressCount: newCount,
      completedAt: reached ? (cur.completedAt ?? now) : null,
      clearCompleted: !reached,
      updatedAt: now,
    );
    await _save();
    await _statsRepo.recompute(cur.date, tasksForDay(cur.date));
    await _syncGoal(cur.goalId);
  }

  /// Переключает подзадачу. Когда все выполнены — задача авто-выполняется
  /// (как счётчик); если снова не все — снимается выполнение.
  Future<void> toggleSubtask(Task task, String subtaskId) async {
    final idx = _cache.indexWhere((t) => t.id == task.id);
    if (idx == -1) return;
    final cur = _cache[idx];
    final subs = cur.subtasks
        .map((s) => s.id == subtaskId ? s.copyWith(done: !s.done) : s)
        .toList();
    final allDone = subs.isNotEmpty && subs.every((s) => s.done);
    final now = DateTime.now();
    if (allDone && !cur.isCompleted) Haptics.completed(); // последняя подзадача
    _cache[idx] = cur.copyWith(
      subtasks: subs,
      completedAt: allDone ? (cur.completedAt ?? now) : null,
      clearCompleted: !allDone,
      updatedAt: now,
    );
    await _save();
    await _statsRepo.recompute(cur.date, tasksForDay(cur.date));
    await _syncGoal(cur.goalId);
  }

  /// Отмечает все подзадачи как [done] разом и синхронизирует статус задачи
  /// (для «отметить задачу выполненной целиком»).
  Future<void> setAllSubtasksDone(Task task, bool done) async {
    final idx = _cache.indexWhere((t) => t.id == task.id);
    if (idx == -1) return;
    final cur = _cache[idx];
    if (cur.subtasks.isEmpty) return;
    final subs = cur.subtasks.map((s) => s.copyWith(done: done)).toList();
    final now = DateTime.now();
    if (done && !cur.isCompleted) Haptics.completed(); // отметка целиком
    _cache[idx] = cur.copyWith(
      subtasks: subs,
      completedAt: done ? (cur.completedAt ?? now) : null,
      clearCompleted: !done,
      updatedAt: now,
    );
    await _save();
    await _statsRepo.recompute(cur.date, tasksForDay(cur.date));
    await _syncGoal(cur.goalId);
  }

  Future<void> toggleCompleted(Task task) async {
    final idx = _cache.indexWhere((t) => t.id == task.id);
    if (idx == -1) return;
    // База — АКТУАЛЬНАЯ задача из кэша, а не переданный (возможно устаревший)
    // снимок из виджета: иначе copyWith затрёт поля, изменённые конкурентно
    // (например actualMinutes, только что записанный Помодоро-таймером).
    final cur = _cache[idx];
    final now = DateTime.now();
    if (!cur.isCompleted) Haptics.completed(); // переход в «выполнено»
    _cache[idx] = cur.copyWith(
      completedAt: cur.isCompleted ? null : now,
      clearCompleted: cur.isCompleted,
      updatedAt: now,
    );
    await _save();
    await _statsRepo.recompute(cur.date, tasksForDay(cur.date));
    await _syncGoal(cur.goalId);
  }

  Future<void> updateTask(Task updated) async {
    final idx = _cache.indexWhere((t) => t.id == updated.id);
    if (idx == -1) return;
    final old = _cache[idx];
    final oldDate = old.date;
    _cache[idx] = updated;
    await _save();
    await _statsRepo.recompute(updated.date, tasksForDay(updated.date));
    if (dateOnly(updated.date) != dateOnly(oldDate)) {
      await _statsRepo.recompute(oldDate, tasksForDay(oldDate));
    }
    // Привязка к цели могла измениться — пересчитываем обе.
    await _syncGoal(updated.goalId);
    if (old.goalId != updated.goalId) await _syncGoal(old.goalId);
  }

  /// Накопительно добавляет фактическое время (источник — Помодоро-таймер).
  /// Задача ищется по id: если удалена — тихий no-op.
  Future<void> addActualMinutes(String taskId, int minutes) async {
    final idx = _cache.indexWhere((t) => t.id == taskId);
    if (idx == -1) return;
    final cur = _cache[idx];
    _cache[idx] = cur.copyWith(
      actualMinutes: (cur.actualMinutes ?? 0) + minutes,
      updatedAt: DateTime.now(),
    );
    await _save();
  }

  Future<void> updateActualMinutes(Task task, int minutes) async {
    final idx = _cache.indexWhere((t) => t.id == task.id);
    if (idx == -1) return;
    // Используем _cache[idx], а не task — task это старый объект из виджета,
    // который может не иметь completedAt, установленного только что.
    _cache[idx] = _cache[idx].copyWith(
      actualMinutes: minutes,
      updatedAt: DateTime.now(),
    );
    await _save();
  }

  /// Ставит субъективную оценку качества (рефлексия). На статистику не влияет.
  Future<void> setQuality(Task task, int quality) async {
    final idx = _cache.indexWhere((t) => t.id == task.id);
    if (idx == -1) return;
    _cache[idx] = _cache[idx].copyWith(quality: quality);
    await _save();
  }

  Future<void> deleteTask(Task task) async {
    _cache.removeWhere((t) => t.id == task.id);
    await _save();
    await _statsRepo.recompute(task.date, tasksForDay(task.date));
    await _syncGoal(task.goalId);

    // Если удаляется перенесённая копия → отправляем в бэклог невыполненных
    if (task.transferredFromId != null && !task.isCompleted) {
      // Берём дату оригинала (если он ещё в кэше), иначе дату копии
      final original = _cache
          .where((t) => t.id == task.transferredFromId)
          .firstOrNull;
      await _backlogRepo.add(BacklogItem(
        id: _uuid.v4(),
        title: task.title,
        description: task.description,
        originalDate: original?.date ?? task.date,
        addedAt: DateTime.now(),
        startMinutes: task.startMinutes,
        endMinutes: task.endMinutes,
        estimatedMinutes: task.estimatedMinutes,
        targetCount: task.targetCount,
        progressCount: task.progressCount,
        subtaskTitles: task.subtasks.map((s) => s.title).toList(),
        priority: task.priority,
        tags: task.tags,
      ));
    }

    // Если это экземпляр из серии — добавляем дату как исключение, чтобы
    // plannedForDay не регенерировал виртуальный незавершённый дубль и маркер
    // календаря не показывал жёлтый вместо зелёного.
    final ruleId = task.recurrenceRuleId;
    if (ruleId != null) {
      final rule = _recurrenceRepo.byId(ruleId);
      if (rule != null) {
        final exDate = DateTime(task.date.year, task.date.month, task.date.day);
        final alreadyExcepted = rule.exceptDates
            .any((d) => DateTime(d.year, d.month, d.day) == exDate);
        if (!alreadyExcepted) {
          await _recurrenceRepo.update(
            rule.copyWith(
              exceptDates: [...rule.exceptDates, exDate],
              updatedAt: DateTime.now(),
            ),
          );
        }
      }
    }
  }

  Future<void> copyTasksTo({
    required List<Task> tasks,
    required DateTime targetDate,
  }) async {
    final now = DateTime.now();
    final target = dateOnly(targetDate);
    final existing = tasksForDay(target);
    var order = existing.length;
    for (final src in tasks) {
      _cache.add(Task(
        id: _uuid.v4(),
        title: src.title,
        description: src.description,
        date: target,
        order: order++,
        createdAt: now,
        updatedAt: now,
        // Копируем поля времени, оценку, счётчик и шаблон подзадач, но не
        // прогресс/статус/серию (подзадачи — свежие, не выполнены).
        startMinutes: src.startMinutes,
        endMinutes: src.endMinutes,
        estimatedMinutes: src.estimatedMinutes,
        targetCount: src.targetCount,
        subtasks: [
          for (final s in src.subtasks) SubTask(id: _uuid.v4(), title: s.title),
        ],
        priority: src.priority,
        tags: src.tags,
      ));
    }
    await _save();
    await _statsRepo.recompute(target, tasksForDay(target));
  }

  /// Применяет шаблон дня: добавляет его пункты как новые задачи на [date]
  /// (к существующим). Прогресс/выполнение — с нуля.
  Future<void> applyTemplate(
      List<TemplateItem> items, DateTime date) async {
    final now = DateTime.now();
    final target = dateOnly(date);
    var order = tasksForDay(target).length;
    for (final it in items) {
      _cache.add(Task(
        id: _uuid.v4(),
        title: it.title,
        description: it.description,
        date: target,
        order: order++,
        createdAt: now,
        updatedAt: now,
        startMinutes: it.startMinutes,
        endMinutes: it.endMinutes,
        estimatedMinutes: it.estimatedMinutes,
        targetCount: it.targetCount,
        subtasks: [
          for (final t in it.subtaskTitles) SubTask(id: _uuid.v4(), title: t),
        ],
        priority: it.priority,
        tags: it.tags,
      ));
    }
    await _save();
    await _statsRepo.recompute(target, tasksForDay(target));
  }

  /// Удаляет все задачи для указанного дня (обычные и экземпляры серий).
  Future<void> deleteAllForDay(DateTime date) async {
    final day = dateOnly(date);
    final affectedGoals = _cache
        .where((t) => dateOnly(t.date) == day && t.goalId != null)
        .map((t) => t.goalId!)
        .toSet();
    _cache.removeWhere((t) => dateOnly(t.date) == day);
    await _save();
    await _statsRepo.recompute(day, tasksForDay(day));
    for (final g in affectedGoals) {
      await _syncGoal(g);
    }
  }

  // ─── Перенос задач ────────────────────────────────────────────────────────

  /// Переносит задачу на [targetDate]:
  /// • создаёт копию на целевой дне (с [transferredFromId] = task.id)
  /// • помечает оригинал как [isTransferred] = true
  /// • статистика исходного дня НЕ пересчитывается (история неизменна)
  Future<void> transferTask(Task task, {required DateTime targetDate}) async {
    final now = DateTime.now();
    final target = dateOnly(targetDate);
    final copy = Task(
      id: _uuid.v4(),
      title: task.title,
      description: task.description,
      date: target,
      order: tasksForDay(target).length,
      startMinutes: task.startMinutes,
      endMinutes: task.endMinutes,
      estimatedMinutes: task.estimatedMinutes,
      targetCount: task.targetCount,
      progressCount: task.progressCount,
      // Переносим подзадачи С их состоянием (живая копия, не сбрасываем).
      subtasks: [
        for (final s in task.subtasks)
          SubTask(id: _uuid.v4(), title: s.title, done: s.done),
      ],
      priority: task.priority,
      tags: task.tags,
      transferredFromId: task.id,
      createdAt: now,
      updatedAt: now,
    );
    _cache.add(copy);
    // Помечаем оригинал
    final idx = _cache.indexWhere((t) => t.id == task.id);
    if (idx != -1) {
      _cache[idx] = _cache[idx].copyWith(isTransferred: true, updatedAt: now);
    }
    await _save();
    await _statsRepo.recompute(target, tasksForDay(target));
  }

  /// Переносит все невыполненные неповторяющиеся задачи дня [day] на [targetDate].
  Future<void> transferAllUncompletedForDay(
      DateTime day, {required DateTime targetDate}) async {
    final toTransfer = tasksForDay(day)
        .where((t) =>
            !t.isCompleted &&
            !t.isTransferred &&
            t.recurrenceRuleId == null &&
            t.transferredFromId == null)
        .toList();
    for (final t in toTransfer) {
      await transferTask(t, targetDate: targetDate);
    }
  }

  /// Невыполненные ОРИГИНАЛЫ из прошлых дней, которые ещё не переносили и от
  /// переноса которых пользователь явно не отказался ([transferDeclined]) —
  /// кандидаты на перенос сегодня. Чистый запрос, ничего не меняет: решение,
  /// переносить или нет, принимает пользователь (баннер/догоняющий список).
  List<Task> transferCandidates({required DateTime now}) {
    final today = dateOnly(now);
    return _cache
        .where((t) =>
            !t.isCompleted &&
            !t.isTransferred &&
            !t.transferDeclined &&
            t.recurrenceRuleId == null &&
            t.transferredFromId == null &&
            dateOnly(t.date).isBefore(today))
        .toList();
  }

  /// Переносит выбранные задачи на сегодня ([now]) — вызывается после
  /// подтверждения пользователем (баннер или догоняющий список).
  Future<void> transferSelected(List<Task> tasks, {required DateTime now}) async {
    final target = dateOnly(now);
    for (final t in tasks) {
      await transferTask(t, targetDate: target);
    }
  }

  /// Пользователь отказался переносить задачу — помечаем, чтобы больше не
  /// предлагать; задача остаётся обычной невыполненной в своём дне.
  Future<void> declineTransfer(Task task) async {
    final idx = _cache.indexWhere((t) => t.id == task.id);
    if (idx == -1) return;
    _cache[idx] =
        _cache[idx].copyWith(transferDeclined: true, updatedAt: DateTime.now());
    await _save();
  }

  /// Невыполненные КОПИИ из прошлых дней (которые уже переносили однажды, но
  /// так и не сделали) → уходят в бэклог «Невыполненные задачи». Тихая
  /// автоматическая механика списания — не тот же смысл, что «перенести или
  /// нет» (это уже вторая, а не первая, неудачная попытка).
  Future<void> demoteStaleTransferredCopies({required DateTime now}) async {
    final target = dateOnly(now);
    final staleCopies = _cache
        .where((t) =>
            !t.isCompleted &&
            !t.isTransferred &&
            t.recurrenceRuleId == null &&
            t.transferredFromId != null &&
            dateOnly(t.date).isBefore(target))
        .toList();
    for (final t in staleCopies) {
      await _sendToBacklogAndMark(t);
    }
  }

  /// Отправляет невыполненную копию в бэклог и помечает её [isTransferred]
  /// (серый след в прошлом дне). Статистика дня НЕ пересчитывается —
  /// история неизменна, как и при обычном переносе.
  Future<void> _sendToBacklogAndMark(Task copy) async {
    final original =
        _cache.where((t) => t.id == copy.transferredFromId).firstOrNull;
    await _backlogRepo.add(BacklogItem(
      id: _uuid.v4(),
      title: copy.title,
      description: copy.description,
      originalDate: original?.date ?? copy.date,
      addedAt: DateTime.now(),
      startMinutes: copy.startMinutes,
      endMinutes: copy.endMinutes,
      estimatedMinutes: copy.estimatedMinutes,
      targetCount: copy.targetCount,
      progressCount: copy.progressCount,
      subtaskTitles: copy.subtasks.map((s) => s.title).toList(),
      priority: copy.priority,
      tags: copy.tags,
    ));
    final idx = _cache.indexWhere((t) => t.id == copy.id);
    if (idx != -1) {
      _cache[idx] =
          _cache[idx].copyWith(isTransferred: true, updatedAt: DateTime.now());
      await _save();
    }
  }

  void dispose() => _controller.close();
}

final taskRepositoryProvider = Provider<TaskRepository>((ref) {
  final repo = TaskRepository(
    ref.watch(localStorageProvider),
    ref.watch(statsRepositoryProvider),
    ref.watch(recurrenceRepositoryProvider),
    ref.watch(goalRepositoryProvider),
    ref.watch(backlogRepositoryProvider),
  );
  ref.onDispose(repo.dispose);
  return repo;
});

final tasksForDayProvider =
    StreamProvider.family<List<Task>, DateTime>((ref, date) {
  return ref.watch(taskRepositoryProvider).watchTasksForDay(date);
});

final allTasksProvider = StreamProvider<List<Task>>((ref) {
  return ref.watch(taskRepositoryProvider).watchAllTasks();
});
