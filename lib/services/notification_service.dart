import 'dart:io' show File, Platform, Process;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:intl/intl.dart' as intl;
import 'package:path_provider/path_provider.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../data/models/goal.dart';
import '../data/models/task.dart';
import '../l10n/app_localizations.dart';
import 'notification_prefs.dart';

/// Модели/сервисы вне дерева виджетов не имеют BuildContext — берём строки
/// из уже разрешённой глобальной локали (см. builder в app.dart).
AppLocalizations get _l10n =>
    lookupAppLocalizations(Locale(intl.Intl.defaultLocale ?? 'ru'));

/// Локальные уведомления (Android + Windows). Таймзоно-зависимое точное
/// расписание:
/// • напоминания к началу и к концу задач (за N минут),
/// • «требует внимания» / «просрочена» — те же моменты, что и бейджи в списке
///   (и у задач, и у целей — целям нет привязки ко времени дня, поэтому их
///   моменты считаются от дедлайна/конца периода, в 9:00),
/// • уведомление о переносе (в 4:00, если есть невыполненное прошлого периода),
/// • общие напоминания по целям — пн утром/пт вечером (отдельно от общих
///   напоминаний по задачам, которые несколько раз в день),
/// • утренний план / вечерняя рефлексия,
/// • общие напоминания «не забудь про задачи» несколько раз в день,
/// — всё с уважением тихих часов (кроме напоминаний по конкретным задачам,
/// которые пользователь сам разместил во времени).
///
/// На Windows приложение не упаковано в MSIX: это ограничивает только уже
/// показанные тосты (историю Action Center) — `cancel`/`cancelAll` для ещё
/// не сработавших запланированных уведомлений работают нормально, так что
/// applySchedule() (снять всё → поставить заново) остаётся корректным.
/// Ближайшие [count] вхождений [dayOfMonth]-го числа месяца в [minutesOfDay],
/// строго позже [from].
///
/// Отдельной чистой функцией, а не внутри планировщика: месячного повтора у
/// плагина нет ни на одной платформе, вхождения приходится считать руками, а
/// переход через декабрь и короткий февраль ломаются незаметно — уведомление
/// просто не приходит, и узнаёшь об этом через месяц.
List<DateTime> monthlyOccurrencesAfter(
  DateTime from, {
  required int dayOfMonth,
  required int minutesOfDay,
  required int count,
}) {
  final result = <DateTime>[];
  var year = from.year;
  var month = from.month;
  while (result.length < count) {
    // Зажимаем по длине месяца: 31-е в феврале иначе перетекло бы на март.
    final lastDay = DateTime(year, month + 1, 0).day;
    final day = dayOfMonth < lastDay ? dayOfMonth : lastDay;
    final when = DateTime(
      year,
      month,
      day,
      minutesOfDay ~/ 60,
      minutesOfDay % 60,
    );
    // Вхождение текущего месяца могло уже пройти — тогда пропускаем его.
    if (when.isAfter(from)) result.add(when);
    month++;
    if (month > 12) {
      month = 1;
      year++;
    }
  }
  return result;
}

class NotificationService {
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _tzReady = false;

  // ── Каналы (раздельные → пользователь рулит ими в системных настройках) ──
  static const _planChannelId = 'todo_planning';
  String get _planChannelName => _l10n.notifPlanChannelName;
  String get _planChannelDesc => _l10n.notifPlanChannelDesc;

  static const _taskChannelId = 'todo_task_reminders';
  String get _taskChannelName => _l10n.notifTaskChannelName;
  String get _taskChannelDesc => _l10n.notifTaskChannelDesc;

  static const _generalChannelId = 'todo_general';
  String get _generalChannelName => _l10n.notifGeneralChannelName;
  String get _generalChannelDesc => _l10n.notifGeneralChannelDesc;

  static const _goalChannelId = 'todo_goal_reminders';
  String get _goalChannelName => _l10n.notifGoalChannelName;
  String get _goalChannelDesc => _l10n.notifGoalChannelDesc;

  // ── Зарезервированные id (чтобы перепланирование было идемпотентным) ──
  static const _idMorning = 1;
  static const _idEvening = 2;
  static const _idTransfer = 3;
  // Общие напоминания: фиксированные слоты в течение дня.
  static const _idGeneral1 = 10;
  static const _idGeneral2 = 11;
  static const _generalSlots = <int, int>{
    _idGeneral1: 12 * 60 + 30, // 12:30
    _idGeneral2: 16 * 60 + 30, // 16:30
  };
  // На сколько дней вперёд расписываем общие напоминания. Больше нет смысла:
  // расписание пересобирается при каждом открытии приложения и любой правке
  // задач, а лишние отложенные уведомления только занимают лимит ОС.
  static const _generalHorizonDays = 7;
  // Общие напоминания по целям — не каждый день, а пару раз в неделю:
  // понедельник утром (спланировать неделю) и пятница вечером (проверить
  // прогресс перед выходными).
  static const _idGoalWeekly1 = 4; // понедельник
  static const _idGoalWeekly2 = 5; // пятница
  // Разбор недели. День и время настраиваемые (по умолчанию понедельник
  // 19:00, см. NotificationPrefs.retroWeekday) — поэтому слот берётся из
  // prefs, а не из константы, как у напоминаний по целям ниже.
  static const _idWeeklyRetro = 6;
  // Бэклог задач — середина недели и выходной: успеть разгрести, пока хвост
  // не оброс, и когда на это есть время.
  static const _idTaskBacklog1 = 7; // среда
  static const _idTaskBacklog2 = 8; // суббота
  static const _taskBacklogSlots = <int, (int, int)>{
    _idTaskBacklog1: (DateTime.wednesday, 18 * 60),
    _idTaskBacklog2: (DateTime.saturday, 12 * 60),
  };
  // Бэклог целей — 1-е число месяца: момент, когда ставят цели на новый
  // месяц, и отложенное стоит пересмотреть прежде, чем придумывать новое.
  static const _idGoalBacklog = 9;
  static const _goalBacklogDay = 1;
  static const _goalBacklogMinutes = 11 * 60; // 11:00
  // Месячного повтора у плагина нет ни на одной платформе — расписываем
  // столько ближайших месяцев явно. Расписание пересобирается при каждом
  // открытии приложения, так что запаса хватает с большим избытком.
  static const _monthlyOccurrences = 4;
  static const _goalWeeklySlots = <int, (int, int)>{
    // id: (weekday 1..7, minutesOfDay)
    _idGoalWeekly1: (DateTime.monday, 9 * 60),
    _idGoalWeekly2: (DateTime.friday, 18 * 60),
  };
  // Напоминания к задачам: id от этого значения и выше (у каждого вида —
  // свой блок из 100 id, с запасом под лимит уведомлений в applySchedule).
  static const _taskIdBase = 2000;
  static const _taskEndIdBase = 2100;
  static const _taskUrgentIdBase = 2200;
  static const _taskOverdueIdBase = 2300;
  // Напоминания к целям: отдельный диапазон, подальше от задач (у каждого
  // вида — блок из 200 id, целей обычно меньше, чем задач, но с запасом).
  static const _goalUrgentIdBase = 2500;
  static const _goalOverdueIdBase = 2700;

  /// Инициализация плагина + базы таймзон. Безопасно вызывать повторно.
  Future<void> init() async {
    if (!_isSupportedPlatform) return;

    if (!_tzReady) {
      tzdata.initializeTimeZones();
      try {
        final name = await FlutterTimezone.getLocalTimezone();
        tz.setLocalLocation(tz.getLocation(name));
      } catch (_) {
        // Не смогли определить зону устройства — остаёмся на UTC (по умолчанию
        // timezone-пакета). Лучше сдвиг расписания, чем краш на старте.
      }
      _tzReady = true;
    }

    _winIconPath = await _windowsIconPath();
    final initSettings = InitializationSettings(
      android: const AndroidInitializationSettings('@mipmap/ic_launcher'),
      windows: WindowsInitializationSettings(
        appName: _kWindowsAppName,
        appUserModelId: _kWindowsAumid,
        guid: _kWindowsActivatorGuid,
        iconPath: _winIconPath,
      ),
    );
    // Реестровую «прописку» AUMID проставляем и ДО инициализации плагина
    // (чтобы он регистрировался поверх валидного ключа), и ПОСЛЕ неё —
    // подробности в доке к _ensureWindowsRegistration.
    await _ensureWindowsRegistration();
    var ok = await _plugin.initialize(initSettings) ?? false;
    await _ensureWindowsRegistration();
    if (!ok && _isWindows) {
      // Регистрация могла падать именно из-за битого ключа — он только что
      // починен, поэтому одна повторная попытка не бессмысленна.
      ok = await _plugin.initialize(initSettings) ?? false;
    }
    if (!ok) {
      debugPrint('NotificationService: plugin.initialize() вернул false — '
          'расписание не будет работать');
    }
  }

  static const _kWindowsAppName = 'Enitor';
  static const _kWindowsAumid = 'Dev.Enitor.App.Desktop';
  static const _kWindowsActivatorGuid = '050d04d6-626e-49f6-bb38-826023847f25';

  /// Путь к распакованной иконке тоста — считается один раз в [init] и потом
  /// переиспользуется при повторной «прописке» в реестре.
  String? _winIconPath;

  /// Реестровая «прописка» приложения под своим AppUserModel.ID.
  ///
  /// Для неупакованного (не-MSIX) приложения Windows берёт отсюда всё, что
  /// нужно, чтобы вообще показать тост: `DisplayName` (заголовок тоста и
  /// строка в «Параметры → Уведомления»), `CustomActivator` (COM-класс,
  /// которому отдаётся клик) и `IconUri` (лого). Если ключ пуст, платформа
  /// молча выбрасывает уведомление в момент срабатывания — запланированные
  /// тосты при этом спокойно лежат в очереди, поэтому со стороны приложения
  /// всё выглядит исправным. Именно так уведомления и «пропали»: расписание
  /// строилось, а доставки не было ни одной.
  ///
  /// Плагин пишет эти значения сам при `initialize()`, но полагаться на это
  /// нельзя: `DisplayName` он кладёт без завершающего нуля
  /// (`size() * sizeof(wchar_t)`), а на практике ключ ещё и оказывается
  /// вычищенным между запусками. Поэтому проверяем и дописываем сами — через
  /// системную `reg.exe`, а не через FFI-обёртки (те уже ловились на том, что
  /// рапортуют успех, не изменив реестр).
  ///
  /// Идемпотентно и дёшево: один `reg query` на всё, запись — только если
  /// значение реально отличается.
  ///
  /// ⚠️ Чего этот код принципиально НЕ может: пробиться через виртуализацию
  /// реестра. Антивирусы с песочницей (проверено на Kaspersky) заворачивают
  /// неподписанный exe в теневой реестр — `reg add` возвращает 0, чтение
  /// сразу после записи возвращает записанное, а в настоящем HKCU не
  /// появляется ничего. Windows же читает настоящий, видит пустой ключ и
  /// молча выбрасывает каждый тост. Изнутри процесса это не детектируется
  /// (readback тоже виртуализован) — лечится только доверием к приложению в
  /// антивирусе, поэтому проверки «а долетело ли» тут нет намеренно.
  Future<void> _ensureWindowsRegistration() async {
    if (!_isWindows) return;
    const keyPath = 'HKCU\\Software\\Classes\\AppUserModelId\\$_kWindowsAumid';
    try {
      final current = await _regQueryAll(keyPath);
      final wanted = <String, String?>{
        'DisplayName': _kWindowsAppName,
        'CustomActivator': '{$_kWindowsActivatorGuid}',
        'IconUri': _winIconPath,
      };
      for (final entry in wanted.entries) {
        final value = entry.value;
        if (value == null || current[entry.key] == value) continue;
        await Process.run('reg', [
          'add',
          keyPath,
          '/v',
          entry.key,
          '/t',
          'REG_SZ',
          '/d',
          value,
          '/f',
        ]);
      }
    } catch (e) {
      // Не критично для запуска: хуже всего — тост без лого/без доставки,
      // но приложение работать не перестанет.
      debugPrint('NotificationService: не удалось прописать AUMID: $e');
    }
  }

  /// Читает все строковые значения ключа реестра одним вызовом `reg query`.
  /// Строки вывода имеют вид `<имя>    REG_SZ    <значение>`; всё, что не
  /// разбирается (заголовок, пустые строки, не-REG_SZ), просто пропускаем.
  ///
  /// Значение без данных (`DisplayName    REG_SZ` и пустота) сюда не попадёт —
  /// и это правильно: пустой DisplayName для нас неотличим от отсутствующего,
  /// оба надо перезаписать.
  ///
  /// Известное ограничение: `reg.exe` печатает в консольной кодировке (cp866),
  /// а Dart декодирует вывод как ANSI — путь с кириллицей в профиле совпадёт
  /// не побайтово и IconUri будет переписываться на каждом вызове. Это лишний
  /// `reg add`, а не ошибка: значение всё равно получается верным.
  Future<Map<String, String>> _regQueryAll(String keyPath) async {
    final result = await Process.run('reg', ['query', keyPath]);
    if (result.exitCode != 0) return const {};
    final values = <String, String>{};
    for (final line in (result.stdout as String).split('\n')) {
      final parts = line.trim().split(RegExp(r'\s+REG_SZ\s+'));
      if (parts.length != 2) continue;
      values[parts[0].trim()] = parts[1].trim();
    }
    return values;
  }

  /// Абсолютный путь к иконке приложения для тоста Windows.
  ///
  /// Приложение не упаковано (нет MSIX), поэтому лого берётся не из манифеста,
  /// а из реестрового значения IconUri — туда плагин кладёт этот путь.
  ///
  /// Иконку распаковываем из ассетов в папку данных приложения, а НЕ ссылаемся
  /// на неё внутри сборки: путь рядом с exe (`data/flutter_assets/…`) зависит
  /// от раскладки сборки и исчезает после `flutter clean`, а реестровая запись
  /// переживает и то и другое. Ошибка → null: тост без лого лучше, чем битая
  /// ссылка на картинку.
  Future<String?> _windowsIconPath() async {
    if (defaultTargetPlatform != TargetPlatform.windows) return null;
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}${Platform.pathSeparator}toast_icon.png');
      final bytes = (await rootBundle.load('assets/icon/icon_windows.png'))
          .buffer
          .asUint8List();
      // Перезаписываем только если файла нет или он изменился (обновление иконки).
      if (!file.existsSync() || file.lengthSync() != bytes.length) {
        await file.writeAsBytes(bytes, flush: true);
      }
      debugPrint('Windows toast icon: ${file.path}');
      return file.path;
    } catch (e) {
      debugPrint('Windows toast icon failed: $e');
      return null;
    }
  }

  /// Запрашивает разрешения (показ уведомлений + точные будильники).
  /// Вызывать ПОСЛЕ старта UI, не блокируя запуск приложения.
  Future<void> requestPermissions() async {
    if (!_isSupportedPlatform) return;
    final android = _android;
    if (android == null) return;
    await android.requestNotificationsPermission();
    // На Android < 13 SCHEDULE_EXACT_ALARM не нужен; на 13 — USE_EXACT_ALARM
    // выдан при установке. Запрос ниже — страховка, тихий no-op если уже есть.
    try {
      await android.requestExactAlarmsPermission();
    } catch (_) {}
  }

  /// Включены ли системные уведомления для приложения (null — неизвестно).
  Future<bool?> areNotificationsEnabled() async {
    if (!_isSupportedPlatform) return null;
    return _android?.areNotificationsEnabled();
  }

  /// Пересобирает ВСЁ расписание под текущие настройки и список задач.
  /// Сначала снимает все прежние, потом ставит заново — идемпотентно.
  Future<void> applySchedule({
    required NotificationPrefs prefs,
    required List<Task> tasks,
    required List<Goal> goals,
    required int pendingTransferCount,
    required Map<int, int> unfinishedByDay,
    required int taskBacklogCount,
    required int goalBacklogCount,
  }) async {
    if (!_isSupportedPlatform) return;
    // Ключ AUMID на Windows может быть вычищен уже ПОСЛЕ старта приложения —
    // а расписание живёт дольше сессии, поэтому перед тем, как ставить тосты,
    // убеждаемся, что к моменту их срабатывания приложение ещё «прописано».
    await _ensureWindowsRegistration();
    await _plugin.cancelAll();
    if (!prefs.enabled) return;
    final l10n = _l10n;

    // 1. Утренний план.
    if (prefs.morningPlan && !prefs.isQuiet(prefs.morningMinutes)) {
      await _scheduleDaily(
        id: _idMorning,
        minutesOfDay: prefs.morningMinutes,
        title: l10n.notifMorningTitle,
        body: l10n.notifMorningBody,
        channel: _Channel.planning,
      );
    }

    // 2. Вечерняя рефлексия.
    if (prefs.eveningReview && !prefs.isQuiet(prefs.eveningMinutes)) {
      await _scheduleDaily(
        id: _idEvening,
        minutesOfDay: prefs.eveningMinutes,
        title: l10n.notifEveningTitle,
        body: l10n.notifEveningBody,
        channel: _Channel.planning,
      );
    }

    // 3. Общие напоминания — пара раз в день. Не «по будильнику»: ставятся
    // только на дни, где реально есть невыполненное, и несут его число.
    // Пустое «не забудь про задачи» в день, когда задач нет, приучает
    // отмахиваться от уведомлений приложения целиком.
    if (prefs.generalReminders) {
      for (final entry in _generalSlots.entries) {
        final id = entry.key;
        final minute = entry.value;
        if (prefs.isQuiet(minute)) continue;
        await _scheduleOnDays(
          id: id,
          minutesOfDay: minute,
          countsByDay: unfinishedByDay,
          title: 'Enitor',
          body: (count) => id == _idGeneral2
              ? l10n.notifGeneral2(count)
              : l10n.notifGeneral1(count),
          channel: _Channel.general,
        );
      }
    }

    // Разбор недели. Единственный экран, который сравнивает неделю с прошлой,
    // и он спрятан в профиле — без напоминания про него просто не вспоминают.
    // Парой к уведомлению идёт окно с итогами при первом открытии приложения
    // после этого момента (см. WeeklyRetroController).
    if (prefs.weeklyRetro && !prefs.isQuiet(prefs.retroMinutes)) {
      await _scheduleWeekly(
        id: _idWeeklyRetro,
        weekday: prefs.retroWeekday,
        minutesOfDay: prefs.retroMinutes,
        title: l10n.notifRetroTitle,
        body: l10n.notifRetroBody,
        channel: _Channel.planning,
      );
    }

    // Бэклог задач. Единственное место в приложении, которое само о себе не
    // напоминает: задача попадает туда, когда её выкидывают из дня, и дальше
    // молчит. Пустой бэклог — молчим и мы.
    if (prefs.taskBacklogReminder && taskBacklogCount > 0) {
      for (final entry in _taskBacklogSlots.entries) {
        final (weekday, minute) = entry.value;
        if (prefs.isQuiet(minute)) continue;
        await _scheduleWeekly(
          id: entry.key,
          weekday: weekday,
          minutesOfDay: minute,
          title: l10n.notifTaskBacklogTitle,
          body: l10n.notifTaskBacklogBody(taskBacklogCount),
          channel: _Channel.general,
        );
      }
    }

    // Бэклог целей — раз в месяц: наполняется он несравнимо медленнее, чем
    // задачный, и чаще напоминать не о чем.
    if (prefs.goalBacklogReminder &&
        goalBacklogCount > 0 &&
        !prefs.isQuiet(_goalBacklogMinutes)) {
      await _scheduleMonthly(
        id: _idGoalBacklog,
        dayOfMonth: _goalBacklogDay,
        minutesOfDay: _goalBacklogMinutes,
        title: l10n.notifGoalBacklogTitle,
        body: l10n.notifGoalBacklogBody(goalBacklogCount),
        channel: _Channel.goal,
      );
    }

    // Общие напоминания по целям — отдельно от общих напоминаний по задачам:
    // не каждый день, а пару раз в неделю (понедельник утром — спланировать
    // неделю, пятница вечером — проверить прогресс перед выходными).
    if (prefs.goalGeneralReminders) {
      final messages = {
        _idGoalWeekly1: l10n.notifGoalGeneral1,
        _idGoalWeekly2: l10n.notifGoalGeneral2,
      };
      for (final entry in _goalWeeklySlots.entries) {
        final id = entry.key;
        final (weekday, minute) = entry.value;
        if (prefs.isQuiet(minute)) continue;
        await _scheduleWeekly(
          id: id,
          weekday: weekday,
          minutesOfDay: minute,
          title: l10n.notifGoalGeneralTitle,
          body: messages[id] ?? l10n.notifGoalGeneral1,
          channel: _Channel.goal,
        );
      }
    }

    // Уведомление о переносе — только когда реально есть невыполненные
    // задачи/цели прошлого периода, ожидающие подтверждения (пересчитывается
    // на каждом reschedule(), т.е. на каждом открытии приложения и изменении
    // данных). Не даёт пустых уведомлений «ни о чём».
    if (prefs.transferReminder && pendingTransferCount > 0) {
      await _scheduleDaily(
        id: _idTransfer,
        minutesOfDay: 4 * 60,
        title: l10n.notifTransferTitle,
        body: l10n.notifTransferBody(pendingTransferCount),
        channel: _Channel.planning,
      );
    }

    // 4. Напоминания к началу задач (одноразовые, к конкретной дате/времени).
    if (prefs.taskReminders) {
      final now = tz.TZDateTime.now(tz.local);
      var id = _taskIdBase;
      for (final task in tasks) {
        if (task.startMinutes == null) continue;
        final start = task.startMinutes!;
        final fireMinute = start - prefs.taskLeadMinutes;
        final day = task.date;
        final when = tz.TZDateTime(
          tz.local,
          day.year,
          day.month,
          day.day,
          fireMinute ~/ 60,
          fireMinute % 60,
        );
        if (!when.isAfter(now)) continue; // момент уже прошёл
        final lead = prefs.taskLeadMinutes;
        final body = lead > 0
            ? l10n.notifTaskLeadBody(lead, task.title, _fmt(start))
            : l10n.notifTaskNowBody(task.title, _fmt(start));
        await _scheduleAt(
          id: id++,
          when: when,
          title: l10n.notifTaskSoonTitle,
          body: body,
          channel: _Channel.task,
        );
        if (id - _taskIdBase >= 48) break; // не упираемся в лимит ОС
      }
    }

    // 5. Напоминания к концу задач (тоже одноразовые). Срабатывают и для уже
    // начавшихся задач — в отличие от блока (4), который смотрит только на
    // ещё не наступивший старт.
    if (prefs.taskEndReminders) {
      final now = tz.TZDateTime.now(tz.local);
      var id = _taskEndIdBase;
      for (final task in tasks) {
        final end = _taskEndAt(task);
        if (end == null) continue;
        final lead = prefs.taskEndLeadMinutes;
        final when = end.subtract(Duration(minutes: lead));
        if (!when.isAfter(now)) continue;
        final body = lead > 0
            ? l10n.notifTaskEndLeadBody(lead, task.title)
            : l10n.notifTaskEndNowBody(task.title);
        await _scheduleAt(
          id: id++,
          when: when,
          title: l10n.notifTaskEndTitle,
          body: body,
          channel: _Channel.task,
        );
        if (id - _taskEndIdBase >= 48) break;
      }
    }

    // 6. «Требует внимания» — тот же порог, что и бейдж в списке задач:
    // за 30 минут до конца, либо (если конца нет) в 23:00 в день задачи.
    if (prefs.taskUrgentAlerts) {
      final now = tz.TZDateTime.now(tz.local);
      var id = _taskUrgentIdBase;
      for (final task in tasks) {
        final when = _taskUrgentAt(task);
        if (!when.isAfter(now)) continue;
        await _scheduleAt(
          id: id++,
          when: when,
          title: l10n.notifTaskUrgentTitle,
          body: l10n.notifTaskUrgentBody(task.title),
          channel: _Channel.task,
        );
        if (id - _taskUrgentIdBase >= 48) break;
      }
    }

    // 7. «Просрочена» — момент реального конца задачи, либо (если конца нет)
    // полночь после дня задачи — согласовано с _TimeState.overdue в
    // today_screen.dart.
    if (prefs.taskOverdueAlerts) {
      final now = tz.TZDateTime.now(tz.local);
      var id = _taskOverdueIdBase;
      for (final task in tasks) {
        final when = _taskOverdueAt(task);
        if (!when.isAfter(now)) continue;
        await _scheduleAt(
          id: id++,
          when: when,
          title: l10n.notifTaskOverdueTitle,
          body: l10n.notifTaskOverdueBody(task.title),
          channel: _Channel.task,
        );
        if (id - _taskOverdueIdBase >= 48) break;
      }
    }

    // 8. Цели: «требует внимания» — тот же порог, что и бейдж в списке целей
    // (за urgencyThreshold дней до дедлайна/конца периода).
    if (prefs.goalUrgentAlerts) {
      final now = tz.TZDateTime.now(tz.local);
      var id = _goalUrgentIdBase;
      for (final goal in goals) {
        final when = _goalUrgentAt(goal);
        if (when == null || !when.isAfter(now)) continue;
        await _scheduleAt(
          id: id++,
          when: when,
          title: l10n.notifGoalUrgentTitle,
          body: l10n.notifGoalUrgentBody(goal.title),
          channel: _Channel.goal,
        );
        if (id - _goalUrgentIdBase >= 200) break;
      }
    }

    // 9. Цели: «просрочена» — на следующий день после конца периода,
    // согласовано с _GoalUrgency.overdue в goals_screen.dart.
    if (prefs.goalOverdueAlerts) {
      final now = tz.TZDateTime.now(tz.local);
      var id = _goalOverdueIdBase;
      for (final goal in goals) {
        final when = _goalOverdueAt(goal);
        if (!when.isAfter(now)) continue;
        await _scheduleAt(
          id: id++,
          when: when,
          title: l10n.notifGoalOverdueTitle,
          body: l10n.notifGoalOverdueBody(goal.title),
          channel: _Channel.goal,
        );
        if (id - _goalOverdueIdBase >= 200) break;
      }
    }
  }

  /// Момент, когда цель становится «срочной» — за urgencyThreshold дней до
  /// дедлайна (или конца периода, если дедлайна нет), в 9:00 — см.
  /// _GoalUrgency.urgent в goals_screen.dart. null, если этот момент уже
  /// позади конца периода (тогда цель либо просрочена, либо порог ей не
  /// подходит — не планируем в прошлое).
  tz.TZDateTime? _goalUrgentAt(Goal goal) {
    final effectiveDeadline = goal.deadline ?? goal.periodEnd;
    final threshold = goal.ref.urgencyThreshold;
    final d = effectiveDeadline.subtract(Duration(days: threshold));
    return tz.TZDateTime(tz.local, d.year, d.month, d.day, 9);
  }

  /// Момент, когда цель становится просроченной — на следующий день после
  /// конца периода, в 9:00 (см. _GoalUrgency.overdue).
  tz.TZDateTime _goalOverdueAt(Goal goal) {
    final d = goal.periodEnd.add(const Duration(days: 1));
    return tz.TZDateTime(tz.local, d.year, d.month, d.day, 9);
  }

  /// Абсолютный момент конца задачи (с учётом «через полночь»), либо null,
  /// если у задачи нет времени конца.
  tz.TZDateTime? _taskEndAt(Task task) {
    final end = task.endMinutes;
    if (end == null) return null;
    final start = task.startMinutes;
    final overnight = start != null && end < start;
    final day = task.date;
    final base = overnight
        ? DateTime(day.year, day.month, day.day).add(const Duration(days: 1))
        : DateTime(day.year, day.month, day.day);
    return tz.TZDateTime(
        tz.local, base.year, base.month, base.day, end ~/ 60, end % 60);
  }

  /// Момент, когда задача становится просроченной — совпадает с концом,
  /// либо, если конца нет, с полуночью после дня задачи (см. _TimeState.overdue).
  tz.TZDateTime _taskOverdueAt(Task task) {
    final end = _taskEndAt(task);
    if (end != null) return end;
    final day = task.date;
    final midnight =
        DateTime(day.year, day.month, day.day).add(const Duration(days: 1));
    return tz.TZDateTime(tz.local, midnight.year, midnight.month, midnight.day);
  }

  /// Момент, когда задача становится «срочной» — за 30 минут до конца, либо,
  /// если конца нет, в 23:00 в день задачи (см. _TimeState.urgent).
  tz.TZDateTime _taskUrgentAt(Task task) {
    final end = _taskEndAt(task);
    if (end != null) return end.subtract(const Duration(minutes: 30));
    final day = task.date;
    return tz.TZDateTime(tz.local, day.year, day.month, day.day, 23, 0);
  }

  Future<void> cancelAll() async {
    if (!_isSupportedPlatform) return;
    await _plugin.cancelAll();
  }

  // ── Примитивы ──────────────────────────────────────────────────────────

  // На Windows-канале plugin.zonedSchedule() не пробрасывает
  // matchDateTimeComponents (нативного повтора там нет вовсе — см. исходники
  // flutter_local_notifications_windows), поэтому там расписываем ежедневное
  // уведомление явно на N дней вперёд, каждый день — отдельным id.
  static const _windowsDailyDays = 14;

  bool get _isWindows => defaultTargetPlatform == TargetPlatform.windows;

  /// Ежедневное уведомление в [minutesOfDay]. На Android/iOS — один вызов с
  /// повтором через matchDateTimeComponents; на Windows — явный цикл на
  /// [_windowsDailyDays] дней вперёд (см. комментарий выше).
  Future<void> _scheduleDaily({
    required int id,
    required int minutesOfDay,
    required String title,
    required String body,
    required _Channel channel,
  }) async {
    if (_isWindows) {
      for (var d = 0; d < _windowsDailyDays; d++) {
        final when = _nextInstanceOf(minutesOfDay ~/ 60, minutesOfDay % 60)
            .add(Duration(days: d));
        await _scheduleAt(
          id: id * 100 + d,
          when: when,
          title: title,
          body: body,
          channel: channel,
        );
      }
      return;
    }
    final when = _nextInstanceOf(minutesOfDay ~/ 60, minutesOfDay % 60);
    await _plugin.zonedSchedule(
      id,
      title,
      body,
      when,
      _details(channel),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time, // повтор каждый день
    );
  }

  /// Слот в [minutesOfDay], но только в те дни, где есть о чём напоминать:
  /// [countsByDay] — смещение от сегодня → число невыполненного.
  ///
  /// В отличие от [_scheduleDaily] расписывается явными одноразовыми
  /// уведомлениями на ВСЕХ платформах, а не системным ежедневным повтором:
  /// повтор сработал бы и в день, когда напоминать нечего, и уж точно не смог
  /// бы назвать число задач — то есть вся «умность» терялась бы на следующий
  /// же день.
  Future<void> _scheduleOnDays({
    required int id,
    required int minutesOfDay,
    required Map<int, int> countsByDay,
    required String title,
    required String Function(int count) body,
    required _Channel channel,
  }) async {
    final now = tz.TZDateTime.now(tz.local);
    final today = DateTime(now.year, now.month, now.day);
    for (var d = 0; d < _generalHorizonDays; d++) {
      final count = countsByDay[d];
      if (count == null || count <= 0) continue;
      final day = today.add(Duration(days: d));
      // Через конструктор, а не сложением Duration: при переходе на летнее
      // время сложение сдвинуло бы час, а нам нужны те же 12:30 по стене.
      final when = tz.TZDateTime(
        tz.local,
        day.year,
        day.month,
        day.day,
        minutesOfDay ~/ 60,
        minutesOfDay % 60,
      );
      if (!when.isAfter(now)) continue; // сегодняшний слот уже прошёл
      await _scheduleAt(
        id: id * 100 + d,
        when: when,
        title: title,
        body: body(count),
        channel: channel,
      );
    }
  }

  // На Windows столько же занятых недель вперёд планируем явно (нет
  // matchDateTimeComponents для еженедельного повтора — та же причина, что и
  // у _scheduleDaily выше).
  static const _windowsWeeklyOccurrences = 8;

  /// Еженедельное уведомление в [weekday] (1=пн..7=вс) в [minutesOfDay]. На
  /// Android/iOS — один вызов с повтором через matchDateTimeComponents; на
  /// Windows — явный цикл на [_windowsWeeklyOccurrences] недель вперёд.
  Future<void> _scheduleWeekly({
    required int id,
    required int weekday,
    required int minutesOfDay,
    required String title,
    required String body,
    required _Channel channel,
  }) async {
    if (_isWindows) {
      for (var w = 0; w < _windowsWeeklyOccurrences; w++) {
        final when = _nextWeekdayInstanceOf(
                weekday, minutesOfDay ~/ 60, minutesOfDay % 60)
            .add(Duration(days: 7 * w));
        await _scheduleAt(
          id: id * 100 + w,
          when: when,
          title: title,
          body: body,
          channel: channel,
        );
      }
      return;
    }
    final when =
        _nextWeekdayInstanceOf(weekday, minutesOfDay ~/ 60, minutesOfDay % 60);
    await _plugin.zonedSchedule(
      id,
      title,
      body,
      when,
      _details(channel),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents:
          DateTimeComponents.dayOfWeekAndTime, // повтор каждую неделю
    );
  }

  /// Ежемесячное уведомление [dayOfMonth]-го числа в [minutesOfDay].
  ///
  /// Месячного повтора нет в плагине ни на одной платформе (у
  /// matchDateTimeComponents есть только «время» и «день недели + время»),
  /// поэтому расписываем ближайшие [_monthlyOccurrences] месяцев явно —
  /// как это уже делается для еженедельных на Windows.
  Future<void> _scheduleMonthly({
    required int id,
    required int dayOfMonth,
    required int minutesOfDay,
    required String title,
    required String body,
    required _Channel channel,
  }) async {
    final now = tz.TZDateTime.now(tz.local);
    final moments = monthlyOccurrencesAfter(
      now,
      dayOfMonth: dayOfMonth,
      minutesOfDay: minutesOfDay,
      count: _monthlyOccurrences,
    );
    for (var i = 0; i < moments.length; i++) {
      final m = moments[i];
      await _scheduleAt(
        id: id * 100 + i,
        when: tz.TZDateTime(tz.local, m.year, m.month, m.day, m.hour, m.minute),
        title: title,
        body: body,
        channel: channel,
      );
    }
  }

  /// Одноразовое уведомление в конкретный момент [when].
  Future<void> _scheduleAt({
    required int id,
    required tz.TZDateTime when,
    required String title,
    required String body,
    required _Channel channel,
  }) async {
    await _plugin.zonedSchedule(
      id,
      title,
      body,
      when,
      _details(channel),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );
  }

  /// Ближайшее наступление времени hh:mm (сегодня, если ещё не прошло — иначе завтра).
  tz.TZDateTime _nextInstanceOf(int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled =
        tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (!scheduled.isAfter(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }

  /// Ближайшее наступление [weekday] (1=пн..7=вс, как DateTime.weekday) в
  /// hh:mm — сегодня, если сегодня тот день недели и время ещё не прошло,
  /// иначе следующее совпадение дня недели.
  tz.TZDateTime _nextWeekdayInstanceOf(int weekday, int hour, int minute) {
    var scheduled = _nextInstanceOf(hour, minute);
    while (scheduled.weekday != weekday) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }

  NotificationDetails _details(_Channel channel) {
    final (id, name, desc, importance) = switch (channel) {
      _Channel.planning => (
          _planChannelId,
          _planChannelName,
          _planChannelDesc,
          Importance.high
        ),
      _Channel.task => (
          _taskChannelId,
          _taskChannelName,
          _taskChannelDesc,
          Importance.high
        ),
      _Channel.general => (
          _generalChannelId,
          _generalChannelName,
          _generalChannelDesc,
          Importance.defaultImportance
        ),
      _Channel.goal => (
          _goalChannelId,
          _goalChannelName,
          _goalChannelDesc,
          Importance.high
        ),
    };
    return NotificationDetails(
      android: AndroidNotificationDetails(
        id,
        name,
        channelDescription: desc,
        importance: importance,
        priority: Priority.defaultPriority,
      ),
    );
  }

  static String _fmt(int m) =>
      '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  /// Уведомления поддерживаются на Android и Windows (iOS/macOS — позже).
  bool get _isSupportedPlatform =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.windows);
}

enum _Channel { planning, task, general, goal }

final notificationServiceProvider = Provider<NotificationService>(
  (ref) => throw UnimplementedError('Override in main()'),
);
