/// Достижения (badges) — чистая надстройка над уже считаемой статистикой.
/// Не хранят прогресс сами: он выводится из агрегатов [AchievementStats].
/// Хранится лишь факт «уже разблокировано» (для де-дупликации уведомлений).

enum AchievementCategory { volume, streak, quality, milestone }

/// Снимок агрегированных показателей, из которых считается прогресс ачивок.
/// Все метрики — накопительные (не убывают), поэтому разблокированная ачивка
/// не «откатывается».
class AchievementStats {
  const AchievementStats({
    required this.tasksDone,
    required this.onTimeTasks,
    required this.quality10Tasks,
    required this.goalsDone,
    required this.currentStreak,
    required this.bestStreak,
    required this.daysUsing,
    required this.perfectDays,
    required this.day10Ratings,
  });

  /// Всего выполнено задач за всё время.
  final int tasksDone;

  /// Из выполненных — сколько в срок.
  final int onTimeTasks;

  /// Выполненных задач с оценкой качества 10/10.
  final int quality10Tasks;

  /// Достигнуто целей.
  final int goalsDone;

  final int currentStreak;
  final int bestStreak;

  /// Дней в приложении (с первого запуска).
  final int daysUsing;

  /// «Идеальные» дни: продуктивность 100% при ≥1 задаче.
  final int perfectDays;

  /// Дни, которым пользователь сам поставил оценку 10/10.
  final int day10Ratings;
}

/// Определение одной ачивки. [progressOf] возвращает текущее значение метрики;
/// ачивка разблокирована, когда оно ≥ [target].
class AchievementDef {
  const AchievementDef({
    required this.id,
    required this.title,
    required this.titleEn,
    required this.description,
    required this.descriptionEn,
    required this.emoji,
    required this.category,
    required this.target,
    required this.progressOf,
    this.liveProgressOf,
    this.secret = false,
  });

  final String id;
  final String title;
  final String titleEn;
  final String description;
  final String descriptionEn;
  final String emoji;
  final AchievementCategory category;
  final int target;

  String localizedTitle(bool ru) => ru ? title : titleEn;
  String localizedDescription(bool ru) => ru ? description : descriptionEn;

  /// Метрика разблокировки (накопительная, не убывает). Ачивка получена, когда
  /// progressOf ≥ target, и больше не «отбирается».
  final int Function(AchievementStats) progressOf;

  /// Необязательная «живая» метрика для полоски прогресса у ещё не полученных
  /// ачивок. Для серий это ТЕКУЩАЯ серия (обнуляется при прерывании), тогда как
  /// разблокировка идёт по рекорду. null — использовать [progressOf].
  final int Function(AchievementStats)? liveProgressOf;

  /// Скрытая (топовая) ачивка: до разблокировки показывается как «???».
  final bool secret;
}

/// Ачивка с вычисленным прогрессом для конкретного снимка статистики.
class EvaluatedAchievement {
  const EvaluatedAchievement({
    required this.def,
    required this.progress,
    required this.displayProgress,
  });

  final AchievementDef def;

  /// Значение метрики разблокировки (рекорд для серий).
  final int progress;

  /// Значение для полоски прогресса у незакрытых ачивок (текущая серия).
  final int displayProgress;

  bool get unlocked => progress >= def.target;
  double get fraction => (displayProgress / def.target).clamp(0.0, 1.0);
}

List<EvaluatedAchievement> evaluateAchievements(AchievementStats s) => [
      for (final d in kAchievements)
        EvaluatedAchievement(
          def: d,
          progress: d.progressOf(s),
          displayProgress: (d.liveProgressOf ?? d.progressOf)(s),
        ),
    ];

/// Полный каталог достижений. Топовые отмечены [secret] = true.
const List<AchievementDef> kAchievements = [
  // ── Объём: задачи ──────────────────────────────────────────────────────────
  AchievementDef(
    id: 'tasks_1',
    title: 'Первые шаги',
    titleEn: 'First Steps',
    description: 'Выполни первую задачу',
    descriptionEn: 'Complete your first task',
    emoji: '🌱',
    category: AchievementCategory.volume,
    target: 1,
    progressOf: _tasksDone,
  ),
  AchievementDef(
    id: 'tasks_10',
    title: 'Разогрев',
    titleEn: 'Warming Up',
    description: 'Выполни 10 задач',
    descriptionEn: 'Complete 10 tasks',
    emoji: '✅',
    category: AchievementCategory.volume,
    target: 10,
    progressOf: _tasksDone,
  ),
  AchievementDef(
    id: 'tasks_50',
    title: 'В потоке',
    titleEn: 'In the Flow',
    description: 'Выполни 50 задач',
    descriptionEn: 'Complete 50 tasks',
    emoji: '💪',
    category: AchievementCategory.volume,
    target: 50,
    progressOf: _tasksDone,
  ),
  AchievementDef(
    id: 'tasks_100',
    title: 'Сотня',
    titleEn: 'Century',
    description: 'Выполни 100 задач',
    descriptionEn: 'Complete 100 tasks',
    emoji: '🏆',
    category: AchievementCategory.volume,
    target: 100,
    progressOf: _tasksDone,
  ),
  AchievementDef(
    id: 'tasks_500',
    title: 'Легенда',
    titleEn: 'Legend',
    description: 'Выполни 500 задач',
    descriptionEn: 'Complete 500 tasks',
    emoji: '👑',
    category: AchievementCategory.volume,
    target: 500,
    progressOf: _tasksDone,
    secret: true,
  ),
  // ── Объём: цели ────────────────────────────────────────────────────────────
  AchievementDef(
    id: 'goals_1',
    title: 'Первая цель',
    titleEn: 'First Goal',
    description: 'Достигни первой цели',
    descriptionEn: 'Achieve your first goal',
    emoji: '🎯',
    category: AchievementCategory.volume,
    target: 1,
    progressOf: _goalsDone,
  ),
  AchievementDef(
    id: 'goals_10',
    title: 'Целеустремлённый',
    titleEn: 'Goal-Oriented',
    description: 'Достигни 10 целей',
    descriptionEn: 'Achieve 10 goals',
    emoji: '🎖️',
    category: AchievementCategory.volume,
    target: 10,
    progressOf: _goalsDone,
  ),
  AchievementDef(
    id: 'goals_50',
    title: 'Стратег',
    titleEn: 'Strategist',
    description: 'Достигни 50 целей',
    descriptionEn: 'Achieve 50 goals',
    emoji: '🏅',
    category: AchievementCategory.volume,
    target: 50,
    progressOf: _goalsDone,
    secret: true,
  ),
  // ── Серии ──────────────────────────────────────────────────────────────────
  AchievementDef(
    id: 'streak_3',
    title: 'Три дня',
    titleEn: 'Three Days',
    description: '3 дня подряд на 100%',
    descriptionEn: '3 days in a row at 100%',
    emoji: '🔥',
    category: AchievementCategory.streak,
    target: 3,
    progressOf: _bestStreak,
    liveProgressOf: _currentStreak,
  ),
  AchievementDef(
    id: 'streak_7',
    title: 'Неделя огня',
    titleEn: 'Week on Fire',
    description: '7 дней подряд на 100%',
    descriptionEn: '7 days in a row at 100%',
    emoji: '🔥',
    category: AchievementCategory.streak,
    target: 7,
    progressOf: _bestStreak,
    liveProgressOf: _currentStreak,
  ),
  AchievementDef(
    id: 'streak_30',
    title: 'Несгораемый',
    titleEn: 'Unburnable',
    description: '30 дней подряд на 100%',
    descriptionEn: '30 days in a row at 100%',
    emoji: '🔥',
    category: AchievementCategory.streak,
    target: 30,
    progressOf: _bestStreak,
    liveProgressOf: _currentStreak,
  ),
  AchievementDef(
    id: 'streak_100',
    title: 'Вечное пламя',
    titleEn: 'Eternal Flame',
    description: '100 дней подряд на 100%',
    descriptionEn: '100 days in a row at 100%',
    emoji: '🌟',
    category: AchievementCategory.streak,
    target: 100,
    progressOf: _bestStreak,
    liveProgressOf: _currentStreak,
    secret: true,
  ),
  // ── Качество и пунктуальность ──────────────────────────────────────────────
  AchievementDef(
    id: 'ontime_25',
    title: 'Пунктуальный',
    titleEn: 'Punctual',
    description: '25 задач выполнено в срок',
    descriptionEn: '25 tasks completed on time',
    emoji: '⏰',
    category: AchievementCategory.quality,
    target: 25,
    progressOf: _onTimeTasks,
  ),
  AchievementDef(
    id: 'ontime_100',
    title: 'Часы по тебе',
    titleEn: 'Like Clockwork',
    description: '100 задач выполнено в срок',
    descriptionEn: '100 tasks completed on time',
    emoji: '⌚',
    category: AchievementCategory.quality,
    target: 100,
    progressOf: _onTimeTasks,
  ),
  AchievementDef(
    id: 'ontime_500',
    title: 'Швейцарская точность',
    titleEn: 'Swiss Precision',
    description: '500 задач выполнено в срок',
    descriptionEn: '500 tasks completed on time',
    emoji: '🕰️',
    category: AchievementCategory.quality,
    target: 500,
    progressOf: _onTimeTasks,
    secret: true,
  ),
  AchievementDef(
    id: 'quality_5',
    title: 'Перфекционист',
    titleEn: 'Perfectionist',
    description: '5 задач с оценкой 10/10',
    descriptionEn: '5 tasks rated 10/10',
    emoji: '⭐',
    category: AchievementCategory.quality,
    target: 5,
    progressOf: _quality10,
  ),
  AchievementDef(
    id: 'quality_25',
    title: 'Мастер качества',
    titleEn: 'Quality Master',
    description: '25 задач с оценкой 10/10',
    descriptionEn: '25 tasks rated 10/10',
    emoji: '💎',
    category: AchievementCategory.quality,
    target: 25,
    progressOf: _quality10,
    secret: true,
  ),
  AchievementDef(
    id: 'day10_1',
    title: 'Идеальный день',
    titleEn: 'Perfect Day',
    description: 'Оцени день на 10/10',
    descriptionEn: 'Rate a day 10/10',
    emoji: '🌈',
    category: AchievementCategory.quality,
    target: 1,
    progressOf: _day10,
  ),
  AchievementDef(
    id: 'day10_10',
    title: 'Коллекционер радуг',
    titleEn: 'Rainbow Collector',
    description: '10 дней с твоей оценкой 10/10',
    descriptionEn: '10 days rated 10/10 by you',
    emoji: '🏵️',
    category: AchievementCategory.quality,
    target: 10,
    progressOf: _day10,
    secret: true,
  ),
  // ── Вехи и привычки ────────────────────────────────────────────────────────
  AchievementDef(
    id: 'days_7',
    title: 'Неделя вместе',
    titleEn: 'One Week Together',
    description: '7 дней в приложении',
    descriptionEn: '7 days using the app',
    emoji: '📅',
    category: AchievementCategory.milestone,
    target: 7,
    progressOf: _daysUsing,
  ),
  AchievementDef(
    id: 'days_30',
    title: 'Месяц вместе',
    titleEn: 'One Month Together',
    description: '30 дней в приложении',
    descriptionEn: '30 days using the app',
    emoji: '📆',
    category: AchievementCategory.milestone,
    target: 30,
    progressOf: _daysUsing,
  ),
  AchievementDef(
    id: 'days_365',
    title: 'Год вместе',
    titleEn: 'One Year Together',
    description: '365 дней в приложении',
    descriptionEn: '365 days using the app',
    emoji: '🎂',
    category: AchievementCategory.milestone,
    target: 365,
    progressOf: _daysUsing,
    secret: true,
  ),
  AchievementDef(
    id: 'perfect_1',
    title: 'Чистый лист',
    titleEn: 'Clean Slate',
    description: 'Закрой день на 100%',
    descriptionEn: 'Close a day at 100%',
    emoji: '💯',
    category: AchievementCategory.milestone,
    target: 1,
    progressOf: _perfectDays,
  ),
  AchievementDef(
    id: 'perfect_10',
    title: 'Десятка чистых',
    titleEn: 'Perfect Ten',
    description: '10 дней, закрытых на 100%',
    descriptionEn: '10 days closed at 100%',
    emoji: '🎉',
    category: AchievementCategory.milestone,
    target: 10,
    progressOf: _perfectDays,
  ),
  AchievementDef(
    id: 'perfect_50',
    title: 'Машина продуктивности',
    titleEn: 'Productivity Machine',
    description: '50 дней, закрытых на 100%',
    descriptionEn: '50 days closed at 100%',
    emoji: '🏔️',
    category: AchievementCategory.milestone,
    target: 50,
    progressOf: _perfectDays,
    secret: true,
  ),
];

// Топ-левел функции (нужны для const-конструкторов AchievementDef).
int _tasksDone(AchievementStats s) => s.tasksDone;
int _goalsDone(AchievementStats s) => s.goalsDone;
int _bestStreak(AchievementStats s) => s.bestStreak;
int _currentStreak(AchievementStats s) => s.currentStreak;
int _onTimeTasks(AchievementStats s) => s.onTimeTasks;
int _quality10(AchievementStats s) => s.quality10Tasks;
int _day10(AchievementStats s) => s.day10Ratings;
int _daysUsing(AchievementStats s) => s.daysUsing;
int _perfectDays(AchievementStats s) => s.perfectDays;
