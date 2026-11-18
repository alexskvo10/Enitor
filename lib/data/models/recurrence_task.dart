import '../../core/utils/date_utils.dart';
import 'recurrence_rule.dart';
import 'task.dart';

/// Id экземпляра повтора — одинаковый на всех устройствах и на сервере.
/// Со случайным id два синхронизуемых устройства создали бы каждое свою
/// задачу правила на один и тот же день.
String recurrenceTaskId(String ruleId, DateTime day) {
  String two(int v) => v.toString().padLeft(2, '0');
  return 'r-$ruleId-${day.year}${two(day.month)}${two(day.day)}';
}

/// Экземпляр правила [rule] на день [day] — без прогресса и отметок.
Task taskFromRule(
  RecurrenceRule rule,
  DateTime day, {
  required int order,
  required DateTime now,
  bool Function(String goalId)? goalOn,
}) {
  final goalId = rule.goalId;
  final d = dateOnly(day);
  final id = recurrenceTaskId(rule.id, d);
  return Task(
    id: id,
    title: rule.taskTitle,
    description: rule.taskDescription,
    date: d,
    order: order,
    createdAt: now,
    updatedAt: now,
    recurrenceRuleId: rule.id,
    startMinutes: rule.startMinutes,
    endMinutes: rule.endMinutes,
    estimatedMinutes: rule.estimatedMinutes,
    targetCount: rule.targetCount,
    subtasks: [
      for (var i = 0; i < rule.subtaskTitles.length; i++)
        SubTask(id: '$id-s$i', title: rule.subtaskTitles[i]),
    ],
    priority: rule.priority,
    tags: rule.tags,
    // Цель правила — только если она идёт в этот день: серия живёт дольше
    // месяца, а декабрьская задача в ноябрьскую цель не считается.
    goalId: goalId != null && (goalOn?.call(goalId) ?? false) ? goalId : null,
  );
}

/// Какую из нескольких задач одного правила на один день оставить. Выбор
/// должен совпадать на всех устройствах — они видят одинаковый набор и
/// независимо друг от друга удаляют одни и те же лишние.
/// Отрицательное значение — [a] лучше.
int compareRecurrenceDuplicates(Task a, Task b) {
  if (a.isCompleted != b.isCompleted) return a.isCompleted ? -1 : 1;
  final ar = a.id.startsWith('r-'), br = b.id.startsWith('r-');
  if (ar != br) return ar ? -1 : 1;
  final byTime = b.updatedAt.compareTo(a.updatedAt);
  if (byTime != 0) return byTime;
  return a.id.compareTo(b.id);
}
