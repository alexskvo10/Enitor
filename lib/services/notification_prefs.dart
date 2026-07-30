import 'package:flutter/material.dart';

/// Настройки уведомлений. Время хранится в минутах с полуночи (0..1439),
/// как и у задач, чтобы легко собирать TimeOfDay.
@immutable
class NotificationPrefs {
  const NotificationPrefs({
    this.enabled = true,
    this.taskReminders = true,
    this.taskLeadMinutes = 10,
    this.taskEndReminders = true,
    this.taskEndLeadMinutes = 10,
    this.taskUrgentAlerts = true,
    this.taskOverdueAlerts = true,
    this.morningPlan = true,
    this.morningMinutes = 8 * 60 + 30, // 08:30
    this.eveningReview = true,
    this.eveningMinutes = 21 * 60, // 21:00
    this.generalReminders = true,
    this.weeklyRetro = true,
    this.retroWeekday = DateTime.monday,
    this.retroMinutes = 19 * 60, // 19:00
    this.transferReminder = false,
    this.taskBacklogReminder = true,
    this.goalBacklogReminder = true,
    this.goalUrgentAlerts = true,
    this.goalOverdueAlerts = true,
    this.goalGeneralReminders = true,
    this.quietHoursEnabled = true,
    this.quietStart = 23 * 60, // 23:00
    this.quietEnd = 8 * 60, // 08:00
  });

  /// Главный рубильник — выключает все уведомления разом.
  final bool enabled;

  /// Напоминание к началу задачи (за [taskLeadMinutes] до её времени).
  final bool taskReminders;
  final int taskLeadMinutes;

  /// Напоминание к концу задачи (за [taskEndLeadMinutes] до её окончания).
  final bool taskEndReminders;
  final int taskEndLeadMinutes;

  /// Уведомление в момент, когда задача переходит в статус «Требует
  /// внимания» (тот же порог, что и бейдж в списке — за 30 мин до конца).
  final bool taskUrgentAlerts;

  /// Уведомление в момент, когда задача становится просроченной.
  final bool taskOverdueAlerts;

  /// Утреннее «спланируй день».
  final bool morningPlan;
  final int morningMinutes;

  /// Вечернее «оцени, как прошёл день».
  final bool eveningReview;
  final int eveningMinutes;

  /// Напоминания «не забудь про задачи» пару раз в день (12:30 и 16:30).
  ///
  /// Ставятся только на дни, где реально есть невыполненное, и называют его
  /// число — как [transferReminder], который молчит, когда переносить нечего.
  /// Пока они слались по часам вслепую, держать их включёнными было нельзя:
  /// пустое напоминание в день без задач приучает отмахиваться от уведомлений
  /// приложения целиком и обесценивает те, что действительно важны.
  final bool generalReminders;

  /// Разбор прошедшей недели: уведомление в назначенный момент + окно с
  /// итогами при первом открытии приложения после него.
  ///
  /// Ретроспектива живёт в профиле, и без напоминания о ней просто не
  /// вспоминают: это единственный экран, который показывает не «что сделано»,
  /// а «как прошла неделя по сравнению с прошлой». Ради него уведомления и
  /// нужны.
  final bool weeklyRetro;

  /// День разбора, 1..7 (как [DateTime.weekday]). По умолчанию понедельник:
  /// разбирается ПРОШЕДШАЯ неделя, а по правилу дня в 4:00 она не закрыта
  /// раньше утра понедельника. Замер в воскресенье вечером систематически
  /// занижал бы сравнение — открытые воскресные задачи попадали бы в
  /// знаменатель, тогда как прошлая неделя уже замерена целиком.
  final int retroWeekday;

  /// Время разбора в минутах с полуночи. По умолчанию 19:00: разбор недели —
  /// занятие рефлексивное, и утро понедельника для него худший слот (человек
  /// настроен начинать, а не оглядываться). На цифры это не влияет —
  /// разбирается прошлая неделя, сегодняшний день в неё не входит.
  final int retroMinutes;

  /// Уведомление в 4:00, если есть невыполненные задачи/цели прошлого
  /// периода, ожидающие подтверждения переноса.
  ///
  /// По умолчанию ВЫКЛЮЧЕНО — единственное из содержательных. Момент у него
  /// жёстко привязан к границе дня (4:00) и потому, в отличие от остальных,
  /// не подчиняется тихим часам: включённым по умолчанию он будил бы среди
  /// ночи. Терять при этом нечего — при первом же открытии приложения
  /// невыполненное всё равно встретит догоняющий диалог переноса.
  final bool transferReminder;

  /// Напоминание про бэклог задач — среда 18:00 и суббота 12:00.
  ///
  /// Бэклог это единственное место в приложении, которое само о себе не
  /// напоминает: задача попадает туда, когда её выкидывают из дня, и дальше
  /// молчит, пока о ней не вспомнят. Дважды в неделю — середина недели, чтобы
  /// хвост не оброс, и выходной, когда разбирать его есть когда. Молчит,
  /// когда бэклог пуст.
  final bool taskBacklogReminder;

  /// Напоминание про бэклог целей — 1-е число месяца, 11:00.
  ///
  /// Реже, чем по задачам, потому что и наполняется несравнимо медленнее:
  /// цель живёт периодом, а не днём. Первое число выбрано не случайно — это
  /// момент, когда ставят цели на новый месяц, и отложенное как раз стоит
  /// пересмотреть прежде, чем придумывать новое. Молчит, когда бэклог пуст.
  final bool goalBacklogReminder;

  /// Уведомление в момент, когда цель переходит в статус «Требует внимания»
  /// (тот же порог, что и бейдж в списке — за urgencyThreshold дней до
  /// дедлайна/конца периода).
  final bool goalUrgentAlerts;

  /// Уведомление на следующий день после конца периода, если цель не
  /// достигнута (тот же момент, что и статус «Просрочена» в списке).
  final bool goalOverdueAlerts;

  /// Общие напоминания «загляни в цели» — не привязаны к конкретной цели,
  /// пара раз в неделю (отдельно от общих напоминаний по задачам).
  final bool goalGeneralReminders;

  /// Главный рубильник тихих часов — если выключен, окно [quietStart]..
  /// [quietEnd] игнорируется полностью (умные/общие напоминания идут как
  /// обычно в любое время).
  final bool quietHoursEnabled;

  /// Тихие часы — окно, в которое умные/общие напоминания подавляются.
  /// Может пересекать полночь (например 23:00 → 08:00).
  final int quietStart;
  final int quietEnd;

  /// true, если минута [minutes] (0..1439) попадает в тихие часы.
  bool isQuiet(int minutes) {
    if (!quietHoursEnabled) return false; // тихие часы выключены целиком
    if (quietStart == quietEnd) return false; // окно нулевой длины
    if (quietStart < quietEnd) {
      // Обычное окно в пределах одних суток.
      return minutes >= quietStart && minutes < quietEnd;
    }
    // Окно через полночь: [quietStart..24:00) ∪ [00:00..quietEnd).
    return minutes >= quietStart || minutes < quietEnd;
  }

  NotificationPrefs copyWith({
    bool? enabled,
    bool? taskReminders,
    int? taskLeadMinutes,
    bool? taskEndReminders,
    int? taskEndLeadMinutes,
    bool? taskUrgentAlerts,
    bool? taskOverdueAlerts,
    bool? morningPlan,
    int? morningMinutes,
    bool? eveningReview,
    int? eveningMinutes,
    bool? generalReminders,
    bool? weeklyRetro,
    int? retroWeekday,
    int? retroMinutes,
    bool? transferReminder,
    bool? taskBacklogReminder,
    bool? goalBacklogReminder,
    bool? goalUrgentAlerts,
    bool? goalOverdueAlerts,
    bool? goalGeneralReminders,
    bool? quietHoursEnabled,
    int? quietStart,
    int? quietEnd,
  }) =>
      NotificationPrefs(
        enabled: enabled ?? this.enabled,
        taskReminders: taskReminders ?? this.taskReminders,
        taskLeadMinutes: taskLeadMinutes ?? this.taskLeadMinutes,
        taskEndReminders: taskEndReminders ?? this.taskEndReminders,
        taskEndLeadMinutes: taskEndLeadMinutes ?? this.taskEndLeadMinutes,
        taskUrgentAlerts: taskUrgentAlerts ?? this.taskUrgentAlerts,
        taskOverdueAlerts: taskOverdueAlerts ?? this.taskOverdueAlerts,
        morningPlan: morningPlan ?? this.morningPlan,
        morningMinutes: morningMinutes ?? this.morningMinutes,
        eveningReview: eveningReview ?? this.eveningReview,
        eveningMinutes: eveningMinutes ?? this.eveningMinutes,
        generalReminders: generalReminders ?? this.generalReminders,
        weeklyRetro: weeklyRetro ?? this.weeklyRetro,
        retroWeekday: retroWeekday ?? this.retroWeekday,
        retroMinutes: retroMinutes ?? this.retroMinutes,
        transferReminder: transferReminder ?? this.transferReminder,
        taskBacklogReminder:
            taskBacklogReminder ?? this.taskBacklogReminder,
        goalBacklogReminder:
            goalBacklogReminder ?? this.goalBacklogReminder,
        goalUrgentAlerts: goalUrgentAlerts ?? this.goalUrgentAlerts,
        goalOverdueAlerts: goalOverdueAlerts ?? this.goalOverdueAlerts,
        goalGeneralReminders:
            goalGeneralReminders ?? this.goalGeneralReminders,
        quietHoursEnabled: quietHoursEnabled ?? this.quietHoursEnabled,
        quietStart: quietStart ?? this.quietStart,
        quietEnd: quietEnd ?? this.quietEnd,
      );

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'taskReminders': taskReminders,
        'taskLeadMinutes': taskLeadMinutes,
        'taskEndReminders': taskEndReminders,
        'taskEndLeadMinutes': taskEndLeadMinutes,
        'taskUrgentAlerts': taskUrgentAlerts,
        'taskOverdueAlerts': taskOverdueAlerts,
        'morningPlan': morningPlan,
        'morningMinutes': morningMinutes,
        'eveningReview': eveningReview,
        'eveningMinutes': eveningMinutes,
        'generalReminders': generalReminders,
        'weeklyRetro': weeklyRetro,
        'retroWeekday': retroWeekday,
        'retroMinutes': retroMinutes,
        'transferReminder': transferReminder,
        'taskBacklogReminder': taskBacklogReminder,
        'goalBacklogReminder': goalBacklogReminder,
        'goalUrgentAlerts': goalUrgentAlerts,
        'goalOverdueAlerts': goalOverdueAlerts,
        'goalGeneralReminders': goalGeneralReminders,
        'quietHoursEnabled': quietHoursEnabled,
        'quietStart': quietStart,
        'quietEnd': quietEnd,
      };

  factory NotificationPrefs.fromJson(Map<String, dynamic> j) {
    const def = NotificationPrefs();
    return NotificationPrefs(
      enabled: j['enabled'] as bool? ?? def.enabled,
      taskReminders: j['taskReminders'] as bool? ?? def.taskReminders,
      taskLeadMinutes: j['taskLeadMinutes'] as int? ?? def.taskLeadMinutes,
      taskEndReminders:
          j['taskEndReminders'] as bool? ?? def.taskEndReminders,
      taskEndLeadMinutes:
          j['taskEndLeadMinutes'] as int? ?? def.taskEndLeadMinutes,
      taskUrgentAlerts: j['taskUrgentAlerts'] as bool? ?? def.taskUrgentAlerts,
      taskOverdueAlerts:
          j['taskOverdueAlerts'] as bool? ?? def.taskOverdueAlerts,
      morningPlan: j['morningPlan'] as bool? ?? def.morningPlan,
      morningMinutes: j['morningMinutes'] as int? ?? def.morningMinutes,
      eveningReview: j['eveningReview'] as bool? ?? def.eveningReview,
      eveningMinutes: j['eveningMinutes'] as int? ?? def.eveningMinutes,
      generalReminders: j['generalReminders'] as bool? ?? def.generalReminders,
      weeklyRetro: j['weeklyRetro'] as bool? ?? def.weeklyRetro,
      // Зажимаем: день недели индексирует список названий (weekday - 1), а
      // время собирается в TimeOfDay — битое значение из чужого/старого
      // бэкапа уронило бы и настройки, и планировщик.
      retroWeekday:
          (j['retroWeekday'] as int? ?? def.retroWeekday).clamp(1, 7),
      retroMinutes:
          (j['retroMinutes'] as int? ?? def.retroMinutes).clamp(0, 1439),
      transferReminder:
          j['transferReminder'] as bool? ?? def.transferReminder,
      taskBacklogReminder:
          j['taskBacklogReminder'] as bool? ?? def.taskBacklogReminder,
      goalBacklogReminder:
          j['goalBacklogReminder'] as bool? ?? def.goalBacklogReminder,
      goalUrgentAlerts:
          j['goalUrgentAlerts'] as bool? ?? def.goalUrgentAlerts,
      goalOverdueAlerts:
          j['goalOverdueAlerts'] as bool? ?? def.goalOverdueAlerts,
      goalGeneralReminders:
          j['goalGeneralReminders'] as bool? ?? def.goalGeneralReminders,
      quietHoursEnabled:
          j['quietHoursEnabled'] as bool? ?? def.quietHoursEnabled,
      quietStart: j['quietStart'] as int? ?? def.quietStart,
      quietEnd: j['quietEnd'] as int? ?? def.quietEnd,
    );
  }
}
