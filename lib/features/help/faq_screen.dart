import 'package:flutter/material.dart';

import '../../core/theme/appearance.dart';
import '../../core/utils/format_utils.dart';
import '../../l10n/l10n_extensions.dart';
import 'pomodoro_guide_sheet.dart';

/// Один вопрос-ответ.
class _Qa {
  const _Qa(
    this.q,
    this.a,
    this.qEn,
    this.aEn, {
    this.opensPomodoroGuide = false,
  });
  final String q;
  final String a;
  final String qEn;
  final String aEn;

  /// Под ответом рисуется кнопка, открывающая полный гайд по длинам
  /// (см. [showPomodoroGuideSheet]). Ответ в FAQ даёт суть, но гайд длинный
  /// и с нажимаемыми пресетами — пересказывать его тут целиком незачем.
  final bool opensPomodoroGuide;

  String question(bool ru) => ru ? q : qEn;
  String answer(bool ru) => ru ? a : aEn;
}

/// Раздел FAQ.
class _Section {
  const _Section(this.title, this.titleEn, this.icon, this.items);
  final String title;
  final String titleEn;
  final IconData icon;
  final List<_Qa> items;

  String label(bool ru) => ru ? title : titleEn;
}

const List<_Section> _kFaq = [
  _Section('Задачи', 'Tasks', Icons.check_circle_outline, [
    _Qa(
      'Как добавить задачу?',
      'Кнопка «+ Задача» внизу экрана «Сегодня». На компьютере — ещё и Ctrl+N. '
          'Можно указать время, оценку длительности, приоритет, теги, '
          'подзадачи и повтор — всё необязательно, минимум это название.',
      'How do I add a task?',
      'The “+ Task” button at the bottom of the Today screen. On desktop, '
          'also Ctrl+N. You can set a time, a duration estimate, priority, '
          'tags, subtasks, and repetition — all optional; the only '
          'requirement is a title.',
    ),
    _Qa(
      'Чем оценка времени отличается от фактического?',
      'Оценка — сколько ты планируешь потратить (заполняется при создании, '
          'необязательно). Факт — сколько ушло на самом деле, заполняется при '
          'выполнении или копится Помодоро-таймером. Сравнение этих двух чисел '
          'даёт «точность оценок» в Статистике.',
      "What's the difference between the time estimate and the actual time?",
      'The estimate is how long you plan to spend (filled in when creating '
          'the task, optional). The actual is how long it really took — '
          'filled in when completing the task, or accumulated by the '
          'Pomodoro timer. Comparing these two numbers gives you “estimate '
          'accuracy” in Stats.',
    ),
    _Qa(
      'Как работает Помодоро?',
      'Таймер фокуса, а за ним перерыв. По умолчанию 25 и 5 минут — '
          'классические цифры, но подходят они не всем, поэтому обе длины '
          'настраиваются: Настройки → Таймер фокуса. Новая длина берётся со '
          'следующего отрезка, идущий таймер остаётся с той, с которой '
          'начался.\n\n'
          'Всё время фокуса копится в фактическое время задачи. Если отметишь '
          'задачу выполненной, пока таймер идёт, — он остановится и запишет '
          'накопленное.\n\n'
          'Таймер открывается на весь экран, и экран, пока он открыт, не '
          'гаснет. «Свернуть» (или «назад», Esc) убирает его в карточку на '
          '«Задачах» — таймер идёт дальше, нажатие на карточку разворачивает '
          'снова. На компьютере пробел ставит на паузу и продолжает.\n\n'
          'Конец фокуса и перерыва — двойной сигнал и вибрация в такт; '
          'музыку он лишь ненадолго приглушает. Если приложение свёрнуто, '
          'тот же сигнал подаст уведомление «Таймер фокуса».',
      'How does Pomodoro work?',
      'A focus timer, followed by a break. The defaults are 25 and 5 minutes '
          "— the classic numbers, but they don't suit everyone, so both "
          'lengths are configurable: Settings → Focus timer. A new length '
          'takes effect from the next stretch; a running timer keeps the one '
          'it started with.\n\n'
          "All focus time accumulates into the task's actual time. If you "
          'mark the task done while the timer is running, it stops and '
          "records what's been accumulated.\n\n"
          'The timer opens full screen, and the screen stays on while it is '
          'open. “Minimize” (or Back, Esc) tucks it into a card on Tasks — '
          'the timer keeps running; tap the card to open it again. On '
          'desktop, Space pauses and resumes.\n\n'
          'The end of focus and of a break is a double chime with vibration '
          'in time; music only dips for a moment. If the app is minimized, '
          'a “Focus timer” notification plays the same chime.',
    ),
    _Qa(
      'Какую длину фокуса и перерыва выбрать?',
      'Единственно правильной цифры нет: 25 минут — число из книги Чирилло, а '
          'не из исследования. Твоя длина лежит между двумя моментами — '
          'сколько ты входишь в задачу и через сколько начинаешь выпадать.\n\n'
          'Отталкивайся от типа работы. Код, текст, дизайн, сложная учёба — '
          '45/10: первые 10–15 минут там уходят на разгон, и 25-минутный '
          'отрезок обрывается ровно тогда, когда ты наконец вошёл. Почта и '
          'рутина — 20/5, там разгона нет вообще. Всего понемногу — 25/5. '
          'Тяжело начать — 15/5: короткий отрезок тем и хорош, что начать его '
          'не страшно.\n\n'
          'Дальше подстраивай по одному сигналу: что ты чувствуешь в момент '
          'звонка. Облегчение («ну наконец-то») — отрезок длинный, убавь 10 '
          'минут. Досада («я только въехал») — короткий, прибавь 10. '
          'Спокойное «о, уже? ладно» — это твоя длина.\n\n'
          'Перерыв берут примерно в пятую часть от фокуса и не больше 15 '
          'минут: за этой границей ты не возвращаешься к работе, а начинаешь '
          'её заново. И он должен быть отдыхом другого типа — встать, вода, '
          'окно; лента голове не отдых, из неё ещё и не выйти по звонку.\n\n'
          'Полный гайд — с тем, сколько отрезков делать подряд, что делать, '
          'когда звонок застал на середине мысли, и что означает «не помогает '
          'вообще», — по кнопке ниже. Он же лежит в Настройки → Таймер '
          'фокуса.',
      'What focus and break lengths should I pick?',
      "There is no single right number: 25 minutes comes from Cirillo's book, "
          'not from a study. Your length sits between two moments — how long '
          'you take to get into a task, and how long before you drift out.\n\n'
          'Start from the kind of work. Code, writing, design, hard study — '
          '45/10: the first 10–15 minutes there go into the warm-up, and a '
          '25-minute stretch cuts out exactly when you finally got in. Email '
          'and routine — 20/5, no warm-up at all. A bit of everything — 25/5. '
          'Hard to start — 15/5: a short stretch is good precisely because '
          'starting it is not scary.\n\n'
          'After that, tune by one signal: how you feel at the bell. Relief '
          '("finally") means the stretch is long — take 10 minutes off. '
          'Annoyance ("I\'d just got going") means it is short — add 10. A '
          'calm "already? fine" means you found your length.\n\n'
          'A break is usually a fifth of the focus and never over 15 minutes: '
          'past that line you do not return to the work, you start it again. '
          'And it has to be a different kind of rest — stand up, water, a '
          'window; a feed is no rest for your head, and you cannot leave it at '
          'the bell.\n\n'
          'The full guide — how many stretches to do in a row, what to do when '
          'the bell catches you mid-thought, and what it means when nothing '
          'helps at all — is behind the button below. It also lives in '
          'Settings → Focus timer.',
      opensPomodoroGuide: true,
    ),
    _Qa(
      'Что такое счётчик и чек-лист?',
      'Счётчик — задача с целевым числом (например «выпить 5 стаканов воды»): '
          'выполняется при достижении числа. Чек-лист — задача с подзадачами: '
          'выполняется, когда отмечены все. Частичный прогресс честно учитывается '
          'в продуктивности.',
      'What are counters and checklists?',
      'A counter is a task with a target number (e.g. “drink 5 glasses of '
          "water”): it's completed once you reach the number. A checklist "
          "is a task with subtasks: it's completed once all of them are "
          'checked. Partial progress is honestly counted toward '
          'productivity.',
    ),
    _Qa(
      'Зачем приоритеты и теги?',
      'Приоритет влияет на сортировку (среди задач без времени важные выше) и '
          'показывается иконкой. Теги группируют задачи и дают отдельную '
          'статистику по тегам.',
      'What are priorities and tags for?',
      'Priority affects sorting (among untimed tasks, important ones rank '
          'higher) and is shown as an icon. Tags group tasks and give you '
          'separate stats by tag.',
    ),
    _Qa(
      'Как найти старую задачу или цель?',
      'Лупа в шапке экрана. На «Сегодня» она ищет по задачам, на «Целях» — по '
          'целям. Ищет по названию, описанию и тегам одновременно, так что '
          'можно искать и по «#работа». Выбранный результат открывает свой '
          'день (для задачи) или свою цель.',
      'How do I find an old task or goal?',
      'The magnifier in the screen header. On Today it searches tasks, on '
          'Goals it searches goals. It looks at the title, the description and '
          'the tags at once, so searching by "#work" works too. Picking a '
          'result opens the day it belongs to (for a task) or the goal itself.',
    ),
    _Qa(
      'Что делают «Скопировать все» и «Удалить все»?',
      'Кнопки стоят прямо над списком задач (и целей). «Скопировать все» '
          'переносит задачи выбранного дня в другой день — удобно, '
          'когда день похож на прошлый и не хочется набивать всё заново; для '
          'целей так же, но копируется в другой период. «Удалить все» очищает '
          'весь список выбранного дня (или периода) разом и спрашивает '
          'подтверждение — отменить это нельзя. Если один и тот же набор '
          'нужен регулярно, лучше не копировать каждый раз, а сохранить его '
          'шаблоном дня.',
      'What do "Copy all" and "Delete all" do?',
      'The buttons sit right above the task (and goal) list. "Copy all" '
          'puts the selected day\'s tasks onto another day — handy when a '
          'day resembles a previous one and you\'d rather not retype it; for '
          'goals it works the same way, copying into another period. "Delete '
          'all" clears the whole list for the selected day (or period) at '
          'once and asks for confirmation — it cannot be undone. If you need '
          'the same set regularly, save it as a day template instead of '
          'copying it every time.',
    ),
    _Qa(
      'Как сделать повторяющуюся задачу?',
      'В форме задачи включи «Повторяется» и выбери режим: ежедневно, по дням '
          'недели, по числам месяца или через интервал. Экземпляры создаются '
          'сами, когда открываешь соответствующий день.',
      'How do I make a recurring task?',
      'In the task form, turn on “Repeats” and choose a mode: daily, by '
          'weekday, by day of the month, or every N days. Occurrences are '
          'created automatically as you open the corresponding day.',
    ),
    _Qa(
      'Можно ли свернуть календарь?',
      'Да: переключатель на самом календаре меняет вид — месяц, две недели или '
          'неделя. Приложение запоминает выбор. Он хранится отдельно на каждом '
          'устройстве: на телефоне может стоять неделя, а на компьютере месяц.',
      'Can I collapse the calendar?',
      'Yes: the switch on the calendar itself changes the view — month, two '
          'weeks or week. The app remembers your choice. It is kept separately '
          'on each device, so your phone can show a week and your computer a '
          'month.',
    ),
  ]),
  _Section('Расписание', 'Schedule', Icons.event_note_outlined, [
    _Qa(
      'Чем расписание отличается от задач?',
      'Задачу нужно сделать и отметить, она влияет на статистику. Пункт '
          'расписания — то, что просто идёт в своё время: пара, тренировка, '
          'смена. Отмечать его не надо. Занятое время видно и на вкладке '
          '«Задачи»: сводка вверху списка открывает расписание.',
      'How is the schedule different from tasks?',
      'A task has to be done and checked off, and it counts in your stats. A '
          'schedule item simply happens at its time: a class, a workout, a '
          'shift. There is nothing to check off. Busy time also shows on the '
          'Tasks tab: the summary above the list opens the schedule.',
    ),
    _Qa(
      'Как добавить пункт и настроить повтор?',
      'На вкладке «Расписание» нажми «+ Пункт». Нужны название и начало, '
          'остальное необязательно: конец, заметка, место, цвет, напоминание '
          'и повтор. Повтор бывает по дням недели (каждую неделю или через '
          'неделю), по числам месяца и через интервал. «Через неделю» считается '
          'от недели, в которой создан пункт, поэтому создавай его на неделе, '
          'когда занятие есть.',
      'How do I add an item and set it to repeat?',
      'On the Schedule tab press “+ Event”. It needs a title and a start time; '
          'the rest is optional: end time, note, place, colour, reminder and '
          'repeat. It can repeat by weekday (every week or every other week), '
          'by day of the month, or at an interval. “Every other week” counts '
          'from the week the item was created in, so create it in a week when '
          'the class takes place.',
    ),
    _Qa(
      'Как поменять или удалить только один день серии?',
      'Открой пункт в нужный день и измени его. При сохранении приложение '
          'спросит: только этот день или вся серия. То же при удалении — через '
          'меню пункта или свайпом влево. Другие дни серии при выборе «только '
          'этот день» не меняются.',
      'How do I change or delete just one day of a series?',
      'Open the item on that day and edit it. When saving, the app asks: just '
          'this day or the whole series. Deleting works the same way, from the '
          'item menu or with a swipe left. Choosing “just this day” leaves the '
          'other days of the series as they are.',
    ),
    _Qa(
      'Что показывает кнопка «Неделя»?',
      'Обзор недели выбранного дня, с понедельника по воскресенье: её даты '
          'видны в шапке, а пункты — по дням. Нажатие на день открывает его. '
          'Кнопка «День» возвращает к обычному виду.',
      'What does the “Week” button show?',
      'An overview of the selected day’s week, Monday to Sunday: its dates are '
          'in the header and the items are grouped by day. Tapping a day opens '
          'it. The “Day” button returns to the usual view.',
    ),
    _Qa(
      'Что значит «Накладка»?',
      'Два пункта в один день пересекаются по времени. Приложение только '
          'предупреждает пометкой и ничего не двигает само.',
      'What does “Overlaps” mean?',
      'Two items on the same day overlap in time. The app only flags this and '
          'does not move anything by itself.',
    ),
    _Qa(
      'Как сделать из пункта задачу?',
      'В меню пункта выбери «Сделать задачей»: только на этот день или, для '
          'серии, повторяющуюся задачу по тому же правилу. Там же есть '
          '«Дублировать», чтобы быстро создать похожий пункт.',
      'How do I turn an item into a task?',
      'Choose “Make a task” in the item menu: for this day only or, for a '
          'series, as a recurring task with the same rule. The same menu has '
          '“Duplicate” for quickly creating a similar item.',
    ),
    _Qa(
      'Как загрузить расписание вуза или график смен?',
      'Пока расписание пустое — кнопкой «Взять расписание из календаря (.ics)» '
          'прямо на вкладке. В любой момент — Настройки → Интеграции → '
          '«Календари»: импорт .ics из файла или по ссылке. Перед импортом '
          'видно, что попадёт в расписание, а что нет и почему (например, '
          'события на весь день — у пункта расписания должно быть время). '
          'Пункты попадут на вкладку «Расписание». Повторный '
          'импорт того же календаря обновляет их, а не дублирует. Твои правки '
          'в Enitor остаются: пункт меняется, только если событие изменили в '
          'самом календаре, а удалённое здесь не возвращается. Календарь по '
          'ссылке можно обновлять раз в день сам или кнопкой «Обновить сейчас».',
      'How do I load a university timetable or shift plan?',
      'While the schedule is empty — with the “Take a schedule from a '
          'calendar (.ics)” button right on the tab. Any time — Settings → '
          'Integrations → “Calendars”: import an .ics file or link. Before '
          'importing you see what goes in and what does not and why (for '
          'example, all-day events — a schedule item needs a time). The '
          'items land on the Schedule tab. Importing the same '
          'calendar again updates them rather than duplicating them. Your '
          'edits in Enitor stay: an item changes only when the event changed '
          'in the calendar itself, and what you deleted here does not come '
          'back. A calendar from a link can update once a day by itself or '
          'with “Update now”.',
    ),
  ]),
  _Section(
    'Перенос и «день с 4:00»',
    'Carryover and the "4:00 day"',
    Icons.schedule,
    [
      _Qa(
        'Почему невыполненная задача переехала на сегодня?',
        'На границе дня (в 4:00) приложение предлагает перенести незакрытые '
            'задачи прошлых дней на сегодня, но не молча: ты подтверждаешь '
            'перенос — плашкой вверху экрана, если приложение открыто, или '
            'списком-напоминанием при следующем запуске — и сам выбираешь, что '
            'перенести. Перенос делает копию на сегодня; оригинал остаётся в '
            'своём дне с обычным цветом статуса и маленьким значком-стрелкой. '
            'Историю мы не переписываем.',
        'Why did an unfinished task move to today?',
        'At the day rollover (4:00) the app offers to carry your unfinished '
            'tasks from past days over to today — but not silently: you confirm '
            'the carry-over (a banner at the top of the screen if the app is '
            'open, or a reminder list on the next launch) and choose what moves. '
            'Carrying over creates a copy on today; the original stays on its '
            'own day with its usual status colour and a small arrow badge. '
            'History is never rewritten.',
      ),
      _Qa(
        'Почему день «начинается» в 4:00, а не в полночь?',
        'Чтобы ночные часы относились к уходящему дню. До 4:00 утра активным '
            'считается вчерашний день — удобно, если ложишься поздно.',
        'Why does the day "start" at 4:00 instead of midnight?',
        "So that late-night hours belong to the day that's ending. Until "
            '4:00 AM, yesterday is still considered the active day — handy '
            'if you go to bed late.',
      ),
      _Qa(
        'Почему прошлые дни нельзя редактировать?',
        'Прошлое — только для чтения, чтобы статистика была честной. Перенос '
            'делается копией на сегодня, а не правкой истории.',
        "Why can't I edit past days?",
        "The past is read-only so that stats stay honest. Carrying a task "
            'over creates a copy on today rather than editing history.',
      ),
      _Qa(
        'Что такое «Невыполненные задачи» (бэклог)?',
        'Если перенесённая задача снова не сделана и переезжает повторно, она '
            'уходит в бэклог «Невыполненные задачи» — чтобы сегодняшний список не '
            'засорялся, но дело не потерялось. Оттуда её можно вернуть.',
        'What\'s the "Unfinished tasks" backlog?',
        'If a carried-over task is left undone again, it moves into the '
            '"Unfinished tasks" backlog — so today\'s list doesn\'t get '
            "cluttered, but nothing is lost. You can bring it back from "
            'there anytime.',
      ),
      _Qa(
        'Зачем шаблоны дня?',
        'Сохрани типовой набор задач (например «рабочий день») как шаблон и '
            'применяй в любой день одним нажатием — задачи добавятся с нуля. '
            'У «Расписания» шаблоны свои: кнопка «Шаблоны» в шапке дня '
            'сохраняет его пункты и кладёт их на другой день разовыми, '
            'а пункты, которые там уже есть, не повторяет.',
        'What are day templates for?',
        'Save a typical set of tasks (e.g. a "workday") as a template and '
            'apply it to any day with one tap — the tasks get added fresh. '
            'The Schedule has its own templates: the Templates button in the '
            "day's header saves its events and puts them on another day as "
            'one-off events, skipping the ones that day already has.',
      ),
    ],
  ),
  _Section('Цели', 'Goals', Icons.flag_outlined, [
    _Qa(
      'Какие бывают цели?',
      'Обычная (галочка), счётчик-квота (прогресс к числу за период) и '
          'чек-лист (набор подзадач). Счётчик меряется в разах («12 книг») '
          'или в часах («20 часов английского»). У цели есть период: неделя, '
          'месяц, сезон или год, и необязательный дедлайн.',
      'What types of goals are there?',
      'A plain goal (checkbox), a counter/quota (progress toward a number '
          'over a period), and a checklist (a set of subtasks). A counter is '
          'measured in times ("12 books") or in hours ("20 hours of '
          'English"). Every goal has a period — week, month, season, or '
          'year — and an optional deadline.',
    ),
    _Qa(
      'Как привязать задачи к цели?',
      'Цель-счётчик можно связать с задачами (поле «Цель» в задаче). Если '
          'счётчик в разах, каждая выполненная задача прибавляет 1 — удобно '
          'для «10 тренировок в месяц». Если в часах, в цель идёт время '
          'фокуса по задаче, а задача, сделанная без таймера, отдаёт свою '
          'оценку. Кнопки ± у цели в часах шагают по полчаса, а число можно '
          'ввести дробным: «1,5». «−» убавляет только то, что ты добавил '
          'сам: если весь прогресс от задач, она серая — поправь задачу. '
          'Минуты задачи (фокус или фактическое время) идут в цель, даже '
          'если отметку снять; оценка — только пока задача выполнена.',
      'How do I link tasks to a goal?',
      'A counter goal can be linked to tasks (the Goal field of a task). '
          'For a counter in times, each completed task adds 1 — handy for '
          '"10 workouts this month". For a counter in hours, the focus time '
          'logged on the task goes in, and a task done without the timer '
          'adds its estimate. On an hours goal the ± buttons step by half an '
          'hour, and you can type a fraction like "1.5". The − button only '
          'takes back what you added yourself: if all progress comes from '
          'tasks, it is greyed out — edit the task instead. Minutes on a task '
          '(focus or actual time) count even if you uncheck it; its estimate '
          'counts only while it is done.',
    ),
    _Qa(
      'Можно ли сделать цель частью другой?',
      'Да. В форме цели выбери «Часть цели» — там цели-счётчики более '
          'длинного периода, в который попадает твоя: неделя может быть '
          'частью месяца, сезона или года, месяц — сезона или года, сезон — '
          'года. Прогресс подцели сам идёт вверх, в том числе по цепочке '
          'неделя → месяц → сезон → год. Счётчик отдаёт своё число, обычная '
          'цель или чек-лист — 1, когда достигнуты. В цель в часах можно '
          'вложить только цели в часах. Неделя на стыке месяцев относится к '
          'месяцу, в котором началась.\n\n'
          'Пример: месячная «Книги — 20 ч» и недельная «Книги — 5 ч» с '
          'пометкой «Часть цели» на месячную. Задачи с чтением привязывай к '
          'недельной — время попадёт и в неделю, и в месяц.',
      'Can a goal be part of another?',
      'Yes. In the goal form pick “Part of a goal” — it lists counter goals '
          'of a longer period that contains yours: a week can be part of a '
          'month, season or year, a month part of a season or year, a season '
          'part of a year. Progress flows up by itself, all the way along '
          'week → month → season → year. A counter passes on its number; a '
          'plain goal or a checklist adds 1 once it is reached. An hours goal '
          'only takes hours goals inside it. A week that spans two months '
          'belongs to the month it starts in.\n\n'
          'Example: a monthly “Reading — 20 h” and a weekly “Reading — 5 h” '
          'marked as part of the monthly one. Link your reading tasks to the '
          'weekly goal — the time lands in both the week and the month.',
    ),
    _Qa(
      'Что такое дедлайн у цели и когда цель «в срок»?',
      'Дедлайн — необязательная дата внутри периода, к которой цель нужно '
          'закрыть. Цель достигнута в срок, если закрыта не позже дедлайна, а '
          'если дедлайна нет — не позже последнего дня периода. От этого зависит '
          'статистика «Соблюдение дедлайнов».',
      "What's a goal deadline, and when is a goal \"on time\"?",
      'A deadline is an optional date within the period by which the goal '
          "should be done. A goal counts as achieved on time if it's closed no "
          "later than the deadline — or, if there's no deadline, no later than "
          'the last day of the period. This feeds the “Deadline compliance” '
          'stats.',
    ),
    _Qa(
      'Почему цель пожелтела или покраснела?',
      'Жёлтая («требует внимания») — до дедлайна или конца периода осталось '
          'мало дней (порог зависит от типа: неделя — 2, месяц — 5, сезон — 10, '
          'год — 15 дней). Красная — период уже закончился, а цель не достигнута. '
          'Приоритет и теги у целей работают как у задач: важные невыполненные '
          'цели поднимаются выше, а по тегам есть отдельная статистика.',
      'Why did a goal turn yellow or red?',
      'Yellow (“needs attention”) means few days are left until the deadline '
          'or the end of the period (the threshold depends on the type: week — '
          '2, month — 5, season — 10, year — 15 days). Red means the period has '
          "ended and the goal isn't achieved. Priority and tags work like they "
          'do for tasks: important unfinished goals rise to the top, and tags '
          'give separate stats.',
    ),
    _Qa(
      'Можно ли перенести цель в другой период?',
      'Да. Когда период закончился, цель можно перенести в текущий период того '
          'же типа кнопкой-стрелкой. А если цель уже «требует внимания» (скоро '
          'конец), её можно досрочно подтолкнуть в следующий период через меню. '
          'Как и у задач, перенос делает копию, а оригинал остаётся со '
          'значком-стрелкой.',
      'Can I move a goal to another period?',
      'Yes. Once the period is over, you can carry the goal into the current '
          'period of the same type with the arrow button. And if a goal already '
          '“needs attention” (nearing its end), you can push it into the next '
          'period early from the menu. As with tasks, carrying over creates a '
          'copy and the original keeps an arrow badge.',
    ),
    _Qa(
      'Что такое сезон?',
      'Метеорологический сезон из трёх месяцев: зима (декабрь–февраль), весна '
          '(март–май), лето (июнь–август), осень (сентябрь–ноябрь). Зима '
          'переходит через Новый год, поэтому подписывается двумя годами — '
          'например «Зима 2026/27».',
      "What's a season?",
      'A meteorological three-month season: winter (December–February), '
          'spring (March–May), summer (June–August), autumn '
          '(September–November). Winter crosses the New Year, so it’s labelled '
          'with both years — e.g. “Winter 2026/27”.',
    ),
  ]),
  _Section('Статистика', 'Stats', Icons.show_chart, [
    _Qa(
      'Как считается продуктивность?',
      'Это доля выполненного за день с учётом дробного вклада чек-листов и '
          'счётчиков (наполовину сделанный чек-лист даёт половину).',
      'How is productivity calculated?',
      "It's the share of the day's work completed, counting the "
          'fractional contribution of checklists and counters (a '
          'half-finished checklist counts as half).',
    ),
    _Qa(
      'Что значит «в срок»?',
      'Доля выполненных задач, закрытых вовремя. У задачи со временем '
          '«вовремя» — до конца её запланированного времени. Задача без '
          'времени считается выполненной в срок, если закрыта в свой день; '
          'если отметить её уже после полуночи, она засчитывается как '
          'просроченная. В метрику входят все выполненные задачи.',
      'What does "on time" mean?',
      'The share of completed tasks finished on time. For a task with a '
          'time, "on time" means before the end of its scheduled time. A task '
          'without a time counts as on time if you close it on its own day; '
          'finishing it after midnight makes it count as overdue. All '
          'completed tasks are included in this metric.',
    ),
    _Qa(
      'Как выбирается «Лучший день/период»?',
      'По составному баллу: продуктивность × немного бонуса за «в срок» × вес '
          'за объём. Так насыщенный продуктивный день обходит день с одной '
          'задачей «на 100%».',
      'How is "Best day/period" chosen?',
      'By a composite score: productivity × a small bonus for being on '
          'time × a weight for volume. So a busy, productive day beats a '
          'day with just one task "at 100%".',
    ),
    _Qa(
      'Что показывает «Соблюдение дедлайнов»?',
      'Насколько рано или поздно ты закрываешь цели относительно срока. За '
          'срок берётся дедлайн цели, а если он не задан — конец её периода. '
          'Показывается медиана по всем достигнутым целям, в днях, со знаком: '
          '«−2 д» значит, что обычно ты закрываешь цель за два дня до срока, '
          '«+2 д» — что на два дня позже. Ноль и любой минус считаются '
          '«в срок» и подсвечиваются зелёным. Медиана, а не среднее, — чтобы '
          'одна забытая на месяц цель не портила всю картину.',
      'What does "Deadline compliance" show?',
      'How early or late you close goals relative to their due date. The due '
          'date is the goal deadline, or the end of its period if no deadline '
          'is set. It shows the median across all achieved goals, in days, '
          'with a sign: "−2 d" means you usually close a goal two days before '
          'the due date, "+2 d" means two days after. Zero and any negative '
          'value count as on time and are shown in green. It is a median '
          'rather than an average so that one goal forgotten for a month '
          "doesn't skew the whole picture.",
    ),
    _Qa(
      'Где посмотреть статистику по тегам?',
      'Статистика → «Статистика по тегам» (для целей — «Статистика по тегам '
          'целей» на вкладке «Цели»). Там по каждому тегу видно, сколько дел '
          'выполнено и какая доля из них закрыта в срок. Удобно, чтобы '
          'заметить, что какая-то область жизни систематически проваливается, '
          'а не тонет в общей цифре.',
      'Where do I see stats per tag?',
      'Stats → "Tag stats" (for goals, "Goal tag stats" on the Goals tab). '
          'For each tag it shows how many items you completed and what share '
          'of them were on time. Useful for noticing that one area of life is '
          'consistently slipping instead of it being hidden inside the overall '
          'number.',
    ),
    _Qa(
      'Что за «точность оценок»?',
      'Сравнение оценки и факта по задачам, где заполнены оба значения '
          '(берётся медиана, чтобы выбросы не врали). Показаны ДВЕ цифры: '
          '«по количеству задач» — каждая задача весит одинаково, и «по '
          'времени» — крупные по длительности задачи весят больше, поэтому '
          'промах на пятиминутном перекусе почти не влияет на неё, в отличие '
          'от первой цифры. Разбивка по размеру задачи и по тегам показывает '
          'обе цифры тоже. Факт заполняется в диалоге «Сколько времени '
          'ушло?» после выполнения задачи с оценкой — это необязательно, '
          'аналитика считает только заполненные пары. Карточка появляется, '
          'когда наберётся хотя бы 3 такие пары.',
      'What is "estimate accuracy"?',
      'A comparison of estimate vs. actual for tasks where both values are '
          "filled in (using the median, so outliers don't skew things). Two "
          'numbers are shown: "by task count" — every task weighs the same, '
          'and "by time" — longer tasks weigh more, so a miss on a '
          'five-minute snack barely moves it, unlike the first number. The '
          'breakdown by task size and by tag shows both numbers too. The '
          'actual is filled in via the "How long did it take?" dialog after '
          "completing a task with an estimate — it's optional, and the "
          'analysis only counts filled pairs. The card appears once you '
          'have at least 3 such pairs.',
    ),
  ]),
  _Section('Профиль и достижения', 'Profile and achievements', Icons.emoji_events_outlined, [
    _Qa(
      'Что такое серия (streak)?',
      'Число дней подряд, закрытых на 100% (все задачи дня выполнены). Дни без '
          'задач нейтральны — серию не рвут и не продлевают. Сегодняшний ещё не '
          'закрытый день серию тоже не обрывает. Повторяющаяся задача на день '
          'считается, даже если приложение в тот день не открывали: не '
          'выполнена — серия рвётся. В Профиле видно текущую серию и рекорд.',
      "What's a streak?",
      'The number of consecutive days closed at 100% (all of the day’s tasks '
          'done). Days with no tasks are neutral — they neither break nor '
          "extend the streak. Today, if it isn't closed yet, doesn't break it "
          'either. A repeating task counts for its day even if you never '
          'opened the app that day: not done — the streak breaks. The Profile '
          'shows your current streak and your record.',
    ),
    _Qa(
      'Что показывает тепловая карта года?',
      'Каждая ячейка — день (столбцы — недели, строки — дни недели), цвет — '
          'насколько продуктивным был день (с учётом своевременности). Дни без '
          'задач — нейтральные. Объём и «в срок» — во всплывающей подсказке.',
      'What does the year heatmap show?',
      'Each cell is a day (columns are weeks, rows are weekdays); the colour '
          'shows how productive the day was (taking timeliness into account). '
          'Days with no tasks are neutral. Volume and “on time” appear in the '
          'tooltip.',
    ),
    _Qa(
      'Как оценить день?',
      'Вечером на экране «Сегодня» появляется карточка «оцени день» — поставь '
          'оценку от 1 до 10. Это субъективная рефлексия, на продуктивность она '
          'не влияет, но идёт в «Итоги недели» и в достижения.',
      'How do I rate a day?',
      'In the evening an “rate your day” card appears on the Today screen — '
          "give it a score from 1 to 10. It's your subjective reflection; it "
          'doesn’t affect productivity, but it feeds the “Week summary” and '
          'achievements.',
    ),
    _Qa(
      'Что такое «Итоги недели»?',
      'Сводка завершённой недели (Профиль → Итоги недели): продуктивность с '
          'изменением к прошлой неделе, выполненные задачи, лучший день, '
          'идеальные дни, цели на эту неделю (сколько из поставленных '
          'достигнуто — а если их не ставили, так и написано), достигнутые '
          'цели любого периода и средняя оценка дней. Можно листать недели '
          'назад.',
      'What is the "Week summary"?',
      'A summary of a finished week (Profile → Week summary): productivity '
          'with the change vs last week, completed tasks, the best day, perfect '
          'days, the goals set for that week (how many of them you achieved — '
          'and if none were set, it says so), goals of any period achieved '
          'during it, and the average day rating. You can page back through '
          'weeks.',
    ),
    _Qa(
      'Что за окно с итогами при запуске?',
      'Разбор прошедшей недели. Показывается один раз за неделю — при первом '
          'открытии приложения после назначенного момента (по умолчанию '
          'понедельник, 19:00; день и время меняются в Настройках → Уведомления → '
          'Итоги недели). Внутри: продуктивность недели и сравнение с предыдущей, '
          'задачи, лучший день, цели на неделю и точность оценок — стала она '
          'лучше или хуже, чем неделей раньше.\n\n'
          'Понедельник, а не воскресенье, потому что неделя должна быть '
          'завершена: по правилу дня в 4:00 она закрывается только утром '
          'понедельника. Если мерить в воскресенье вечером, ещё не сделанные '
          'воскресные задачи попадают в знаменатель, и каждая неделя выглядит '
          'чуть хуже предыдущей просто из-за момента замера.\n\n'
          'Если приложение в этот вечер не открывали, окно дождётся '
          'следующего запуска — хоть в среду. Если за ту неделю данных нет '
          'вообще (ни дней с задачами, ни целей), окно не показывается: '
          'рассказывать не о чем. Каждый блок внутри тоже появляется только '
          'при своих данных — точность оценок, например, требует минимум трёх '
          'задач с заполненными оценкой и фактом.\n\n'
          'Недельную цель можно закрыть ещё двое суток после конца недели '
          '(grace-окно периода) — то есть в понедельник и вторник. Поэтому, '
          'пока это окно открыто, счёт целей в разборе не окончательный, и '
          'под ним так и написано: «их ещё можно закрыть». Само окно — '
          'снимок на момент показа, а экран Профиль → Итоги недели всегда '
          'считает заново, так что закрытая во вторник цель там уже учтётся.',
      'What is that summary window on launch?',
      'The review of the past week. It shows once a week — at the first app '
          'launch after the configured moment (Monday 19:00 by default; the '
          'day and time are in Settings → Notifications → Week summary). Inside: the week’s '
          'productivity and how it compares with the week before, tasks, the '
          'best day, the goals set for that week, and estimate accuracy — '
          'whether it got better or worse than the week before.\n\n'
          'Monday rather than Sunday because the week has to be finished: '
          'under the 4:00 day rule it only closes on Monday morning. Measured '
          'on Sunday evening, your still-unfinished Sunday tasks land in the '
          'denominator, and every week ends up looking slightly worse than the '
          'last one purely because of when it was measured.\n\n'
          'If the app wasn’t opened that evening, the window waits for the '
          'next launch — Wednesday is fine. If there’s no data for that week '
          'at all (no days with tasks, no goals), the window doesn’t appear: '
          'there’s nothing to report. Each block inside also appears only when '
          'it has data — estimate accuracy, for instance, needs at least three '
          'tasks with both an estimate and an actual.\n\n'
          'A weekly goal stays closable for two more days after the week ends '
          '(the period’s grace window) — Monday and Tuesday. So while that '
          'window is open the goal count in the review isn’t final, and it '
          'says so underneath: "you can still close them". The window itself '
          'is a snapshot taken when it appeared; Profile → Week summary always '
          'recomputes, so a goal closed on Tuesday shows up there.',
    ),
    _Qa(
      'Что такое достижения и как их получить?',
      'Значки за прогресс: объём (выполненные задачи и цели), серии, '
          'пунктуальность и качество, вехи (дней в приложении, идеальные дни). '
          'Открываются, когда метрика достигает порога, и больше не теряются. '
          'Топовые скрыты как «???», пока не откроешь. Прогресс — в Профиль → '
          'Достижения, о новом открытии приходит уведомление.',
      'What are achievements and how do I earn them?',
      'Badges for progress: volume (completed tasks and goals), streaks, '
          'punctuality and quality, milestones (days using the app, perfect '
          'days). They unlock when a metric reaches its target and are never '
          'taken away. Top ones stay hidden as “???” until you earn them. '
          'Progress is in Profile → Achievements, and a new unlock triggers a '
          'notification.',
    ),
  ]),
  _Section('Уведомления', 'Notifications', Icons.notifications_outlined, [
    _Qa(
      'Какие бывают напоминания?',
      'По задачам: к началу и к концу задачи (за выбранное число минут), '
          '«требует внимания» (скоро конец) и «просрочена». По целям: «требует '
          'внимания» у дедлайна/конца периода, «просрочена» и общие напоминания '
          'о целях. Плюс утренний план, вечерняя оценка дня, напоминание об '
          'итогах недели (по умолчанию понедельник, 19:00 — день и время '
          'настраиваются) и напоминание о переносе на границе дня. Всё '
          'включается по отдельности в Настройках.\n\n'
          'Отдельно — про бэклог: среда 18:00 и суббота 12:00 по задачам '
          '(середина недели, чтобы хвост не оброс, и выходной, когда его есть '
          'когда разгрести) и 1-е число месяца в 11:00 по целям. По целям '
          'реже, потому что бэклог целей и наполняется несравнимо медленнее: '
          'цель живёт периодом, а не днём. Первое число выбрано не случайно — '
          'это момент, когда ставят цели на новый месяц, и отложенное стоит '
          'пересмотреть прежде, чем придумывать новое.\n\n'
          'Ни одно из них не шлётся вхолостую. Общие «не забудь про задачи» '
          'ставятся только на дни, где реально есть невыполненное, и называют '
          'его число: в день без задач их просто не будет. Напоминания о '
          'бэклогах молчат, когда бэклог пуст. Напоминание о '
          'переносе молчит, когда переносить нечего. Разбор недели не '
          'показывается, если за неделю нет данных.\n\n'
          'Выключено по умолчанию только напоминание о переносе. Оно '
          'содержательное, но его момент жёстко привязан к границе дня — 4:00 '
          '— и потому тихие часы его не сдвигают: включённым оно '
          'будило бы среди ночи, а невыполненное всё равно встретит диалогом '
          'при первом открытии приложения. Включается там же, если такой ритм '
          'подходит.',
      'What kinds of reminders are there?',
      'For tasks: before a task starts and before it ends (by a chosen '
          'number of minutes), "needs attention" (nearing its end), and '
          '"overdue". For goals: "needs attention" near the deadline/period '
          'end, "overdue", and general goal nudges. Plus a morning plan, an '
          'evening day review, a week-summary nudge (Monday 19:00 by default '
          '— the day and time are configurable), and a carry-over reminder at '
          'the day rollover. Each is toggled separately in Settings.\n\n'
          'The backlog gets its own: Wednesday 18:00 and Saturday 12:00 for '
          'tasks (midweek so the tail doesn\'t grow, and a weekend day when '
          'there is time to clear it), the 1st of the month at 11:00 for '
          'goals. Goals get a rarer slot because that backlog fills far more '
          'slowly — a goal lives in a period, not a day. The 1st isn\'t '
          'arbitrary either: it\'s when you set goals for a new month, and '
          'what you shelved is worth revisiting before inventing something '
          'new.\n\n'
          'None of them fire on an empty day. The general "don\'t forget your '
          'tasks" nudges are only scheduled for days that actually have '
          'unfinished tasks, and they name how many: on a day with nothing '
          'planned there is simply no nudge. The backlog reminders stay quiet '
          'when the backlog is empty. The carry-over reminder stays '
          'quiet when there is nothing to carry over. The week summary '
          'doesn\'t appear when the week has no data.\n\n'
          'Only the carry-over reminder is off by default. It does carry real '
          'information, but its moment is pinned to the day rollover — 4:00 — '
          'so quiet hours cannot move it: on by default '
          'it would wake you at night, and unfinished items greet you in a '
          'dialog at the next launch anyway. Turn it on in the same place if '
          'that rhythm suits you.',
    ),
    _Qa(
      'Что такое тихие часы?',
      'Окно (по умолчанию 23:00–08:00), когда общие и умные напоминания '
          'молчат.\n\n'
          'Исключения, которые приходят всегда:\n'
          '• напоминания к началу и концу задач, для которых ты поставил время;\n'
          '• «требует внимания» и «просрочена» у задачи, у которой стоит время '
          'конца;\n'
          '• напоминания из Расписания: время у каждого пункта назначаешь ты;\n'
          '• напоминание о переносе: его момент жёстко привязан к границе дня '
          '(4:00), сдвинуть его нельзя, поэтому подчиняться тихим часам ему '
          'нечем. Именно поэтому оно единственное выключено по умолчанию.\n\n'
          'У задачи без времени конца «требует внимания» (23:00 в день задачи) '
          'и «просрочена» (полночь) выбирает приложение. В тихие часы они не '
          'будят: приходят в конце тихих часов, по умолчанию в 8:00.\n\n'
          'У целей «требует внимания» и «просрочена» стоят на 9:00. Если этот '
          'час попадает в тихие часы, они тоже переносятся на их конец.',
      'What are quiet hours?',
      'A window (23:00–08:00 by default) during which general and smart '
          'reminders stay silent.\n\n'
          'Exceptions that always fire:\n'
          '• reminders before the start and end of tasks you set a time for;\n'
          '• "needs attention" and "overdue" for a task that has an end time;\n'
          '• schedule reminders: you set the time for each item;\n'
          '• the carry-over reminder: its moment is pinned to the day rollover '
          '(4:00) and can’t be moved, so there is nothing for quiet hours to '
          'shift. That is exactly why it is the one reminder off by default.\n\n'
          'For a task with no end time, "needs attention" (23:00 on the task’s '
          'day) and "overdue" (midnight) are chosen by the app. During quiet '
          'hours they stay silent and arrive at the end of quiet hours instead '
          '(8:00 by default).\n\n'
          'For goals, "needs attention" and "overdue" are set at 9:00. If that '
          'hour falls inside quiet hours, they move to the end of quiet hours too.',
    ),
    _Qa(
      'Почему уведомления не приходят?',
      'На телефоне чаще всего система усыпляет приложение в фоне (особенно '
          'Infinix/Transsion, Xiaomi, Huawei). Разреши работу в фоне по '
          'подсказке в приложении или вручную: Настройки телефона → Батарея → '
          'отключить оптимизацию для Enitor и включить автозапуск.\n\n'
          'На Windows причина обычно другая — антивирус. Чтобы показать '
          'уведомление, система опознаёт приложение по записи, которую Enitor '
          'делает в реестре при запуске. Антивирусы с песочницей (замечено за '
          'Kaspersky и 360 Total Security) считают неподписанное приложение '
          'недоверенным и заворачивают эту запись в теневую копию: Enitor '
          'думает, что прописался, а система его не видит и молча выбрасывает '
          'каждое уведомление. Само приложение это обнаружить не может — '
          'читая запись обратно, оно получает ту же теневую копию. Лечится '
          'добавлением Enitor в доверенные (исключения) в антивирусе.',
      "Why aren't notifications arriving?",
      'On the phone the system usually puts the app to sleep in the '
          'background (especially on Infinix/Transsion, Xiaomi, Huawei). Allow '
          'background activity via the in-app hint, or manually: Phone '
          'Settings → Battery → disable optimization for Enitor and enable '
          'autostart.\n\n'
          'On Windows the cause is usually different — your antivirus. To show '
          'a notification, the system identifies the app by an entry Enitor '
          'writes to the registry on startup. Antivirus suites that sandbox '
          'unknown applications (Kaspersky and 360 Total Security both do) '
          'treat an unsigned app as untrusted and redirect that write into a '
          'shadow copy: Enitor believes it registered, the system never sees '
          'it, and every notification is silently discarded. The app cannot '
          'detect this itself — reading the value back returns the same '
          'shadow copy. Adding Enitor to your antivirus trusted list fixes it.',
    ),
  ]),
  _Section('Интеграции', 'Integrations', Icons.hub_outlined, [
    _Qa(
      'Интеграции что-то отправляют на сервер?',
      'Нашего сервера нет — Enitor его не запускает. Всё работает на этом '
          'устройстве: ссылки, «Поделиться», Tasker и консоль говорят с '
          'приложением напрямую. Наружу данные уходят, только если ты сам '
          'добавишь адрес вебхука, загрузишь календарь по своей ссылке, '
          'разрешишь ИИ-ассистенту читать план или подключишь свой сервер для '
          'синхронизации. Синхронизация по сети отдаёт данные только твоим '
          'устройствам, с которыми ты их познакомил. Свой сервер получает данные только по адресу, который '
          'ты ввёл. На Android он ещё шлёт короткий сигнал через доставщика '
          'push — без твоих данных.',
      'Do integrations send anything to a server?',
      'There is no Enitor server of ours — we do not run one. Everything works '
          'on this device: links, “Share”, Tasker and the console talk to the '
          'app directly. Data leaves only if you add a webhook address yourself, '
          'load a calendar from your own link, let an AI assistant read your '
          'plan, or connect your own server for sync. Network sync gives data '
          'only to your own devices that you paired. Your own server receives '
          'data only at the address you entered. On Android it also sends a '
          'short push signal through the distributor app, with none of your '
          'data in it.',
    ),
    _Qa(
      'Как синхронизировать телефон и компьютер?',
      'Проще всего — напрямую по Wi-Fi: Настройки → Синхронизация. На одном '
          'устройстве нажми «Добавить устройство» — появятся QR-код и код. На '
          'другом наведи на QR-код камеру телефона или нажми «Ввести код» и '
          'введи его, а на первом подтверди. Знакомить нужно один раз; дальше '
          'устройства в одной сети обмениваются сами, зашифрованно, без '
          'интернета. На телефоне обмен идёт, пока Enitor открыт. Если '
          'устройства далеко друг от друга — нужен свой сервер (enitor-server, '
          'лежит рядом с enitor.exe, есть сборка для Linux): там же, в блоке '
          '«Свой сервер», подключи к нему устройства по адресу и токену. '
          'Инструкция — docs/integrations/server.ru.md в репозитории.',
      'How do I sync my phone and PC?',
      'The easiest way is directly over Wi-Fi: Settings → Sync. On one device '
          'press “Add a device” — a QR code and a code appear. On the other, '
          'point the phone camera at the QR code or press “Enter a code” and '
          'type it, then confirm on the first one. You pair them once; after '
          'that, devices on the same network sync by themselves, encrypted, '
          'with no internet. On a phone, sync runs while Enitor is open. If the '
          'devices are far apart, you need your own server (enitor-server, next '
          'to enitor.exe, with a Linux build too): connect the devices to it in '
          'the same place, under “Own server”, with the address and the token. '
          'The guide is docs/integrations/server.md in the repository.',
    ),
    _Qa(
      'Синхронизация по сети безопасна? Сосед по Wi-Fi не увидит мои задачи?',
      'Не увидит. Устройства говорят только с теми, с кем ты их познакомил, '
          'и только зашифрованно. Код из 12 знаков нельзя подобрать, пока он '
          'действует (5 минут), а после пяти неверных попыток он меняется. Кто '
          'ввёл верный код, всё равно попадёт в группу, только если ты '
          'подтвердишь это на своём устройстве. Потерянное устройство можно '
          'отключить — оно перестанет получать данные от всей группы.',
      'Is network sync safe? Can someone on the same Wi-Fi see my tasks?',
      'No. Devices talk only to the ones you paired them with, and only '
          'encrypted. The 12-character code can’t be guessed while it is valid '
          '(5 minutes), and it changes after five wrong tries. Even with the '
          'right code, a device joins only after you confirm it on yours. A '
          'lost device can be removed — it stops getting data from the whole '
          'group.',
    ),
    _Qa(
      'Что выбрать при подключении: объединить или заменить?',
      '«Объединить» сохраняет данные и устройства, и сервера: подходит почти '
          'всегда. «Заменить» стирает данные этого устройства и берёт серверные. '
          'Это нужно, когда устройство новое или его данные больше не важны. '
          'Перед заменой сохранится авто-бэкап.',
      'Which one do I pick when connecting: merge or replace?',
      '“Merge” keeps the data of both the device and the server, and it suits '
          'almost every case. “Replace” wipes this device’s data and takes the '
          'server’s. Use it when the device is new or its data no longer '
          'matters. An auto-backup is saved before replacing.',
    ),
    _Qa(
      'Как быстро приходят изменения с сервера?',
      'Пока Enitor открыт — за пару секунд: он держит связь с сервером, и '
          'тот сразу сообщает о новом. Своя правка уходит на сервер секунды '
          'через три после последнего изменения. Для подстраховки приложение '
          'ещё и само спрашивает сервер раз в 5 минут и при каждом открытии. '
          'Закрытый Enitor на Android забирает изменения в фоне примерно раз '
          'в 15 минут (Android может сдвигать это время), а с приложением для '
          'push, например ntfy, — за секунды. На компьютере фонового обмена '
          'нет: всё придёт при следующем запуске. Кнопка «Синхронизировать '
          'сейчас» запускает обмен сразу.',
      'How fast do changes arrive from the server?',
      'While Enitor is open, within a couple of seconds: it keeps a connection '
          'to the server, which reports anything new right away. Your own edit '
          'goes to the server about three seconds after your last change. As a '
          'safety net the app also asks the server every 5 minutes and every '
          'time it opens. A closed Enitor on Android picks up changes in the '
          'background about every 15 minutes (Android may shift that time), '
          'and within seconds with a push app such as ntfy. On a computer there '
          'is no background sync: everything arrives the next time you start '
          'it. The “Sync now” button starts an exchange right away.',
    ),
    _Qa(
      'Что будет, если изменить одно и то же на двух устройствах?',
      'Побеждает правка, которая дошла до сервера позже, — целиком, без '
          'смешивания полей. Если на одном устройстве запись удалили, а на '
          'другом потом изменили, она вернётся. Если два устройства независимо '
          'создали одну и ту же запись (например, экземпляр повтора), остаётся '
          'та, что была на сервере первой.',
      'What if I change the same thing on two devices?',
      'The edit that reaches the server later wins, as a whole, without mixing '
          'fields. If one device deleted a record and another edited it later, '
          'the record comes back. If two devices created the same record on '
          'their own (a repeat instance, for example), the one that reached the '
          'server first stays.',
    ),
    _Qa(
      'Где посмотреть, какие устройства подключены?',
      'Настройки → Синхронизация. В «Устройствах в сети» — вся группа: '
          'кто сейчас в сети и когда был обмен; крестик отключает устройство '
          'насовсем. У своего сервера — свой список «Устройства»: крестик '
          'убирает из него старое устройство, а если оно снова выйдет на '
          'связь, то вернётся. Чтобы устройство перестало получать данные с '
          'сервера, нажми на нём «Отключить» или смени токен на сервере.',
      'Where do I see which devices are connected?',
      'Settings → Sync. “Devices on your network” shows the whole group: who '
          'is online now and when they last synced; the cross removes a device '
          'for good. Your own server has its own “Devices” list: the cross '
          'removes an old device from it, and if it syncs again, it comes back. '
          'To stop a device from getting data from the server, press '
          '“Disconnect” on it or change the token on the server.',
    ),
    _Qa(
      'Что будет с данными, если нажать «Отключить»?',
      'Ничего не пропадёт: данные останутся и на устройстве, и на сервере, '
          'просто обмен прекратится, а устройство уберёт себя из списка. '
          'Подключиться снова можно в любой момент; «Объединить» при этом не '
          'создаст дублей.',
      'What happens to my data if I press “Disconnect”?',
      'Nothing is lost: the data stays both on the device and on the server; '
          'the exchange just stops and the device removes itself from the list. '
          'You can connect again at any time, and “Merge” will not create '
          'duplicates.',
    ),
    _Qa(
      'Может ли ссылка с сайта добавить мне задачу без спроса?',
      'Нет. Ссылка enitor:// и «Поделиться» только открывают обычную '
          'анкету — заполненную и с пометкой «из ссылки». Задача появится, '
          'только когда ты нажмёшь «Добавить». Ничего не читают и не отмечают.',
      'Can a link on a website add a task without asking?',
      'No. An enitor:// link and “Share” only open the usual form — filled '
          'in and marked “from a link”. The task appears only when you press '
          'Add. They never read or mark anything.',
    ),
    _Qa(
      'Как подключить ИИ-ассистента (MCP) на компьютере?',
      'Включи «ИИ-ассистенты» в Настройки → Интеграции → Права и скопируй '
          'блок из раздела «ИИ-ассистенты». Enitor должен быть запущен. Куда '
          'вставить:\n'
          '• Claude Desktop — файл %APPDATA%\\Claude\\claude_desktop_config.json '
          '(Настройки → Developer → Edit Config). Если в файле уже есть '
          '"mcpServers", добавь внутрь только строку "enitor": {…}, второй '
          '"mcpServers" не создавай. Потом полностью закрой Claude (и в трее) '
          'и запусти снова.\n'
          '• Cursor — %USERPROFILE%\\.cursor\\mcp.json, так же внутрь '
          '"mcpServers".\n'
          '• VS Code — .vscode\\mcp.json в папке проекта или команда «MCP: '
          'Open User Configuration». Тут ключ называется "servers", а не '
          '"mcpServers"; содержимое "enitor" то же.\n'
          '• Claude Code — без файла, одной командой: claude mcp add -s user '
          'enitor -- "<путь к enitor-cli.exe>" mcp.\n'
          'Путь к enitor-cli.exe — в разделе «Windows» там же.',
      'How do I connect an AI assistant (MCP) on my computer?',
      'Turn on “AI assistants” in Settings → Integrations → Permissions and '
          'copy the block from the “AI assistants” section. Enitor must be '
          'running. Where to paste it:\n'
          '• Claude Desktop — the file %APPDATA%\\Claude\\claude_desktop_config.json '
          '(Settings → Developer → Edit Config). If the file already has '
          '"mcpServers", add only the "enitor": {…} entry inside it; do not '
          'create a second "mcpServers". Then quit Claude completely (the tray '
          'too) and start it again.\n'
          '• Cursor — %USERPROFILE%\\.cursor\\mcp.json, also inside '
          '"mcpServers".\n'
          '• VS Code — .vscode\\mcp.json in the project folder, or the “MCP: '
          'Open User Configuration” command. Here the key is "servers", not '
          '"mcpServers"; the "enitor" part is the same.\n'
          '• Claude Code — no file, one command: claude mcp add -s user enitor '
          '-- "<path to enitor-cli.exe>" mcp.\n'
          'The path to enitor-cli.exe is in the “Windows” section of the same '
          'screen.',
    ),
    _Qa(
      'Как добавлять задачи из командной строки?',
      'На Windows рядом с Enitor лежит enitor-cli.exe. Примеры: enitor-cli '
          'add Купить молоко --at 18:00 — задача; enitor-cli schedule Пара '
          '--at 10:30 --until 12:00 — пункт расписания; enitor-cli today — план '
          'дня; enitor-cli done 3f9a — отметить по началу id. Всё — enitor-cli '
          '--help. Enitor должен быть запущен, а «Консоль» — разрешена в '
          '«Правах». Чтобы вызывать его из любой папки, добавь папку Enitor в '
          'PATH.',
      'How do I add tasks from the command line?',
      'On Windows, enitor-cli.exe sits next to Enitor. Examples: enitor-cli add '
          'Buy milk --at 18:00 adds a task; enitor-cli schedule Lecture --at '
          '10:30 --until 12:00 adds a schedule item; enitor-cli today prints the '
          'day plan; enitor-cli done 3f9a marks a task by the start of its id. '
          'Everything else: enitor-cli --help. Enitor must be running, and '
          '“Console” must be allowed in Permissions. To call it from any '
          'folder, add the Enitor folder to PATH.',
    ),
    _Qa(
      'Как подключить Tasker или Automate?',
      'Разреши Tasker в Настройки → Интеграции → Права, затем в разделе '
          '«Tasker и Automate» скопируй готовый пример действия «Send Intent» — '
          'ключ в нём уже подставлен. Команда без верного ключа ничего не '
          'делает. Чтобы автоматизация могла читать план и получать ответы, '
          'нужно право «Читать» и имя её пакета в списке «Кому можно '
          'отвечать».',
      'How do I connect Tasker or Automate?',
      'Allow Tasker in Settings → Integrations → Permissions, then copy the '
          'ready “Send Intent” example from the “Tasker and Automate” section; '
          'the key is already filled in. A command without the right key does '
          'nothing. For the automation to read the plan and get replies, it '
          'needs the “Read” permission and its package name in the “Apps that '
          'may get replies” list.',
    ),
    _Qa(
      'Что такое вебхуки и зачем они?',
      'Enitor сам сообщает твоей системе о событиях: задача выполнена, день '
          'закрыт, цель достигнута. Добавь адрес (n8n, Home Assistant, свой '
          'сервер) в разделе «Вебхуки» и выбери события. Каждый запрос '
          'подписан секретом — так видно, что он от твоего Enitor. Если адрес '
          'недоступен, событие подождёт в очереди и уйдёт позже.',
      'What are webhooks for?',
      'Enitor tells your own system about events: a task is done, a day is '
          'closed, a goal is achieved. Add an address (n8n, Home Assistant, your '
          'own server) in the “Webhooks” section and pick the events. Every '
          'request is signed with a secret, so you can tell it came from your '
          'Enitor. If the address is down, the event waits in a queue and goes '
          'out later.',
    ),
    _Qa(
      'Как увидеть расписание Enitor в Google Календаре или Outlook?',
      'Настройки → Интеграции → «Экспорт в календарь (.ics)» сохраняет '
          'расписание и задачи со временем в файл; импортируй его в календарь. '
          'Это снимок, а не подписка: после изменений экспортируй снова. '
          'Обратное направление — «Импорт календаря» из файла или по ссылке.',
      'How do I see my Enitor schedule in Google Calendar or Outlook?',
      'Settings → Integrations → “Export to a calendar (.ics)” saves your '
          'schedule and timed tasks to a file; import it into your calendar. It '
          'is a snapshot, not a subscription: export again after changes. The '
          'other way round is “Import calendar” from a file or a link.',
    ),
    _Qa(
      'Что видит ИИ-ассистент?',
      'Только то, что разрешено в Настройки → Интеграции → Права. По '
          'умолчанию — ничего. «Добавлять» позволяет создавать и отмечать '
          'задачи, «Читать» — видеть план дня, и тогда названия задач уходят '
          'в модель ассистента. Удалять он не может вовсе. Последние вызовы '
          'видны там же, в журнале.',
      'What does an AI assistant see?',
      'Only what Settings → Integrations → Permissions allows. By default — '
          'nothing. “Add” lets it create and mark tasks, “Read” lets it see '
          "the day's plan, and then task titles go to the assistant's model. "
          'It cannot delete anything at all. Recent calls are listed there, '
          'in the log.',
    ),
    _Qa(
      'Попадают ли ключи и настройки интеграций в резервную копию?',
      'Нет. Ключ Tasker, токен своего сервера и секреты вебхуков лежат в '
          'защищённом хранилище системы, а настройки, очередь и журнал вебхуков '
          'и настройки синхронизации — состояние именно этого устройства. '
          'Копия с телефона не включит интеграции на компьютере, а восстановление '
          'не отправит заново ни одного вебхука.',
      'Do integration keys and settings go into backups?',
      "No. The Tasker key, your server's token and the webhook secrets live in "
          "the system's protected storage, and integration settings, the webhook "
          'queue and log, and the sync settings belong to this device only. A '
          "phone backup won't turn integrations on on your computer, and "
          "restoring it won't resend any webhook.",
    ),
    _Qa(
      'Как перенести задачи из Todoist, Google Задач или TickTick?',
      'Сделай экспорт в том приложении (подсказка, где он, — прямо в '
          'Enitor), затем Настройки → Данные → «Переезд из другого '
          'приложения». Перед импортом видно, что будет создано и что '
          'пропущено и почему; повторный импорт того же файла дублей не '
          'создаёт.',
      'How do I move my tasks from Todoist, Google Tasks or TickTick?',
      'Export them in that app (Enitor shows where), then Settings → '
          'Data → “Move in from another app”. Before importing you '
          'see what will be created and what is skipped and why; importing '
          'the same file again creates no duplicates.',
    ),
  ]),
  _Section('Резервные копии', 'Backups', Icons.backup_outlined, [
    _Qa(
      'Данные куда-то отправляются?',
      'Нет, если ты сам не включил что-то из перечисленного. Аккаунта нет, '
          'сервера Enitor нет, аналитики и телеметрии нет — всё лежит на этом '
          'устройстве. В сеть приложение ходит только за тем, что ты включил сам:\n'
          '• синхронизация — на твой сервер (его адрес ты вводишь сам);\n'
          '• синхронизация по локальной сети — между твоими устройствами в одной сети;\n'
          '• календарь по ссылке — скачивается по кнопке «Обновить сейчас» '
          'или раз в сутки, если ты включил автообновление;\n'
          '• вебхуки — отправляют изменения на адреса, которые ты задал.\n\n'
          'Без этого приложение ходит в сеть только за проверкой обновлений на '
          'GitHub: при запуске, не чаще раза в сутки. Отключить её нельзя — '
          'переключателя нет; ручная «Проверить обновления» работает по нажатию. '
          'Проверка не передаёт ни задач, ни целей, ни статистики. Файл обновления '
          'скачивается, только если ты согласился.',
      'Is my data sent anywhere?',
      'No, unless you switched on one of the things below. There is no '
          'account, no Enitor server, no analytics and no telemetry — everything '
          'lives on this device only. The app reaches the network only for what '
          'you switched on yourself:\n'
          '• sync — to your own server (you enter its address);\n'
          '• sync over the local network — between your devices on the same network;\n'
          '• calendar by link — downloaded with “Update now”, or once a day '
          'if you turned on auto-update;\n'
          '• webhooks — send changes to the addresses you set.\n\n'
          'Otherwise the only network request is the update check against GitHub: '
          'at launch, at most once a day. It cannot be turned off — there is no '
          'switch; the manual “Check for updates” button runs only when you press '
          'it. The check sends no tasks, goals or stats. An update file is '
          'downloaded only if you agree.',
    ),
    _Qa(
      'Где физически лежат мои данные?',
      'На Windows — в папке %APPDATA%\\Enitor\\Enitor, на Android — в '
          'песочнице приложения. Это отдельно от файлов самой программы, '
          'поэтому обновление или перенос папки с приложением данные не '
          'трогает. Скопировать эту папку целиком — тоже рабочий способ '
          'бэкапа, но переносимее всё-таки экспорт в файл.',
      'Where is my data physically stored?',
      'On Windows, in %APPDATA%\\Enitor\\Enitor; on Android, in the app '
          'sandbox. That is separate from the program files, which is why '
          'updating the app — or moving its folder — leaves your data alone. '
          'Copying that folder is a valid backup too, though the file export '
          'is the more portable option.',
    ),
    _Qa(
      'Мои данные где-то сохраняются?',
      'Да, на этом же устройстве. Приложение само держит свежую авто-копию всех '
          'данных и поднимает её при запуске, если хранилище данных оказалось '
          'пустым. На Windows копия — файл auto_backup.json в папке «Документы»: '
          'он переживает удаление программы, а «Удалить все данные» стирает его '
          'намеренно. На Android она лежит в папке самого приложения, поэтому '
          'пропадает вместе с приложением или при очистке его данных. Для переноса '
          'между устройствами и настоящей страховки есть экспорт в файл.',
      'Is my data saved anywhere?',
      'Yes, on this device. The app keeps a fresh automatic copy of all your '
          'data and restores it at launch if the data storage turns out to be '
          'empty. On Windows the copy is a file, auto_backup.json, in your '
          'Documents folder: it survives uninstalling the program, and “Delete '
          'all data” removes it on purpose. On Android it sits in the app’s own '
          'folder, so it is deleted together with the app or when its data is '
          'cleared. For moving between devices and real safekeeping, use the '
          'file export.',
    ),
    _Qa(
      'Что будет с другими устройствами, если восстановить бэкап?',
      'Если синхронизация включена, Enitor спросит. «На всех устройствах» — '
          'везде станет как в бэкапе: его записи разойдутся по серверу и '
          'соседям по сети, а записи, которых в нём нет, удалятся и там. '
          '«Только здесь» — файл запишется только на это устройство, а более '
          'свежие записи с других устройств вернутся при следующем обмене. '
          'Без синхронизации вопроса нет — бэкап просто заменяет данные.',
      'What happens to my other devices when I restore a backup?',
      'If sync is on, Enitor asks. “On all devices” — every device goes '
          'back to the backup: its records spread to the server and network '
          'neighbours, and records it does not have are deleted there too. '
          '“Only here” — the file goes to this device only, and newer records '
          'from other devices come back at the next sync. Without sync there '
          'is no question — the backup simply replaces the data.',
    ),
    _Qa(
      'Что делает «Сбросить настройки»?',
      'Возвращает к значениям по умолчанию тему, фон, виньетку, язык, длины '
          'таймера фокуса и все настройки уведомлений — то есть приложение '
          'выглядит и напоминает так же, как при первом запуске. Задачи, цели, '
          'статистика и достижения не трогаются. Перезапуск не нужен, всё '
          'применяется сразу.',
      'What does "Reset settings" do?',
      'It returns the theme, background, vignette, language, the focus timer '
          'lengths and every notification setting to their defaults — the app '
          'looks and reminds you exactly as it did on first launch. Tasks, '
          'goals, stats and achievements are left untouched. No restart '
          'needed, it applies immediately.',
    ),
    _Qa(
      'Что делает «Удалить все данные»?',
      'Стирает всё содержимое: задачи, цели, статистику, достижения, шаблоны '
          'и повторы — и вместе с ними автоматическую резервную копию. '
          'Последнее важно: без этого приложение подняло бы копию на '
          'следующем запуске, '
          'и удаление выглядело бы не сработавшим. Поэтому восстановить будет '
          'нечем — в диалоге есть кнопка «Экспорт и удаление»: она сохраняет '
          'файл и стирает данные одним действием, причём стирает только если '
          'файл действительно сохранён. Настройки при этом тоже сбрасываются, '
          'а после удаления приложение просит перезапуск, чтобы все экраны увидели '
          'пустое хранилище. Если ты пользуешься своим сервером, удаление '
          'касается только этого устройства: данные на сервере остаются, а '
          'устройство от него отключается.',
      'What does "Delete all data" do?',
      'It erases everything: tasks, goals, stats, achievements, templates and '
          'repeats — and the automatic backup along with them. That last part '
          'matters: without it the app would restore the copy on the next '
          'launch and the deletion would look like it had failed. So there '
          'will be nothing to restore from — the dialog has an "Export and '
          'delete" button that saves a file and wipes in one go, and it only '
          'wipes if the file really was saved. Settings are reset too, and '
          'afterwards the app asks for a restart so every screen sees the '
          'empty storage. If you use your own server, the wipe affects only '
          'this device: the server keeps its data, and the device disconnects '
          'from it.',
    ),
    _Qa(
      'Зачем тогда экспорт/импорт?',
      'Для переноса между устройствами и подстраховки. Важно: на Android '
          'удаление приложения стирает и авто-копию, поэтому файл-экспорт лучше '
          'хранить снаружи (в Загрузках или облаке). Настройки → Данные.',
      "Then what's export/import for?",
      'For moving between devices and as a safety net. Important: on '
          'Android, uninstalling the app also erases the auto-backup, so '
          "it's best to keep the exported file somewhere external "
          '(Downloads or the cloud). Settings → Data.',
    ),
    _Qa(
      'Как перенести всё на новый телефон или компьютер?',
      'Два способа. Через файл: на старом устройстве Настройки → Данные → '
          '«Экспорт в файл», на новом — «Импорт из файла». Через свой сервер: '
          'подключи новое '
          'устройство с «Заменить данные этого устройства данными сервера». '
          'Ключи и настройки интеграций не переносятся ни так, ни так — их '
          'включают заново на новом устройстве.',
      'How do I move everything to a new phone or computer?',
      'Two ways. With a file: on the old device go to Settings → Data → '
          '“Export to file”, and on the new one, “Import from file”. With your '
          'own server: connect the new '
          "device with “Replace this device's data with the server's data”. "
          'Integration keys and settings move in neither case: you turn them '
          'on again on the new device.',
    ),
  ]),
  _Section('Обновления', 'Updates', Icons.cloud_download_outlined, [
    _Qa(
      'Как обновляется приложение?',
      'Автоматически проверяет обновления на GitHub при запуске (не чаще '
          'раза в сутки, чтобы не дёргать сервер попусту), либо вручную — '
          'кнопка «Проверить обновления» в разделе «О приложении». Если есть '
          'новая версия, появится диалог с номером версии и списком '
          'изменений — можно поставить сразу или отложить. Установка '
          'скачивает файл с прогрессом: на Android откроется системный '
          'установщик (нужно будет подтвердить — приложение не из Google '
          'Play), на Windows приложение само перезапустится уже в новой '
          'версии. Задачи, цели и настройки при этом не трогаются — они '
          'хранятся отдельно от файлов программы.',
      'How does the app update itself?',
      'It checks GitHub for a new release automatically on launch (at most '
          "once a day, so it doesn't hammer the server for nothing), or "
          'manually via the "Check for updates" button in About. If a new '
          'version is found, a dialog shows the version number and '
          "changelog — install right away or postpone it. Installing "
          "downloads the file with a progress bar: on Android the system "
          "installer opens (you'll need to confirm — the app isn't from "
          'Google Play), on Windows the app restarts itself automatically '
          "already on the new version. Your tasks, goals, and settings "
          "aren't touched — they're stored separately from the app's "
          'program files.',
    ),
  ]),
  _Section(
    'Горячие клавиши (компьютер)',
    'Keyboard shortcuts (desktop)',
    Icons.keyboard_outlined,
    [
      _Qa(
        'Какие есть сочетания?',
        'Ctrl+N — создать (задачу на «Сегодня», цель на «Цели»). В формах и '
            'диалогах: Enter — сохранить/подтвердить, Esc — закрыть, Tab — '
            'переход между полями. В таймере фокуса: пробел — пауза и '
            'продолжение, Esc — свернуть.',
        'What shortcuts are available?',
        'Ctrl+N — create (a task on Today, a goal on Goals). In forms and '
            'dialogs: Enter — save/confirm, Esc — close, Tab — move between '
            'fields. In the focus timer: Space — pause and resume, Esc — '
            'minimize.',
      ),
    ],
  ),
  _Section('Оформление', 'Appearance', Icons.palette_outlined, [
    _Qa(
      'Можно вместо колец показывать полосы?',
      'Да: Настройки → Оформление → «Сводка дня» — нажми на плитку '
          '«Полосы». Те же два показателя (выполнено и в срок) встанут '
          'двумя строками — компактнее, экран сразу ближе к задачам. Вид '
          'меняется и на «Задачах», и в «Целях».',
      'Can I see bars instead of rings?',
      'Yes: Settings → Appearance → “Day summary” — tap the “Bars” tile. '
          'The same two figures (done and on time) become two rows — more '
          'compact, so the tasks come up sooner. It applies on both Tasks '
          'and Goals.',
    ),
    _Qa(
      'Как пройти экскурсию по приложению заново?',
      'Настройки → «Экскурсия по приложению»: 12 коротких шагов, '
          'приложение само переключает экраны и подсвечивает нужное. Там же '
          'переключатель «Предлагать после обновлений» — если выключить, '
          'карточка «Что нового» после обновлений больше не появится.',
      'How do I take the app tour again?',
      'Settings → “App tour”: 12 short steps; the app switches screens and '
          'highlights what matters itself. Next to it is the “Offer after '
          'updates” switch — turn it off and the “What’s new” card stops '
          'appearing after updates.',
    ),
    _Qa(
      'Есть виджет на рабочий стол?',
      'На Android — да, «Сегодня»: задачи на день и кнопка новой задачи. '
          'Добавь его как любой виджет: долгое нажатие на рабочем столе → '
          'Виджеты → Enitor. День в нём сменяется в 4:00, как в приложении.',
      'Is there a home screen widget?',
      'On Android — yes, “Today”: the day’s tasks and a new-task button. '
          'Add it like any widget: long-press the home screen → Widgets → '
          'Enitor. Its day rolls over at 4:00, like the app.',
    ),
    _Qa(
      'Как сменить тему и фон?',
      'Настройки → Оформление. Тема: системная, светлая или тёмная. Фон: '
          'гладкий, «бумага» или «точки», плюс необязательная виньетка по краям.',
      'How do I change the theme and background?',
      'Settings → Appearance. Theme: system, light, or dark. Background: '
          'plain, "paper", or "dots", plus an optional vignette around the '
          'edges.',
    ),
    _Qa(
      'Как сменить язык?',
      'Настройки → Оформление → Язык: системный, русский или английский. Меняется сразу, '
          'без перезапуска приложения.',
      'How do I change the language?',
      'Settings → Appearance → Language: system, Russian, or English. It applies '
          'immediately, without restarting the app.',
    ),
  ]),
];

/// Экран «Помощь / FAQ»: раскрывающиеся вопросы по разделам + поиск.
class FaqScreen extends StatefulWidget {
  const FaqScreen({super.key});

  @override
  State<FaqScreen> createState() => _FaqScreenState();
}

class _FaqScreenState extends State<FaqScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.helpTitle)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              decoration: InputDecoration(
                hintText: l10n.searchQuestionsHint,
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                isDense: true,
                suffixIcon: q.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(() => _query = ''),
                      ),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Expanded(
            child: q.isEmpty
                ? _buildSections(context)
                : _buildResults(context, q),
          ),
        ],
      ),
    );
  }

  Widget _buildSections(BuildContext context) {
    final theme = Theme.of(context);
    final ru = Localizations.localeOf(context).languageCode == 'ru';
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        for (final section in _kFaq) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Row(
              children: [
                Icon(section.icon, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  section.label(ru).toUpperCase(),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                  ),
                ),
              ],
            ),
          ),
          _QaCard([for (final qa in section.items) _QaTile(qa: qa)]),
        ],
      ],
    );
  }

  Widget _buildResults(BuildContext context, String q) {
    final matches = <_Qa>[
      for (final section in _kFaq)
        for (final qa in section.items)
          if ([qa.q, qa.a, qa.qEn, qa.aEn]
              .any((t) => searchNorm(t).contains(searchNorm(q))))
            qa,
    ];
    if (matches.isEmpty) {
      return Center(
        child: NotebookEmptyState(
          icon: Icons.search_off_outlined,
          text: context.l10n.nothingFoundNote,
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        _QaCard([
          for (final qa in matches) _QaTile(qa: qa, initiallyExpanded: true),
        ]),
      ],
    );
  }
}

/// Вопросы раздела — в одной карточке с разделителями, как строки Настроек.
class _QaCard extends StatelessWidget {
  const _QaCard(this.tiles);
  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < tiles.length; i++) ...[
              if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
              tiles[i],
            ],
          ],
        ),
      );
}

class _QaTile extends StatelessWidget {
  const _QaTile({required this.qa, this.initiallyExpanded = false});
  final _Qa qa;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ru = Localizations.localeOf(context).languageCode == 'ru';
    return ExpansionTile(
      initiallyExpanded: initiallyExpanded,
      // Без линий сверху/снизу у раскрытого: границы задаёт карточка.
      shape: const Border(),
      collapsedShape: const Border(),
      tilePadding: const EdgeInsets.symmetric(horizontal: 16),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      title: Text(qa.question(ru), style: theme.textTheme.titleSmall),
      children: [
        Text(
          qa.answer(ru),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
            height: 1.35,
          ),
        ),
        if (qa.opensPomodoroGuide)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: TextButton.icon(
                onPressed: () => showPomodoroGuideSheet(context),
                icon: const Icon(Icons.lightbulb_outline, size: 18),
                label: Text(pomodoroGuideOpenLabel(ru)),
              ),
            ),
          ),
      ],
    );
  }
}
