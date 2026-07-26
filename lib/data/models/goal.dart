import 'package:intl/intl.dart' as intl;

import '../../core/utils/date_utils.dart';
import 'task.dart' show SubTask, TaskPriority;

/// Период цели. Порядок значений соответствует порядку вкладок на экране
/// «Цели» (по возрастанию длительности).
enum GoalPeriod { week, month, season, year }

/// Модели-датаклассы не зависят от Flutter (BuildContext), поэтому берём
/// текущий язык из глобальной [intl.Intl.defaultLocale] — его синхронизирует
/// с уже разрешённой Flutter-локалью builder в app.dart на каждой перестройке.
bool get _isRu => (intl.Intl.defaultLocale ?? 'ru').startsWith('ru');

const _seasonNamesRu = ['Зима', 'Весна', 'Лето', 'Осень'];
const _seasonNamesEn = ['Winter', 'Spring', 'Summer', 'Autumn'];

/// Названия сезонов по индексу: 0 — зима, 1 — весна, 2 — лето, 3 — осень.
/// Зима привязана к году своего декабря: Зима N = декабрь N + январь/февраль N+1.
List<String> get seasonNames => _isRu ? _seasonNamesRu : _seasonNamesEn;

/// То же самое, но с явно переданным языком (надёжнее глобального стейта —
/// см. [GoalPeriodRef.labelFor]).
List<String> seasonNamesFor(bool ru) => ru ? _seasonNamesRu : _seasonNamesEn;

/// Порядок отображения сезонов в сетках (хронологический внутри года):
/// весна → лето → осень → зима. Значения — индексы в [seasonNames].
const seasonDisplayOrder = [1, 2, 3, 0];

const _monthGenRu = [
  '',
  'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
  'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря',
];

const _monthNomRu = [
  '',
  'Январь', 'Февраль', 'Март', 'Апрель', 'Май', 'Июнь',
  'Июль', 'Август', 'Сентябрь', 'Октябрь', 'Ноябрь', 'Декабрь',
];

const _monthEn = [
  '',
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

/// Неизменяемое описание конкретного периода (без привязки к цели).
///
/// Централизует всю логику границ периода, grace-окна, срочности и подписей,
/// чтобы экран и репозиторий считали одинаково для пустого и заполненного
/// периода.
class GoalPeriodRef {
  const GoalPeriodRef({
    required this.period,
    required this.year,
    this.month,
    this.season,
    this.weekStart,
  });

  /// Текущий период переданного типа для даты [now].
  factory GoalPeriodRef.current(GoalPeriod period, DateTime now) {
    switch (period) {
      case GoalPeriod.week:
        return GoalPeriodRef(
          period: period,
          year: now.year,
          weekStart: startOfWeek(now),
        );
      case GoalPeriod.month:
        return GoalPeriodRef(period: period, year: now.year, month: now.month);
      case GoalPeriod.season:
        final (sy, si) = seasonOf(now);
        return GoalPeriodRef(period: period, year: sy, season: si);
      case GoalPeriod.year:
        return GoalPeriodRef(period: period, year: now.year);
    }
  }

  final GoalPeriod period;

  /// Якорный год периода. Для сезона «Зима» — год декабря.
  final int year;

  /// 1..12 — только для [GoalPeriod.month].
  final int? month;

  /// 0..3 — только для [GoalPeriod.season] (см. [seasonNames]).
  final int? season;

  /// Понедельник недели — только для [GoalPeriod.week].
  final DateTime? weekStart;

  /// Первый день периода.
  DateTime get start {
    switch (period) {
      case GoalPeriod.week:
        return dateOnly(weekStart!);
      case GoalPeriod.month:
        return DateTime(year, month!);
      case GoalPeriod.season:
        return _seasonStart(year, season!);
      case GoalPeriod.year:
        return DateTime(year);
    }
  }

  /// Последний день периода (включительно).
  DateTime get endInclusive {
    switch (period) {
      case GoalPeriod.week:
        return dateOnly(weekStart!).add(const Duration(days: 6));
      case GoalPeriod.month:
        return DateTime(year, month! + 1, 0);
      case GoalPeriod.season:
        return _seasonEnd(year, season!);
      case GoalPeriod.year:
        return DateTime(year, 12, 31);
    }
  }

  /// Сколько дней после конца периода его ещё можно редактировать.
  int get graceDays => switch (period) {
        GoalPeriod.week => 2,
        GoalPeriod.month => 5,
        GoalPeriod.season => 10,
        GoalPeriod.year => 15,
      };

  /// За сколько дней до конца период считается «срочным».
  int get urgencyThreshold => switch (period) {
        GoalPeriod.week => 2,
        GoalPeriod.month => 5,
        GoalPeriod.season => 10,
        GoalPeriod.year => 15,
      };

  /// Период полностью в прошлом (grace-окно тоже истекло) → только просмотр.
  bool isPast([DateTime? now]) {
    final today = dateOnly(now ?? DateTime.now());
    return today.isAfter(endInclusive.add(Duration(days: graceDays)));
  }

  /// Стабильный ключ для группировки целей по периоду.
  String get key {
    switch (period) {
      case GoalPeriod.week:
        final s = start;
        return 'w-${s.year}-${s.month}-${s.day}';
      case GoalPeriod.month:
        return 'm-$year-$month';
      case GoalPeriod.season:
        return 's-$year-$season';
      case GoalPeriod.year:
        return 'y-$year';
    }
  }

  /// Подпись периода для заголовков и карточек.
  ///
  /// Модели вне дерева виджетов не имеют BuildContext, поэтому по умолчанию
  /// язык берётся из глобальной [_isRu] (синхронизируется в app.dart). Там,
  /// где виджет может остаться смонтированным «под» другим экраном (и не
  /// перестроиться сразу при смене языка), явно передавай [ru] из
  /// `Localizations.localeOf(context)` — это надёжнее глобального стейта.
  String get label => labelFor(_isRu);

  String labelFor(bool ru) {
    final monthGen = ru ? _monthGenRu : _monthEn;
    final monthNom = ru ? _monthNomRu : _monthEn;
    final seasons = ru ? _seasonNamesRu : _seasonNamesEn;
    switch (period) {
      case GoalPeriod.week:
        final ws = start;
        final we = endInclusive;
        if (ws.month == we.month) {
          return '${ws.day}–${we.day} ${monthGen[ws.month]} ${we.year}';
        }
        if (ws.year == we.year) {
          return '${ws.day} ${monthGen[ws.month]} – '
              '${we.day} ${monthGen[we.month]} ${we.year}';
        }
        return '${ws.day} ${monthGen[ws.month]} ${ws.year} – '
            '${we.day} ${monthGen[we.month]} ${we.year}';
      case GoalPeriod.month:
        return '${monthNom[month!]} $year';
      case GoalPeriod.season:
        // Зима переходит через Новый год → показываем оба года: «Зима 2026/27».
        if (season == 0) {
          final nextYY = ((year + 1) % 100).toString().padLeft(2, '0');
          return '${seasons[0]} $year/$nextYY';
        }
        return '${seasons[season!]} $year';
      case GoalPeriod.year:
        return '$year';
    }
  }

  /// Предыдущий период того же типа.
  GoalPeriodRef get previous => _shift(-1);

  /// Следующий период того же типа.
  GoalPeriodRef get next => _shift(1);

  GoalPeriodRef _shift(int delta) {
    switch (period) {
      case GoalPeriod.week:
        return GoalPeriodRef(
          period: period,
          year: year,
          weekStart: start.add(Duration(days: 7 * delta)),
        );
      case GoalPeriod.month:
        final m = DateTime(year, month! + delta);
        return GoalPeriodRef(period: period, year: m.year, month: m.month);
      case GoalPeriod.season:
        // Хронологический порядок сезонов: весна(1) < лето(2) < осень(3) < зима(0).
        final ord = _seasonOrder(season!);
        final abs = year * 4 + ord + delta;
        final ny = abs >= 0 ? abs ~/ 4 : ((abs - 3) ~/ 4);
        final nord = abs - ny * 4;
        return GoalPeriodRef(
          period: period,
          year: ny,
          season: _seasonFromOrder(nord),
        );
      case GoalPeriod.year:
        return GoalPeriodRef(period: period, year: year + delta);
    }
  }

  @override
  bool operator ==(Object other) =>
      other is GoalPeriodRef && other.key == key;

  @override
  int get hashCode => key.hashCode;
}

// ─── Сезонные хелперы (метеорологические сезоны) ─────────────────────────────

DateTime _seasonStart(int year, int s) => switch (s) {
      0 => DateTime(year, 12, 1), // зима: декабрь year
      1 => DateTime(year, 3, 1), // весна
      2 => DateTime(year, 6, 1), // лето
      3 => DateTime(year, 9, 1), // осень
      _ => DateTime(year),
    };

DateTime _seasonEnd(int year, int s) => switch (s) {
      0 => DateTime(year + 1, 3, 0), // конец февраля следующего года
      1 => DateTime(year, 6, 0), // конец мая
      2 => DateTime(year, 9, 0), // конец августа
      3 => DateTime(year, 12, 0), // конец ноября
      _ => DateTime(year, 12, 31),
    };

/// Сезон, которому принадлежит дата: (якорный год, индекс сезона).
(int, int) seasonOf(DateTime d) {
  final m = d.month;
  if (m == 12) return (d.year, 0); // зима этого года
  if (m <= 2) return (d.year - 1, 0); // зима прошлого года
  if (m <= 5) return (d.year, 1); // весна
  if (m <= 8) return (d.year, 2); // лето
  return (d.year, 3); // осень
}

/// Хронологический порядок внутри года: весна→0, лето→1, осень→2, зима→3.
int _seasonOrder(int s) => switch (s) {
      1 => 0,
      2 => 1,
      3 => 2,
      0 => 3,
      _ => 0,
    };

int _seasonFromOrder(int o) => switch (o) {
      0 => 1,
      1 => 2,
      2 => 3,
      3 => 0,
      _ => 1,
    };

// ─── Модель цели ─────────────────────────────────────────────────────────────

class Goal {
  Goal({
    required this.id,
    required this.period,
    required this.year,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    this.month,
    this.season,
    this.weekStart,
    this.description,
    this.completed = false,
    this.completedAt,
    this.startDate,
    this.deadline,
    this.targetCount,
    this.manualProgress = 0,
    this.linkedProgress = 0,
    this.isTransferred = false,
    this.transferredFromId,
    this.transferDeclined = false,
    this.quality,
    this.subtasks = const [],
    this.priority = TaskPriority.none,
    this.tags = const [],
  });

  final String id;
  final GoalPeriod period;
  final int year;
  final int? month;

  /// Индекс сезона 0..3 — только для [GoalPeriod.season].
  final int? season;

  /// Понедельник недели — только для [GoalPeriod.week].
  final DateTime? weekStart;

  final String title;
  final String? description;
  final bool completed;

  /// Момент выполнения цели. Заполняется при toggleComplete → completed = true,
  /// обнуляется при toggleComplete → completed = false.
  final DateTime? completedAt;

  final DateTime createdAt;
  final DateTime updatedAt;

  /// Дата начала — с какого дня цель становится актуальной (необязательно).
  /// null = актуальна с первого дня периода.
  final DateTime? startDate;

  /// Дедлайн — дата внутри периода, до которой цель должна быть достигнута.
  final DateTime? deadline;

  /// Цель-число для цели-счётчика (напр. «12 книг»). null — обычная цель.
  final int? targetCount;

  /// Ручная часть прогресса (кнопки −/+ и ручной ввод).
  final int manualProgress;

  /// Кэш суммы вкладов привязанных задач (обновляется TaskRepository).
  final int linkedProgress;

  /// true — оригинал цели, которую перенесли в другой период.
  final bool isTransferred;

  /// Цель является копией, перенесённой из другого периода.
  /// Значение — id оригинальной цели.
  final String? transferredFromId;

  /// Пользователь явно отказался переносить эту цель (баннер/догоняющий
  /// список) — больше не предлагать перенос повторно.
  final bool transferDeclined;

  /// Субъективная оценка качества достижения (1..10), рефлексия. null — не оценено.
  final int? quality;

  /// Подзадачи (чек-лист). Пусто — обычная цель. Работают как счётчик:
  /// все выполнены → цель достигнута; частично → дробный вклад.
  final List<SubTask> subtasks;

  /// Приоритет (нет/низкий/средний/высокий) — влияет на сортировку среди
  /// невыполненных целей и на иконку в плитке (как у задач).
  final TaskPriority priority;

  /// Теги для группировки и поиска («здоровье», «карьера»). Без «#» в данных.
  final List<String> tags;

  /// Итоговое значение счётчика = ручная часть + вклад задач.
  int get progressCount => manualProgress + linkedProgress;

  /// Цель-счётчик (с прогрессом к числу), а не обычная галочка.
  bool get isCounter => targetCount != null && targetCount! > 1;

  /// Цель-чек-лист (есть подзадачи).
  bool get isChecklist => subtasks.isNotEmpty;

  /// Сколько подзадач выполнено.
  int get subtasksDone => subtasks.where((s) => s.done).length;

  /// Прогресс счётчика 0..1 (или null для обычной цели).
  double? get counterProgress =>
      isCounter ? (progressCount / targetCount!).clamp(0.0, 1.0) : null;

  /// Значение для кольца прогресса (0..1) у чек-листа/счётчика; null — обычная.
  double? get progressRingValue {
    if (isChecklist) return subtasksDone / subtasks.length;
    return counterProgress;
  }

  /// Дробный вклад в выполнение: чек-лист/счётчик — доля, обычная — 0/1.
  double get completionValue {
    if (isChecklist) return subtasksDone / subtasks.length;
    return counterProgress ?? (completed ? 1.0 : 0.0);
  }

  /// Описание периода этой цели.
  GoalPeriodRef get ref => GoalPeriodRef(
        period: period,
        year: year,
        month: month,
        season: season,
        weekStart: weekStart,
      );

  DateTime get periodStart => ref.start;
  DateTime get periodEnd => ref.endInclusive;

  /// Цель выполнена вовремя:
  /// • completedAt ≤ deadline (если задан), ИЛИ
  /// • completedAt ≤ последний день периода (если deadline не задан).
  bool get isOnTime {
    if (!completed || completedAt == null) return false;
    final completedDate = dateOnly(completedAt!);
    final effectiveDeadline = deadline ?? periodEnd;
    return !completedDate.isAfter(effectiveDeadline);
  }

  Goal copyWith({
    String? title,
    bool? completed,
    DateTime? completedAt,
    bool clearCompletedAt = false,
    DateTime? updatedAt,
    DateTime? startDate,
    bool clearStartDate = false,
    DateTime? deadline,
    bool clearDeadline = false,
    int? targetCount,
    bool clearTargetCount = false,
    int? manualProgress,
    int? linkedProgress,
    bool? isTransferred,
    bool? transferDeclined,
    int? quality,
    bool clearQuality = false,
    List<SubTask>? subtasks,
    TaskPriority? priority,
    List<String>? tags,
  }) =>
      Goal(
        id: id,
        period: period,
        year: year,
        month: month,
        season: season,
        weekStart: weekStart,
        title: title ?? this.title,
        description: description,
        completed: completed ?? this.completed,
        completedAt:
            clearCompletedAt ? null : (completedAt ?? this.completedAt),
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        startDate: clearStartDate ? null : (startDate ?? this.startDate),
        deadline: clearDeadline ? null : (deadline ?? this.deadline),
        targetCount:
            clearTargetCount ? null : (targetCount ?? this.targetCount),
        manualProgress: manualProgress ?? this.manualProgress,
        linkedProgress: linkedProgress ?? this.linkedProgress,
        isTransferred: isTransferred ?? this.isTransferred,
        transferredFromId: transferredFromId ?? this.transferredFromId,
        transferDeclined: transferDeclined ?? this.transferDeclined,
        quality: clearQuality ? null : (quality ?? this.quality),
        subtasks: subtasks ?? this.subtasks,
        priority: priority ?? this.priority,
        tags: tags ?? this.tags,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'period': period.name,
        'year': year,
        'month': month,
        'season': season,
        'weekStart': weekStart?.toIso8601String(),
        'title': title,
        'description': description,
        'completed': completed,
        'completedAt': completedAt?.toIso8601String(),
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'startDate': startDate?.toIso8601String(),
        'deadline': deadline?.toIso8601String(),
        'targetCount': targetCount,
        'manualProgress': manualProgress,
        'linkedProgress': linkedProgress,
        'isTransferred': isTransferred,
        'transferredFromId': transferredFromId,
        'transferDeclined': transferDeclined,
        'quality': quality,
        'subtasks': subtasks.map((s) => s.toJson()).toList(),
        'priority': priority.index,
        'tags': tags,
      };

  factory Goal.fromJson(Map<String, dynamic> j) => Goal(
        id: j['id'] as String,
        period: GoalPeriod.values.byName(j['period'] as String),
        year: j['year'] as int,
        month: j['month'] as int?,
        season: j['season'] as int?,
        weekStart: j['weekStart'] == null
            ? null
            : DateTime.parse(j['weekStart'] as String),
        title: j['title'] as String,
        description: j['description'] as String?,
        completed: j['completed'] as bool? ?? false,
        completedAt: j['completedAt'] == null
            ? null
            : DateTime.parse(j['completedAt'] as String),
        createdAt: DateTime.parse(j['createdAt'] as String),
        updatedAt: DateTime.parse(j['updatedAt'] as String),
        startDate: j['startDate'] == null
            ? null
            : DateTime.parse(j['startDate'] as String),
        deadline: j['deadline'] == null
            ? null
            : DateTime.parse(j['deadline'] as String),
        targetCount: j['targetCount'] as int?,
        // Миграция: старое единое progressCount → ручная часть.
        manualProgress:
            (j['manualProgress'] ?? j['progressCount']) as int? ?? 0,
        linkedProgress: j['linkedProgress'] as int? ?? 0,
        isTransferred: j['isTransferred'] as bool? ?? false,
        transferredFromId: j['transferredFromId'] as String?,
        transferDeclined: j['transferDeclined'] as bool? ?? false,
        quality: j['quality'] as int?,
        subtasks: (j['subtasks'] as List?)
                ?.map((e) => SubTask.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        priority: TaskPriority.values[(j['priority'] as int? ?? 0)
            .clamp(0, TaskPriority.values.length - 1)],
        tags: (j['tags'] as List?)?.map((e) => e as String).toList() ??
            const [],
      );
}
