import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../widgets/error_view.dart';
import '../../widgets/pill_toggle.dart';
import '../../widgets/seg_chip.dart';
import '../../core/utils/date_utils.dart';
import '../../data/models/goal.dart';
import '../../data/repositories/goal_repository.dart';
import '../../data/repositories/profile_repository.dart';
import '../../data/repositories/stats_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/l10n_extensions.dart';
import 'estimate_accuracy.dart';
import 'goal_deadline_accuracy.dart';
import 'goal_productivity_chart.dart';
import 'goal_tag_stats_screen.dart';
import 'productivity_chart.dart';
import 'tag_stats_screen.dart';

/// Экран статистики: переключатель Задачи/Цели в шапке (тот же паттерн —
/// TabController + PillToggle в AppBar.bottom + TabBarView, — что у переклю-
/// чателя периода на экране «Цели»), каждая вкладка — сводка за период +
/// график продуктивности со своими переключателями группировки/таймфрейма.
class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this)
      ..addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.navStats),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: PillToggle<int>(
              selected: _tabController.index,
              segments: [
                (0, l10n.navToday),
                (1, l10n.navGoals),
              ],
              // animateTo меняет вкладку; слушатель контроллера (addListener в
              // initState) делает setState → пилюля едет и при свайпе страниц.
              onChanged: (i) => _tabController.animateTo(i),
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          _TasksStatsTab(),
          _GoalsStatsTab(),
        ],
      ),
    );
  }
}

/// Вкладка «Задачи» — сводка/график/тегов/точность оценок (прежнее
/// содержимое единственного экрана Статистики, вынесено под вкладку).
///
/// Верхняя строка чипов — группировка (периодичность точек на графике).
/// Нижняя строка — таймфрейм (видимый диапазон). Зависит от группировки:
/// нельзя выбрать «5 лет» при «День» — слишком много точек.
class _TasksStatsTab extends ConsumerStatefulWidget {
  const _TasksStatsTab();

  @override
  ConsumerState<_TasksStatsTab> createState() => _TasksStatsTabState();
}

class _TasksStatsTabState extends ConsumerState<_TasksStatsTab> {
  ChartGrouping _grouping = ChartGrouping.daily;
  _TfKind _timeframe = _TfKind.month;

  /// Меняет группировку и сбрасывает таймфрейм на первый доступный,
  /// если текущий не входит в список для новой группировки.
  void _setGrouping(ChartGrouping g) {
    final available = _timeframesFor(g);
    final tf = available.contains(_timeframe) ? _timeframe : available.first;
    setState(() {
      _grouping = g;
      _timeframe = tf;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    // Профиль нужен для таймфрейма «Всё время» — startedAt.
    final profile = ref.watch(profileProvider).value;
    final (from, to) = _timeframe.resolve(profile?.startedAt);
    final range = StatsRange(from, to);
    final summaryAsync = ref.watch(summaryProvider(range));
    // Точки нужны для блока «Лучший …» — тот же кэш что у графика, доп. запроса нет.
    final query = PointsQuery(from: from, to: to, grouping: _grouping);
    final pointsAsync = ref.watch(productivityPointsProvider(query));
    final available = _timeframesFor(_grouping);

    // Прокручиваемое тело: график имеет фиксированную высоту (не сжимается
    // под экран), остальное прокручивается.
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      children: [
        summaryAsync.when(
          loading: () => const _SummarySkeleton(),
          error: (e, _) => ErrorView(
            compact: true,
            onRetry: () => ref.invalidate(summaryProvider(range)),
          ),
          data: (s) => _SummaryBlock(
            summary: s,
            points: pointsAsync.valueOrNull ?? const [],
            grouping: _grouping,
            timeframePhrase: _timeframe.forPhrase(l10n),
          ),
        ),
        const SizedBox(height: 12),
        // ── Переключатели графика в одной карточке ───────────────────────
        // Группировка (периодичность точек) + таймфрейм (видимый диапазон).
        // Чипы — пилюли без галочки: выбранный сплошной синий, остальные —
        // с тонкой рамкой.
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _chipsLabel(context, l10n.eachPointLabel),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final g in ChartGrouping.values)
                      SegChip(
                        label: _chartGroupingLabel(l10n, g),
                        selected: _grouping == g,
                        onTap: () => _setGrouping(g),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                _chipsLabel(context, l10n.showForLabel),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final tf in available)
                      SegChip(
                        label: tf.label(l10n),
                        selected: _timeframe == tf,
                        onTap: () => setState(() => _timeframe = tf),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          // Фиксированная высота графика — не сжимается под экран.
          height: 300,
          // Не Card, а Container с BoxDecoration: Material рисует обводку
          // ПОВЕРХ содержимого (перечёркивал бы тултип «полоской»), а
          // BoxDecoration — как фон, ПОД содержимым. Поэтому всплывающее
          // окошко графика рисуется поверх рамки и может выходить за карточку.
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
              boxShadow: AppColors.stickerShadow,
              border: Border.all(
                color: Theme.of(context).brightness == Brightness.dark
                    ? AppColors.surfaceDarkMuted
                    : AppColors.ringTrack,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 14, 14, 10),
              child: ProductivityChart(
                from: from,
                to: to,
                grouping: _grouping,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        // Переход к статистике по тегам — карточка со свечением (заметнее
        // обычной кнопки в шапке).
        _TagStatsButton(),
        // Точность оценок времени — скрыта, пока нет ≥3 пар «оценка+факт».
        const SizedBox(height: 12),
        const EstimateAccuracyCard(),
      ],
    );
  }

}

/// Мелкая подпись над рядом чипов — общая для разделов «Задачи» и «Цели».
Widget _chipsLabel(BuildContext context, String text) => Text(
      text,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color:
                Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
          ),
    );

/// Подпись гранулярности точки («Каждая точка —») — общая для обеих вкладок.
String _chartGroupingLabel(AppLocalizations l10n, ChartGrouping g) =>
    switch (g) {
      ChartGrouping.daily => l10n.groupingDay,
      ChartGrouping.weekly => l10n.goalsPeriodWeek,
      ChartGrouping.monthly => l10n.goalsPeriodMonth,
      ChartGrouping.yearly => l10n.goalsPeriodYear,
    };

/// Подпись типа периода целей («Тип периода —»).
String _goalPeriodLabel(AppLocalizations l10n, GoalPeriod g) => switch (g) {
      GoalPeriod.week => l10n.goalsPeriodWeek,
      GoalPeriod.month => l10n.goalsPeriodMonth,
      GoalPeriod.season => l10n.goalsPeriodSeason,
      GoalPeriod.year => l10n.goalsPeriodYear,
    };

/// Доступные таймфреймы («Показать за») для гранулярности точки — общий для
/// обеих вкладок (у целей «Показать за» зависит только от «Каждая точка —»,
/// как у задач).
List<_TfKind> _timeframesFor(ChartGrouping g) => switch (g) {
      ChartGrouping.daily => [
          _TfKind.week,
          _TfKind.month,
          _TfKind.months3,
          _TfKind.allTime,
        ],
      ChartGrouping.weekly => [
          _TfKind.month,
          _TfKind.months3,
          _TfKind.months6,
          _TfKind.year,
          _TfKind.allTime,
        ],
      ChartGrouping.monthly => [
          _TfKind.months6,
          _TfKind.year,
          _TfKind.months18,
          _TfKind.years2,
          _TfKind.allTime,
        ],
      ChartGrouping.yearly => [
          _TfKind.years3,
          _TfKind.years5,
          _TfKind.allTime,
        ],
    };

/// Карточка-кнопка перехода к статистике по тегам — обычная карточка.
class _TagStatsButton extends StatelessWidget {
  const _TagStatsButton();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const TagStatsScreen()),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(Icons.tag, color: theme.colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  context.l10n.tagStatsButtonLabel,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              Icon(Icons.chevron_right,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.4)),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Таймфреймы ───────────────────────────────────────────────────────────────

enum _TfKind {
  // Подписи — в винительном падеже (идут после «Показать за …»).
  week,
  month,
  months3,
  months6,
  year,
  months18,
  years2,
  years3,
  years5,
  allTime;

  String label(AppLocalizations l10n) => switch (this) {
        _TfKind.week => l10n.tfWeek,
        _TfKind.month => l10n.tfMonth,
        _TfKind.months3 => l10n.tfMonths3,
        _TfKind.months6 => l10n.tfMonths6,
        _TfKind.year => l10n.tfYear,
        _TfKind.months18 => l10n.tfMonths18,
        _TfKind.years2 => l10n.tfYears2,
        _TfKind.years3 => l10n.tfYears3,
        _TfKind.years5 => l10n.tfYears5,
        _TfKind.allTime => l10n.tfAllTime,
      };

  /// Фраза для подписи: «выполнено за …»
  String forPhrase(AppLocalizations l10n) => switch (this) {
        _TfKind.week => l10n.tfPhraseWeek,
        _TfKind.month => l10n.tfPhraseMonth,
        _TfKind.months3 => l10n.tfPhraseMonths3,
        _TfKind.months6 => l10n.tfPhraseMonths6,
        _TfKind.year => l10n.tfPhraseYear,
        _TfKind.months18 => l10n.tfPhraseMonths18,
        _TfKind.years2 => l10n.tfPhraseYears2,
        _TfKind.years3 => l10n.tfPhraseYears3,
        _TfKind.years5 => l10n.tfPhraseYears5,
        _TfKind.allTime => l10n.tfPhraseAllTime,
      };

  /// Возвращает (from, to), округлённые до дня. Без округления каждый build
  /// давал бы новый DateTime.now() с разными миллисекундами → family-ключ
  /// `StatsRange` менял бы equality → подписка пересоздавалась бы каждый
  /// кадр → loading навсегда.
  (DateTime, DateTime) resolve(DateTime? startedAt) {
    final d = today();
    return switch (this) {
      _TfKind.week => (d.subtract(const Duration(days: 7)), d),
      _TfKind.month => (subtractMonths(d, 1), d),
      _TfKind.months3 => (subtractMonths(d, 3), d),
      _TfKind.months6 => (subtractMonths(d, 6), d),
      _TfKind.year => (subtractMonths(d, 12), d),
      _TfKind.months18 => (subtractMonths(d, 18), d),
      _TfKind.years2 => (subtractMonths(d, 24), d),
      _TfKind.years3 => (subtractMonths(d, 36), d),
      _TfKind.years5 => (subtractMonths(d, 60), d),
      _TfKind.allTime => (startedAt == null ? d : dateOnly(startedAt), d),
    };
  }
}

// ─── Сводка ──────────────────────────────────────────────────────────────────

class _SummaryBlock extends StatelessWidget {
  const _SummaryBlock({
    required this.summary,
    required this.points,
    required this.grouping,
    required this.timeframePhrase,
  });
  final StatsSummary summary;
  final List<ProductivityPoint> points;
  final ChartGrouping grouping;
  final String timeframePhrase;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final avg = summary.avgProductivity;

    final avgCard = _SummaryCard(
      label: l10n.goalStatAverage,
      value: avg == null ? '—' : '${(avg * 100).round()}%',
      sub: summary.daysWithData == 0
          ? l10n.noDataNote
          : l10n.forNDaysNote(summary.daysWithData),
      color: theme.colorScheme.primary,
    );
    final tasksCard = _SummaryCard(
      label: l10n.tasksSummaryLabel,
      value: '${summary.completedTasks}/${summary.totalTasks}',
      sub: l10n.completedPhrase(timeframePhrase),
      color: theme.colorScheme.tertiary,
    );
    final bestCard = _BestBucketCard(points: points, grouping: grouping);

    // Адаптивно: на широком экране (десктоп) все три карточки в один ряд;
    // на узком (телефон) — две метрики в ряд, «Лучший…» на всю ширину снизу
    // (в три колонки на телефоне «Лучший…» не помещается из-за даты+описания).
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 600) {
          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: avgCard),
                const SizedBox(width: 8),
                Expanded(child: tasksCard),
                const SizedBox(width: 8),
                Expanded(child: bestCard),
              ],
            ),
          );
        }
        return Column(
          children: [
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: avgCard),
                  const SizedBox(width: 8),
                  Expanded(child: tasksCard),
                ],
              ),
            ),
            const SizedBox(height: 8),
            bestCard,
          ],
        );
      },
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.label,
    required this.value,
    required this.sub,
    required this.color,
  });

  final String label;
  final String value;
  final String sub;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: theme.textTheme.titleLarge?.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (sub.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                sub,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Карточка «Лучший день / неделя / месяц / год».
/// Зависит от группировки: находит бакет с максимальным составным скором
/// P × (0.7 + 0.3 × T) среди уже агрегированных [ProductivityPoint].
class _BestBucketCard extends StatelessWidget {
  const _BestBucketCard({required this.points, required this.grouping});

  final List<ProductivityPoint> points;
  final ChartGrouping grouping;

  // ── Заголовок карточки ──────────────────────────────────────────────────────

  String _label(AppLocalizations l10n) => switch (grouping) {
        ChartGrouping.daily => l10n.bestDayLabel,
        ChartGrouping.weekly => l10n.bestWeekLabel,
        ChartGrouping.monthly => l10n.bestMonthLabel,
        ChartGrouping.yearly => l10n.bestYearLabel,
      };

  // ── Составной скор (тот же алгоритм что в StatsRepository) ─────────────────

  static double _score(ProductivityPoint p) {
    final prod = p.value ?? 0.0;
    final t = p.onTimeValue ?? 1.0;
    // Вес за объём: бакет с парой задач не обгонит насыщенный бакет.
    return prod * (0.7 + 0.3 * t) * volumeWeight(p.totalTasks);
  }

  /// Бакет с наибольшим скором; тайбрейк — более поздняя дата.
  ProductivityPoint? get _best {
    final candidates = points.where((p) => p.value != null).toList();
    if (candidates.isEmpty) return null;
    return candidates.reduce((a, b) {
      final sa = _score(a);
      final sb = _score(b);
      if ((sa - sb).abs() < 1e-9) {
        return a.bucketStart.isAfter(b.bucketStart) ? a : b;
      }
      return sa > sb ? a : b;
    });
  }

  // ── Имена месяцев (intl даёт нестабильные падежи в ru-локали) ──────────────

  /// Именительный падеж — для standalone месяца: «май 2026».
  static const _monthNomRu = [
    '',
    'январь',
    'февраль',
    'март',
    'апрель',
    'май',
    'июнь',
    'июль',
    'август',
    'сентябрь',
    'октябрь',
    'ноябрь',
    'декабрь',
  ];

  /// Родительный падеж — после числа: «24 мая», «1 января».
  static const _monthGenRu = [
    '',
    'января',
    'февраля',
    'марта',
    'апреля',
    'мая',
    'июня',
    'июля',
    'августа',
    'сентября',
    'октября',
    'ноября',
    'декабря',
  ];

  static const _monthEn = [
    '',
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  // ── Форматирование даты ─────────────────────────────────────────────────────

  String _formatDate(BuildContext context, DateTime d) {
    final l10n = context.l10n;
    final ru = Localizations.localeOf(context).languageCode == 'ru';
    final monthNom = ru ? _monthNomRu : _monthEn;
    final monthGen = ru ? _monthGenRu : _monthEn;
    switch (grouping) {
      case ChartGrouping.daily:
        final dateStr = '${d.day} ${monthGen[d.month]} ${d.year}';
        // «27 мая 2026 · сегодня»
        return dateOnly(d) == today() ? l10n.bestDateToday(dateStr) : dateStr;

      case ChartGrouping.weekly:
        final end = d.add(const Duration(days: 6));
        if (d.month == end.month) {
          // «24–30 мая 2026»
          return '${d.day}–${end.day} ${monthGen[d.month]} ${d.year}';
        } else {
          // «28 апреля – 4 мая 2026» (год — конечной даты, неделя может переходить год)
          return '${d.day} ${monthGen[d.month]} – '
              '${end.day} ${monthGen[end.month]} ${end.year}';
        }

      case ChartGrouping.monthly:
        // «май 2026» (именительный)
        return '${monthNom[d.month]} ${d.year}';

      case ChartGrouping.yearly:
        return '${d.year}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final subColor = theme.colorScheme.onSurface.withValues(alpha: 0.5);
    final best = _best;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _label(l10n),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              best == null ? '—' : _formatDate(context, best.bucketStart),
              style: theme.textTheme.titleLarge?.copyWith(
                color: AppColors.success,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (best != null) ...[
              const SizedBox(height: 2),
              Text.rich(
                TextSpan(
                  style: theme.textTheme.bodySmall?.copyWith(color: subColor),
                  children: [
                    TextSpan(
                      text: '${(best.value! * 100).round()}%',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    TextSpan(text: l10n.tasksWordSuffix),
                    if (best.onTimeValue != null) ...[
                      TextSpan(text: l10n.outOfWhichPrefix),
                      TextSpan(
                        text: '${(best.onTimeValue! * 100).round()}%',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      TextSpan(text: l10n.onTimeWordSuffix),
                    ],
                  ],
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SummarySkeleton extends StatelessWidget {
  const _SummarySkeleton();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 92,
      child: Row(
        children: List.generate(
          3,
          (_) => const Expanded(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Card(margin: EdgeInsets.zero, child: SizedBox.expand()),
            ),
          ),
        ),
      ),
    );
  }
}

/// Вкладка «Цели» — та же структура, что у задач (сводка + переключатели +
/// график + «по тегам»), но:
/// • переключатель группировки — не День/Неделя/Месяц/Год, а тип периода
///   цели (Неделя/Месяц/Сезон/Год), в ТОМ ЖЕ стиле чипов (SegChip/Wrap), что
///   и у задач — стиль PillToggle зарезервирован за переключателем вкладок
///   Задачи/Цели в шапке экрана (см. _StatsScreenState);
/// • вместо «Точности оценок» — «Соблюдение дедлайнов» (на сколько в среднем
///   просрочен дедлайн, не сравнение оценки со временем).
class _GoalsStatsTab extends ConsumerStatefulWidget {
  const _GoalsStatsTab();

  @override
  ConsumerState<_GoalsStatsTab> createState() => _GoalsStatsTabState();
}

class _GoalsStatsTabState extends ConsumerState<_GoalsStatsTab> {
  /// Тип анализируемого периода (какие цели) — «Тип периода».
  /// null — «Общий» (среднее колец всех типов периодов).
  GoalPeriod? _periodType = GoalPeriod.month;

  /// Гранулярность точки графика — «Каждая точка —» (как у задач).
  ChartGrouping _grouping = ChartGrouping.monthly;

  /// «Показать за» — зависит только от [_grouping] (как у задач).
  _TfKind _timeframe = _TfKind.months6;

  void _setGrouping(ChartGrouping g) {
    final available = _timeframesFor(g);
    final tf = available.contains(_timeframe) ? _timeframe : available.first;
    setState(() {
      _grouping = g;
      _timeframe = tf;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final profile = ref.watch(profileProvider).value;
    final (from, to) = _timeframe.resolve(profile?.startedAt);
    // Сводка/карточки — по типу периода + диапазону, не зависят от гранулярности.
    final summaryRange =
        GoalStatsRange(period: _periodType, from: from, to: to);
    final summaryAsync = ref.watch(goalStatsSummaryProvider(summaryRange));
    final available = _timeframesFor(_grouping);

    // Прокручиваемое тело — та же структура/паддинг, что у вкладки «Задачи».
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      children: [
        summaryAsync.when(
          loading: () => const _SummarySkeleton(),
          error: (e, _) => ErrorView(
            compact: true,
            onRetry: () => ref.invalidate(goalStatsSummaryProvider(summaryRange)),
          ),
          data: (s) => _GoalSummaryBlock(
            summary: s,
            grouping: _periodType,
            timeframePhrase: _timeframe.forPhrase(l10n),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // «Тип периода» — какие цели анализируем.
                _chipsLabel(context, l10n.goalPeriodTypeLabel),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final p in GoalPeriod.values)
                      SegChip(
                        label: _goalPeriodLabel(l10n, p),
                        selected: _periodType == p,
                        onTap: () => setState(() => _periodType = p),
                      ),
                    // «Общий» — среднее колец всех типов периодов сразу.
                    SegChip(
                      label: l10n.goalPeriodOverall,
                      selected: _periodType == null,
                      onTap: () => setState(() => _periodType = null),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                // «Каждая точка —» — гранулярность точки графика (как у задач).
                _chipsLabel(context, l10n.eachPointLabel),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final g in ChartGrouping.values)
                      SegChip(
                        label: _chartGroupingLabel(l10n, g),
                        selected: _grouping == g,
                        onTap: () => _setGrouping(g),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                _chipsLabel(context, l10n.showForLabel),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final tf in available)
                      SegChip(
                        label: tf.label(l10n),
                        selected: _timeframe == tf,
                        onTap: () => setState(() => _timeframe = tf),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 300,
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
              boxShadow: AppColors.stickerShadow,
              border: Border.all(
                color: Theme.of(context).brightness == Brightness.dark
                    ? AppColors.surfaceDarkMuted
                    : AppColors.ringTrack,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 14, 14, 10),
              child: GoalProductivityChart(
                from: from,
                to: to,
                periodType: _periodType,
                grouping: _grouping,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        const _GoalTagStatsButton(),
        const SizedBox(height: 12),
        const GoalDeadlineCard(),
      ],
    );
  }
}

/// Карточка-кнопка перехода к статистике по тегам целей.
class _GoalTagStatsButton extends StatelessWidget {
  const _GoalTagStatsButton();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const GoalTagStatsScreen()),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(Icons.tag, color: theme.colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  context.l10n.goalTagStatsButtonLabel,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              Icon(Icons.chevron_right,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.4)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Сводка раздела «Цели» — та же раскладка, что у задач (_SummaryBlock).
class _GoalSummaryBlock extends StatelessWidget {
  const _GoalSummaryBlock({
    required this.summary,
    required this.grouping,
    required this.timeframePhrase,
  });
  final GoalStatsSummary summary;

  /// Тип периода (null — «Общий»); прокидывается в карточку лучшего периода.
  final GoalPeriod? grouping;
  final String timeframePhrase;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final avg = summary.avgCompletion;

    final avgCard = _SummaryCard(
      label: l10n.goalStatAverage,
      value: avg == null ? '—' : '${(avg * 100).round()}%',
      sub: summary.periodsWithData == 0
          ? l10n.noDataNote
          : l10n.forNPeriodsNote(summary.periodsWithData),
      color: theme.colorScheme.primary,
    );
    final goalsCard = _SummaryCard(
      label: l10n.goalsSummaryLabel,
      value: '${summary.completedGoals}/${summary.totalGoals}',
      sub: l10n.completedPhrase(timeframePhrase),
      color: theme.colorScheme.tertiary,
    );
    final bestCard = _BestGoalPeriodCard(summary: summary, grouping: grouping);

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 600) {
          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: avgCard),
                const SizedBox(width: 8),
                Expanded(child: goalsCard),
                const SizedBox(width: 8),
                Expanded(child: bestCard),
              ],
            ),
          );
        }
        return Column(
          children: [
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: avgCard),
                  const SizedBox(width: 8),
                  Expanded(child: goalsCard),
                ],
              ),
            ),
            const SizedBox(height: 8),
            bestCard,
          ],
        );
      },
    );
  }
}

/// Карточка «Лучшая неделя / месяц / сезон / год» — использует уже готовую
/// подпись периода (GoalPeriodRef.labelFor), без ручного форматирования дат,
/// как приходилось делать у задач (_BestBucketCard).
class _BestGoalPeriodCard extends StatelessWidget {
  const _BestGoalPeriodCard({required this.summary, required this.grouping});

  final GoalStatsSummary summary;

  /// null — «Общий» (лучший период среди всех типов).
  final GoalPeriod? grouping;

  // В режиме «Общий» (null) лучший период — это лучшая НЕДЕЛЯ (по продуктивности
  // всех типов), поэтому заголовок тот же, что и для типа «Неделя».
  String _label(AppLocalizations l10n) => switch (grouping) {
        GoalPeriod.week || null => l10n.bestWeekLabel,
        GoalPeriod.month => l10n.bestMonthLabel,
        GoalPeriod.season => l10n.bestSeasonLabel,
        GoalPeriod.year => l10n.bestYearLabel,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final subColor = theme.colorScheme.onSurface.withValues(alpha: 0.5);
    final best = summary.bestPeriod;
    final ru = Localizations.localeOf(context).languageCode == 'ru';

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _label(l10n),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              best == null ? '—' : best.labelFor(ru),
              style: theme.textTheme.titleLarge?.copyWith(
                color: AppColors.success,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (best != null && summary.bestCompletion != null) ...[
              const SizedBox(height: 2),
              Text.rich(
                TextSpan(
                  style: theme.textTheme.bodySmall?.copyWith(color: subColor),
                  children: [
                    TextSpan(
                      text: '${(summary.bestCompletion! * 100).round()}%',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    TextSpan(text: l10n.goalsWordSuffix),
                    if (summary.bestOnTimeRate != null) ...[
                      TextSpan(text: l10n.outOfWhichPrefix),
                      TextSpan(
                        text: '${(summary.bestOnTimeRate! * 100).round()}%',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      TextSpan(text: l10n.onTimeWordSuffix),
                    ],
                  ],
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
