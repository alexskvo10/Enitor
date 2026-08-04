import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../l10n/l10n_extensions.dart';
import '../../services/pomodoro_prefs.dart';
import '../../widgets/esc_dismissible.dart';

/// Гайд «как выбрать длину фокуса и перерыва».
///
/// Текст живёт прямо здесь двумя языками, а не в `.arb` — так же, как FAQ:
/// это связный длинный текст, который читают целиком, и разрезать его на три
/// десятка ключей значило бы потерять и связность, и возможность править его
/// как текст. Короткие подписи интерфейса (строка в настройках) остаются в
/// локализации, как и всё остальное в приложении.
///
/// Открывается из двух мест: «Настройки → Таймер фокуса» и FAQ. Пресеты в нём
/// НАЖИМАЮТСЯ и сразу ставят длины — иначе гайд был бы просто стеной текста,
/// после которой надо ещё вспомнить, куда идти и что там выбрать.
Future<void> showPomodoroGuideSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    // На широком окне шторка во весь экран нечитаема: строка длиной в монитор
    // сбивает глаз на возврате к началу. 560 — привычная ширина колонки текста.
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (_) => const EscDismissible(
      autofocus: true,
      child: _PomodoroGuideSheet(),
    ),
  );
}

/// Подпись кнопки, открывающей гайд (нужна и FAQ — он живёт вне локализации).
String pomodoroGuideOpenLabel(bool ru) =>
    ru ? 'Открыть гайд по длинам' : 'Open the length guide';

class _PomodoroGuideSheet extends ConsumerWidget {
  const _PomodoroGuideSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final ru = Localizations.localeOf(context).languageCode == 'ru';
    final g = ru ? _ru : _en;
    final prefs = ref.watch(pomodoroPrefsProvider);
    final isDark = theme.brightness == Brightness.dark;
    // Тёплый акцент в тёмной теме высветляем — как в баннере таймера: обычная
    // «глина» на угольном фоне теряет контраст.
    final clay = isDark ? AppColors.claySoft : AppColors.clay;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: theme.colorScheme.primary.withValues(alpha: 0.14),
                ),
                child: Icon(
                  Icons.lightbulb_outline,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  g.title,
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Flexible + прокрутка: шторка забирает ровно столько высоты,
          // сколько есть, и не вылезает за экран на низких телефонах.
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _para(theme, g.intro1),
                  _para(theme, g.intro2),

                  _sectionTitle(theme, g.startTitle),
                  _para(theme, g.startNote),
                  for (final p in g.presets) ...[
                    _presetRow(
                      context,
                      ref,
                      preset: p,
                      isCurrent: prefs.focusMinutes == p.focus &&
                          prefs.breakMinutes == p.rest,
                      applyLabel: g.applyLabel,
                      currentLabel: g.currentLabel,
                    ),
                    const SizedBox(height: 8),
                  ],
                  const SizedBox(height: 2),
                  _para(theme, g.startWhy),

                  _sectionTitle(theme, g.signalTitle),
                  _para(theme, g.signalIntro),
                  _signalRow(theme, clay, g.signalTooLong),
                  _signalRow(theme, theme.colorScheme.primary, g.signalTooShort),
                  _signalRow(theme, AppColors.success, g.signalRight),
                  const SizedBox(height: 10),
                  _para(theme, g.lastMinutes),

                  _sectionTitle(theme, g.breakTitle),
                  for (final p in g.breakParas) _para(theme, p),

                  _sectionTitle(theme, g.cyclesTitle),
                  _para(theme, g.cycles),

                  _sectionTitle(theme, g.interruptTitle),
                  _para(theme, g.interrupt),

                  _sectionTitle(theme, g.mistakesTitle),
                  for (var i = 0; i < g.mistakes.length; i++)
                    _numbered(theme, clay, i + 1, g.mistakes[i]),

                  _sectionTitle(theme, g.notWorkingTitle),
                  _para(theme, g.notWorking),

                  _sectionTitle(theme, g.appTitle),
                  for (final p in g.appParas) _para(theme, p),

                  const SizedBox(height: 8),
                  _shortCard(theme, g),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l10n.close),
            ),
          ),
        ],
      ),
    );
  }

  // ── Кирпичики ────────────────────────────────────────────────────────────

  static Widget _para(ThemeData theme, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(
          text,
          style: theme.textTheme.bodyMedium?.copyWith(
            height: 1.45,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.85),
          ),
        ),
      );

  /// Заголовок раздела — тот же приём, что в настройках: мелкие капители
  /// акцентным цветом. Гайд читают вперемешку со скроллом, и такие метки
  /// работают как оглавление на полях.
  static Widget _sectionTitle(ThemeData theme, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(0, 10, 0, 8),
        child: Text(
          text.toUpperCase(),
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.primary,
            letterSpacing: 0.8,
            fontWeight: FontWeight.w700,
          ),
        ),
      );

  /// Строка стартовой точки: слева цифры, справа — для чего это. Вся строка
  /// нажимается и ставит обе длины сразу.
  static Widget _presetRow(
    BuildContext context,
    WidgetRef ref, {
    required _Preset preset,
    required bool isCurrent,
    required String applyLabel,
    required String currentLabel,
  }) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    return Material(
      color: isCurrent
          ? accent.withValues(alpha: 0.10)
          : theme.colorScheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isCurrent
              ? accent.withValues(alpha: 0.45)
              : theme.colorScheme.onSurface.withValues(alpha: 0.10),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: isCurrent
            ? null
            : () async {
                final ctrl = ref.read(pomodoroPrefsProvider);
                await ctrl.setFocusMinutes(preset.focus);
                await ctrl.setBreakMinutes(preset.rest);
              },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Row(
            children: [
              // Цифры фиксированной ширины: строки читаются столбиком, и
              // «45 / 10» не пляшет по горизонтали от длины подписи рядом.
              SizedBox(
                width: 62,
                child: Text(
                  '${preset.focus} / ${preset.rest}',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  preset.label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    height: 1.35,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (isCurrent)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle, size: 16, color: accent),
                    const SizedBox(width: 4),
                    Text(
                      currentLabel,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: accent,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                )
              else
                Text(
                  applyLabel,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Реплика-ощущение + вывод под ней, с цветной точкой слева.
  static Widget _signalRow(ThemeData theme, Color dot, _Signal signal) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  signal.feeling,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontStyle: FontStyle.italic,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  signal.verdict,
                  style: theme.textTheme.bodySmall?.copyWith(
                    height: 1.35,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static Widget _numbered(ThemeData theme, Color accent, int n, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 22,
            child: Text(
              '$n.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: accent,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(
                height: 1.45,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.85),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// «Коротко» — карточка на выходе: тот, кто пролистал текст, всё равно
  /// уносит четыре пункта.
  static Widget _shortCard(ThemeData theme, _Guide g) {
    final accent = theme.colorScheme.primary;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            g.shortTitle.toUpperCase(),
            style: theme.textTheme.labelMedium?.copyWith(
              color: accent,
              letterSpacing: 0.8,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          for (final item in g.short)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 7),
                    child: Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        color: accent,
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      item,
                      style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Текст гайда ─────────────────────────────────────────────────────────────

class _Preset {
  const _Preset(this.focus, this.rest, this.label);
  final int focus;
  final int rest;
  final String label;
}

class _Signal {
  const _Signal(this.feeling, this.verdict);
  final String feeling;
  final String verdict;
}

class _Guide {
  const _Guide({
    required this.title,
    required this.intro1,
    required this.intro2,
    required this.startTitle,
    required this.startNote,
    required this.presets,
    required this.startWhy,
    required this.applyLabel,
    required this.currentLabel,
    required this.signalTitle,
    required this.signalIntro,
    required this.signalTooLong,
    required this.signalTooShort,
    required this.signalRight,
    required this.lastMinutes,
    required this.breakTitle,
    required this.breakParas,
    required this.cyclesTitle,
    required this.cycles,
    required this.interruptTitle,
    required this.interrupt,
    required this.mistakesTitle,
    required this.mistakes,
    required this.notWorkingTitle,
    required this.notWorking,
    required this.appTitle,
    required this.appParas,
    required this.shortTitle,
    required this.short,
  });

  final String title;
  final String intro1;
  final String intro2;
  final String startTitle;
  final String startNote;
  final List<_Preset> presets;
  final String startWhy;
  final String applyLabel;
  final String currentLabel;
  final String signalTitle;
  final String signalIntro;
  final _Signal signalTooLong;
  final _Signal signalTooShort;
  final _Signal signalRight;
  final String lastMinutes;
  final String breakTitle;
  final List<String> breakParas;
  final String cyclesTitle;
  final String cycles;
  final String interruptTitle;
  final String interrupt;
  final String mistakesTitle;
  final List<String> mistakes;
  final String notWorkingTitle;
  final String notWorking;
  final String appTitle;
  final List<String> appParas;
  final String shortTitle;
  final List<String> short;
}

const _ru = _Guide(
  title: 'Как выбрать длину',
  intro1: '25 минут — не результат исследования. Это число из книги Франческо '
      'Чирилло: в конце 80-х он засекал учёбу кухонным таймером в форме '
      'помидора. Цифра прижилась, потому что круглая и удобная.',
  intro2: 'Твоя длина другая, и зависит она от двух вещей: сколько времени ты '
      'входишь в задачу и через сколько начинаешь выпадать. Отрезок должен '
      'помещаться между этими моментами. Найти его можно за неделю — гадать '
      'не нужно.',
  startTitle: 'С чего начать',
  startNote: 'Стартовая точка зависит от того, чем ты занят, а не от чужого '
      'совета. Нажми на строку — длины поставятся сразу.',
  presets: [
    _Preset(45, 10, 'Код, текст, дизайн, сложная учёба — всё, где нужен '
        'разгон'),
    _Preset(20, 5, 'Почта, рутина, мелкие дела, повторение'),
    _Preset(25, 5, 'Всего понемногу или пока не знаешь'),
    _Preset(15, 5, 'Тяжело начать: устал, тревожно, задача противная'),
  ],
  startWhy: 'У работы с разгоном первые 10–15 минут уходят на то, чтобы '
      'вспомнить, где ты остановился, — при 25-минутном отрезке звонок '
      'застаёт тебя ровно тогда, когда ты наконец вошёл. У рутины разгона нет '
      'вообще: там длинный отрезок только утомляет.',
  applyLabel: 'Поставить',
  currentLabel: 'Сейчас',
  signalTitle: 'Главный сигнал — что ты чувствуешь на звонке',
  signalIntro: 'Самый честный индикатор, и он есть уже после первого дня. '
      'Поймай первое ощущение в ту секунду, когда таймер закончился.',
  signalTooLong: _Signal('«Ну наконец-то»', 'Ты дотерпел. Убавь 10 минут.'),
  signalTooShort:
      _Signal('«Да я только въехал»', 'Тебя перебили. Прибавь 10 минут.'),
  signalRight: _Signal('«О, уже? Ладно»', 'Это твоя длина. Не трогай.'),
  lastMinutes: 'Второй сигнал, менее заметный: чем ты занят в последние пять '
      'минут отрезка. Если уже переставляешь окна и заглядываешь в телефон — '
      'эти минуты просто утекают. Отрежь их.',
  breakTitle: 'Про перерыв',
  breakParas: [
    'Обычно берут пятую часть от фокуса: 25/5, 45/10, 50/10. Это разумная '
        'отправная точка, но важнее не длина, а два правила.',
    'Перерыв должен быть отдыхом другого типа. Встать, налить воды, '
        'посмотреть в окно, размяться. Лента и ролики — не отдых: голова '
        'остаётся в том же режиме, добавляется ещё одно переключение, и выйти '
        'из них по звонку нельзя — у них нет естественного конца.',
    'Больше 15 минут — уже не перерыв. За этой границей ты не возвращаешься к '
        'работе, а начинаешь её заново, со всем разгоном с нуля. Если тянет '
        'на полчаса — это не перерыв, а признак, что на сегодня хватит.',
  ],
  cyclesTitle: 'Сколько отрезков подряд',
  cycles: 'Три-четыре, потом большой перерыв — 20–30 минут. Enitor его не '
      'считает: просто не запускай следующий фокус сразу. Признак, что пора: '
      'два отрезка подряд прошли заметно хуже предыдущих. Гнать дальше '
      'бессмысленно — следующий будет ещё хуже.',
  interruptTitle: 'Когда звонок застал на середине мысли',
  interrupt: 'Дописать фразу или строчку — нормально, полминуты ничего не '
      'портят. Работать весь перерыв — нет: тогда таймер превращается в '
      'фоновый шум, а через два часа выясняется, что перерыва не было ни '
      'одного. А если мысль слишком жалко бросать, это как раз сигнал, что '
      'отрезок пора удлинить.',
  mistakesTitle: 'Три ошибки',
  mistakes: [
    'Гнаться за длинными отрезками. Длинный фокус кажется признаком силы '
        'воли, но он дороже стоит: сорваться на 40-й минуте пятидесятиминутного '
        'обиднее, чем на 20-й минуте двадцатипятиминутного. Отрезок, который '
        'ты дотягиваешь до конца в девяти случаях из десяти, лучше того, '
        'которым можно похвастаться.',
    'Ставить длину «как у нормальных людей». Утром и вечером твоя длина '
        'разная, на выспавшуюся голову и на больную — тоже. Менять настройку '
        'нормально, это не «сбился с системы».',
    'Ждать одну цифру на все случаи. Настройка одна, поэтому поставь ту, что '
        'подходит для дела, которым ты занят чаще всего, а под нетипичное '
        'меняй руками: перед долгим погружением — 50, перед разбором почты — '
        '20.',
  ],
  notWorkingTitle: 'Если не помогает вообще',
  notWorking: 'Бывает, что ни одна длина не заходит: отрезок идёт, а работа — '
      'нет. Тогда дело не в таймере. Чаще всего задача слишком крупная, и в '
      'ней не видно первого шага: раздели её на подзадачи и запусти фокус на '
      'первой. Таймер помогает удержать внимание, но не решает, что делать.',
  appTitle: 'Что важно знать про сам таймер',
  appParas: [
    'Остановить отрезок посреди — не значит потерять его. В фактическое время '
        'задачи попадут все полные отработанные минуты, даже если ты нажал '
        'стоп на двенадцатой. Пришли и надо идти — жми стоп спокойно.',
    'Новая длина применяется со следующего отрезка. Идущий таймер остаётся с '
        'той, с которой начался: иначе он бы прыгнул или мгновенно '
        '«закончился», а в факт задачи уехало бы не то время, которое ты '
        'отработал.',
  ],
  shortTitle: 'Коротко',
  short: [
    'Начни с 45/10 для работы с разгоном, 20/5 для рутины, 25/5 если не '
        'знаешь.',
    'Неделю лови первое ощущение на звонке: облегчение — короче, досада — '
        'длиннее.',
    'Перерыв — примерно пятая часть фокуса, не больше 15 минут и не в телефон.',
    'Дотягиваемый отрезок лучше героического.',
  ],
);

const _en = _Guide(
  title: 'Choosing your lengths',
  intro1: "25 minutes isn't a research finding. It comes from Francesco "
      "Cirillo's book: in the late 1980s he timed his studying with a "
      'tomato-shaped kitchen timer. The number stuck because it is round and '
      'convenient.',
  intro2: 'Yours is a different number, and it depends on two things: how long '
      'you take to get into a task, and how long before you start drifting '
      'out. Your stretch has to fit between those two moments. A week of '
      'paying attention is enough to find it — no guessing required.',
  startTitle: 'Where to start',
  startNote: 'Pick your starting point by what you actually do, not by '
      'somebody else’s advice. Tap a row and both lengths are set.',
  presets: [
    _Preset(45, 10, 'Code, writing, design, hard study — anything with a '
        'warm-up'),
    _Preset(20, 5, 'Email, chores, small errands, revision'),
    _Preset(25, 5, "A bit of everything, or you don't know yet"),
    _Preset(15, 5, 'Hard to start: tired, anxious, or the task is unpleasant'),
  ],
  startWhy: 'Work with a warm-up spends its first 10–15 minutes just '
      'remembering where you left off — with a 25-minute stretch the bell '
      'catches you exactly when you finally got in. Routine has no warm-up at '
      'all, and a long stretch there only wears you down.',
  applyLabel: 'Use these',
  currentLabel: 'Current',
  signalTitle: 'The main signal is how you feel at the bell',
  signalIntro: 'It is the most honest indicator you have, and you have it '
      'after the first day. Catch your very first reaction the second the '
      'timer ends.',
  signalTooLong:
      _Signal('“Finally.”', 'You were holding out. Take 10 minutes off.'),
  signalTooShort:
      _Signal('“But I’d just got going.”', 'You got cut off. Add 10 minutes.'),
  signalRight: _Signal('“Already? Fine.”', 'That is your length. Leave it.'),
  lastMinutes: 'A second, quieter signal: what you are doing in the last five '
      'minutes of a stretch. If you are already rearranging windows and '
      'glancing at your phone, those minutes are draining away. Cut them.',
  breakTitle: 'About the break',
  breakParas: [
    'The usual ratio is a fifth of the focus: 25/5, 45/10, 50/10. A sensible '
        'starting point — but two rules matter more than the number.',
    'A break has to be a different kind of rest. Stand up, get water, look out '
        'of the window, stretch. Feeds and clips are not rest: your head stays '
        'in the same mode, you pay for one more context switch, and you cannot '
        'leave them at the bell — they have no natural end.',
    'Over 15 minutes it stops being a break. Past that line you do not return '
        'to the work, you start it again, warm-up and all. If you want half an '
        'hour, that is not a break — that is a sign you are done for today.',
  ],
  cyclesTitle: 'How many in a row',
  cycles: 'Three or four, then a real break of 20–30 minutes. Enitor does not '
      'count those: simply do not start the next focus right away. The tell is '
      'two stretches in a row that went noticeably worse than the ones before '
      '— pushing on from there is pointless, the next will be worse still.',
  interruptTitle: 'When the bell catches you mid-thought',
  interrupt: 'Finishing the sentence or the line is fine — half a minute costs '
      'nothing. Working through the whole break is not: the timer turns into '
      'background noise, and two hours later it turns out you never took one. '
      'And if the thought feels too good to drop, that is precisely the sign '
      'your stretch should be longer.',
  mistakesTitle: 'Three mistakes',
  mistakes: [
    'Chasing long stretches. A long focus feels like willpower, but it costs '
        'more: giving up at minute 40 of fifty stings more than at minute 20 '
        'of twenty-five. A stretch you finish nine times out of ten beats one '
        'you can boast about.',
    'Setting the length “the way normal people do”. Your length differs '
        'morning and evening, well-slept and not. Changing the setting is '
        'normal, not falling off the wagon.',
    'Expecting one number to cover everything. There is a single setting, so '
        'set it for whatever you do most and change it by hand for the rest: '
        '50 before a deep session, 20 before clearing email.',
  ],
  notWorkingTitle: 'If nothing helps at all',
  notWorking: 'Sometimes no length works: the stretch runs and the work still '
      'does not. Then it is not about the timer. Usually the task is too big '
      'to see a first move in — split it into subtasks and start the timer on '
      'the first one. A timer helps you hold attention; it does not decide '
      'what to do.',
  appTitle: 'Worth knowing about the timer itself',
  appParas: [
    "Stopping a stretch early doesn't throw it away. Every full minute you "
        "worked goes into the task's actual time, even if you hit stop at "
        'minute twelve. Someone needs you — hit stop without regret.',
    'A new length takes effect from the next stretch. The running timer keeps '
        'the one it started with: otherwise it would jump, or “finish” '
        'instantly, and the time logged would not be the time you worked.',
  ],
  shortTitle: 'In short',
  short: [
    'Start at 45/10 for work with a warm-up, 20/5 for routine, 25/5 if unsure.',
    'For a week, catch your first reaction at the bell: relief means shorter, '
        'annoyance means longer.',
    'Break: about a fifth of the focus, never over 15 minutes, and not in your '
        'phone.',
    'A stretch you finish beats a heroic one.',
  ],
);
