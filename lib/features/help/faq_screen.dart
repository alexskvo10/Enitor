import 'package:flutter/material.dart';

import '../../l10n/l10n_extensions.dart';

/// Один вопрос-ответ.
class _Qa {
  const _Qa(this.q, this.a, this.qEn, this.aEn);
  final String q;
  final String a;
  final String qEn;
  final String aEn;

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
      'Таймер 25 минут фокуса / 5 минут перерыва. Всё время фокуса копится в '
          'фактическое время задачи. Если отметишь задачу выполненной, пока '
          'таймер идёт, — он остановится и запишет накопленное.',
      'How does Pomodoro work?',
      'A timer of 25 minutes of focus / 5 minutes of break. All focus time '
          "accumulates into the task's actual time. If you mark the task "
          "done while the timer is running, it stops and records what's "
          'been accumulated.',
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
      'Как сделать повторяющуюся задачу?',
      'В форме задачи включи «Повторяется» и выбери режим: ежедневно, по дням '
          'недели, по числам месяца или через интервал. Экземпляры создаются '
          'сами, когда открываешь соответствующий день.',
      'How do I make a recurring task?',
      'In the task form, turn on “Repeats” and choose a mode: daily, by '
          'weekday, by day of the month, or every N days. Occurrences are '
          'created automatically as you open the corresponding day.',
    ),
  ]),
  _Section(
      'Перенос и «день с 4:00»', 'Carryover and the "4:00 day"', Icons.schedule, [
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
          'применяй в любой день одним нажатием — задачи добавятся с нуля.',
      'What are day templates for?',
      'Save a typical set of tasks (e.g. a "workday") as a template and '
          'apply it to any day with one tap — the tasks get added fresh.',
    ),
  ]),
  _Section('Цели', 'Goals', Icons.flag_outlined, [
    _Qa(
      'Какие бывают цели?',
      'Обычная (галочка), счётчик-квота (прогресс к числу за период) и '
          'чек-лист (набор подзадач). У цели есть период: неделя, месяц, сезон '
          'или год, и необязательный дедлайн.',
      'What types of goals are there?',
      'A plain goal (checkbox), a counter/quota (progress toward a number '
          'over a period), and a checklist (a set of subtasks). Every goal '
          'has a period — week, month, season, or year — and an optional '
          'deadline.',
    ),
    _Qa(
      'Как привязать задачи к цели?',
      'Цель-квоту можно связать с задачами: выполнение таких задач '
          'автоматически прибавляется к прогрессу цели. Удобно для целей вроде '
          '«10 тренировок в месяц».',
      'How do I link tasks to a goal?',
      'A quota goal can be linked to tasks: completing those tasks '
          "automatically adds to the goal's progress. Handy for goals "
          'like "10 workouts this month".',
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
          'the last day of the period. This feeds the “Deadline adherence” '
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
  _Section('Профиль и достижения', 'Profile and achievements',
      Icons.emoji_events_outlined, [
    _Qa(
      'Что такое серия (streak)?',
      'Число дней подряд, закрытых на 100% (все задачи дня выполнены). Дни без '
          'задач нейтральны — серию не рвут и не продлевают. Сегодняшний ещё не '
          'закрытый день серию тоже не обрывает. В Профиле видно текущую серию '
          'и рекорд.',
      "What's a streak?",
      'The number of consecutive days closed at 100% (all of the day’s tasks '
          'done). Days with no tasks are neutral — they neither break nor '
          "extend the streak. Today, if it isn't closed yet, doesn't break it "
          'either. The Profile shows your current streak and your record.',
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
          'идеальные дни, достигнутые цели и средняя оценка дней. Можно листать '
          'недели назад.',
      'What is the "Week summary"?',
      'A summary of a finished week (Profile → Week summary): productivity '
          'with the change vs last week, completed tasks, the best day, perfect '
          'days, achieved goals, and the average day rating. You can page back '
          'through weeks.',
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
          'о целях. Плюс утренний план, вечерняя оценка дня, общие «не забудь '
          'про задачи» и напоминание о переносе на границе дня. Всё включается '
          'по отдельности в Настройках.',
      'What kinds of reminders are there?',
      'For tasks: before a task starts and before it ends (by a chosen '
          'number of minutes), "needs attention" (nearing its end), and '
          '"overdue". For goals: "needs attention" near the deadline/period '
          'end, "overdue", and general goal nudges. Plus a morning plan, an '
          'evening day review, general "don\'t forget your tasks" nudges, and '
          'a carry-over reminder at the day rollover. Each is toggled '
          'separately in Settings.',
    ),
    _Qa(
      'Что такое тихие часы?',
      'Окно (по умолчанию 23:00–08:00), когда умные и общие напоминания '
          'молчат. Напоминания к началу конкретных задач работают всегда — ты '
          'сам назначил это время.',
      'What are quiet hours?',
      'A window (23:00–08:00 by default) during which smart and general '
          'reminders stay silent. Reminders for the start of a specific '
          'task always fire — you set that time yourself.',
    ),
    _Qa(
      'Почему уведомления не приходят?',
      'Чаще всего телефон усыпляет приложение в фоне (особенно Infinix/'
          'Transsion, Xiaomi, Huawei). Разреши работу в фоне по подсказке в '
          'приложении или вручную: Настройки телефона → Батарея → отключить '
          'оптимизацию для Enitor и включить автозапуск.',
      "Why aren't notifications arriving?",
      'Most often the phone puts the app to sleep in the background '
          '(especially on Infinix/Transsion, Xiaomi, Huawei). Allow '
          'background activity via the in-app hint, or manually: Phone '
          'Settings → Battery → disable optimization for Enitor and enable '
          'autostart.',
    ),
  ]),
  _Section('Резервные копии', 'Backups', Icons.backup_outlined, [
    _Qa(
      'Мои данные где-то сохраняются?',
      'Да. Приложение само хранит свежую резервную копию всех данных и '
          'восстановит её при чистой переустановке или после «очистить данные».',
      'Is my data saved anywhere?',
      'Yes. The app automatically keeps a fresh backup of all your data '
          'and restores it on a clean reinstall or after "clear data".',
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
  ]),
  _Section('Горячие клавиши (компьютер)', 'Keyboard shortcuts (desktop)',
      Icons.keyboard_outlined, [
    _Qa(
      'Какие есть сочетания?',
      'Ctrl+N — создать (задачу на «Сегодня», цель на «Цели»). В формах и '
          'диалогах: Enter — сохранить/подтвердить, Esc — закрыть, Tab — '
          'переход между полями.',
      'What shortcuts are available?',
      'Ctrl+N — create (a task on Today, a goal on Goals). In forms and '
          'dialogs: Enter — save/confirm, Esc — close, Tab — move between '
          'fields.',
    ),
  ]),
  _Section('Оформление', 'Appearance', Icons.palette_outlined, [
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
      'Настройки → Язык: системный, русский или английский. Меняется сразу, '
          'без перезапуска приложения.',
      'How do I change the language?',
      'Settings → Language: system, Russian, or English. It applies '
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
            child: q.isEmpty ? _buildSections(context) : _buildResults(context, q),
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
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
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
          for (final qa in section.items) _QaTile(qa: qa),
        ],
      ],
    );
  }

  Widget _buildResults(BuildContext context, String q) {
    final matches = <_Qa>[
      for (final section in _kFaq)
        for (final qa in section.items)
          if (qa.q.toLowerCase().contains(q) ||
              qa.a.toLowerCase().contains(q) ||
              qa.qEn.toLowerCase().contains(q) ||
              qa.aEn.toLowerCase().contains(q))
            qa,
    ];
    if (matches.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            context.l10n.nothingFoundNote,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.5),
                ),
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        for (final qa in matches) _QaTile(qa: qa, initiallyExpanded: true),
      ],
    );
  }
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
      ],
    );
  }
}
