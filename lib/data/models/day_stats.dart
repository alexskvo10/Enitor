class DayStats {
  DayStats({
    required this.date,
    required this.totalTasks,
    required this.completedTasks,
    required this.updatedAt,
    this.onTimeCount = 0,
    this.lateCount = 0,
    double? completedFraction,
  }) : completedFraction = completedFraction ?? completedTasks.toDouble();

  final DateTime date;
  final int totalTasks;

  /// Число полностью выполненных задач (счётчик считается выполненным на 100%).
  final int completedTasks;

  /// Сумма дробного выполнения по задачам: обычная = 0/1, счётчик = доля
  /// прогресса (3/5 → 0.6). Используется для продуктивности.
  final double completedFraction;

  /// Выполненных задач — вовремя.
  final int onTimeCount;

  /// Выполненных задач — с опозданием.
  final int lateCount;

  final DateTime updatedAt;

  /// Продуктивность: completedFraction / totalTasks. null — если задач нет.
  double? get productivity =>
      totalTasks == 0 ? null : completedFraction / totalTasks;

  /// Доля своевременных среди выполненных. null — если нет ни одной выполненной.
  double? get timeliness {
    final total = onTimeCount + lateCount;
    return total == 0 ? null : onTimeCount / total;
  }

  Map<String, dynamic> toJson() => {
        'date': date.toIso8601String(),
        'totalTasks': totalTasks,
        'completedTasks': completedTasks,
        'completedFraction': completedFraction,
        'onTimeCount': onTimeCount,
        'lateCount': lateCount,
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory DayStats.fromJson(Map<String, dynamic> j) => DayStats(
        date: DateTime.parse(j['date'] as String),
        totalTasks: j['totalTasks'] as int,
        completedTasks: j['completedTasks'] as int,
        // Старое поле отсутствует → берётся completedTasks (целое выполнение).
        completedFraction: (j['completedFraction'] as num?)?.toDouble(),
        // Старые записи без этих полей → 0 (корректно пересчитается при первом изменении задачи).
        onTimeCount: j['onTimeCount'] as int? ?? 0,
        lateCount: j['lateCount'] as int? ?? 0,
        updatedAt: DateTime.parse(j['updatedAt'] as String),
      );
}
