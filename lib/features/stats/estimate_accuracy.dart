import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/appearance.dart';
import '../../core/utils/stats_math.dart' as stats_math;
import '../../data/models/task.dart';
import '../../data/repositories/task_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/l10n_extensions.dart';

/// Аналитика точности оценок времени: сравнение estimatedMinutes (план)
/// и actualMinutes (факт). Обе метрики НЕОБЯЗАТЕЛЬНЫЕ — участвуют только
/// задачи, где заполнены обе. Нет данных → карточка не показывается вовсе.
///
/// Считаются ДВЕ метрики параллельно:
///   - «по количеству задач» — обычная медиана отношения факт/оценка,
///     каждая пара весит одинаково (один выброс не ломает картину, но
///     пачка мелких задач шумит наравне с крупными);
///   - «по времени» — медиана того же отношения, но взвешенная по
///     estimatedMinutes: крупные по времени задачи сильнее двигают
///     результат, а промах на 5-минутном перекусе почти не заметен.

const _kMinPairs = 3; // меньше — не показываем вообще
const _kConfidentPairs = 10; // меньше — показываем с пометкой «мало данных»

/// Размер оценки: короткие и длинные задачи врут по-разному.
enum DurationBucket { under30, m30to60, h1to2, over2h }

String _durationBucketLabel(AppLocalizations l10n, DurationBucket b) =>
    switch (b) {
      DurationBucket.under30 => l10n.bucketUnder30,
      DurationBucket.m30to60 => l10n.bucket30to60,
      DurationBucket.h1to2 => l10n.bucket1to2h,
      DurationBucket.over2h => l10n.bucketOver2h,
    };

/// Единый цвет по величине отклонения: ≤10% — зелёный (точно), ≤25% —
/// янтарный, иначе красный. Используется и в карточке, и в строках бакетов.
Color accuracyColor(int absBias) => absBias <= 10
    ? AppColors.success
    : absBias <= 25
        ? AppColors.warning
        : AppColors.danger;

/// Одна метрика точности — медиана отношения факт/оценка плюс все
/// производные (смещение в %, цвет, текстовые формулировки). Используется
/// и для «по количеству», и для «по времени» — отличается только тем,
/// как была посчитана исходная медиана (см. [_median]/[_weightedMedian]).
class AccuracyMetric {
  const AccuracyMetric(this.medianRatio, this.minutesBias);

  /// Медиана отношения факт/оценка.
  final double medianRatio;

  /// Медиана (тем же методом — обычная или взвешенная по estimatedMinutes,
  /// см. [AccuracyBucket.byCount]/[byTime]) разницы факт−оценка в минутах,
  /// со знаком. Отдельная статистика от [medianRatio] — считается на тех же
  /// парах, но не привязана к нему математически (медианы разных
  /// преобразований одной выборки не обязаны согласовываться).
  final int minutesBias;

  /// Смещение в процентах: +30 — недооцениваешь, −20 — переоцениваешь.
  int get biasPercent => ((medianRatio - 1) * 100).round();

  /// Абсолютное смещение в %.
  int get absBias => biasPercent.abs();

  /// Абсолютное смещение в минутах.
  int get absMinutesBias => minutesBias.abs();

  /// В пределах ±10% — считаем оценки точными.
  bool get isAccurate => absBias <= 10;

  /// Цвет по величине отклонения (см. [accuracyColor]).
  Color get magnitudeColor => accuracyColor(absBias);

  /// Короткая метка для карточки: «±6%» / «+30%» / «−20%».
  String get shortLabel => isAccurate
      ? '±$absBias%'
      : biasPercent > 0
          ? '+$biasPercent%'
          : '−$absBias%';

  /// Метка для строк бакетов/тегов: слово «точно» вместо «±0%».
  String rowLabel(AppLocalizations l10n) => isAccurate
      ? l10n.accurateLabel
      : biasPercent > 0
          ? '+$biasPercent%'
          : '−$absBias%';

  /// Тот же знак/± паттерн, что у [shortLabel], но в минутах — абсолютная
  /// величина погрешности рядом с относительной (%).
  String minutesLabel(AppLocalizations l10n) => isAccurate
      ? '±$absMinutesBias ${l10n.minutesAbbrev}'
      : minutesBias > 0
          ? '+$minutesBias ${l10n.minutesAbbrev}'
          : '−$absMinutesBias ${l10n.minutesAbbrev}';

  /// Короткая характеристика для подписи рядом с числом.
  String phrase(AppLocalizations l10n) => isAccurate
      ? l10n.phraseAccurate
      : biasPercent > 0
          ? l10n.phraseUnderestimate
          : l10n.phraseOverestimate;

  /// Короткий вердикт для детального экрана.
  String verdict(AppLocalizations l10n) {
    if (isAccurate) return l10n.verdictAccurate;
    return biasPercent > 0
        ? l10n.verdictUnderestimate(biasPercent)
        : l10n.verdictOverestimate(absBias);
  }
}

/// Бакет: либо по размеру оценки ([durationBucket]), либо по тегу ([label] —
/// уже готовая строка «#tag», не требует перевода). Несёт обе метрики.
class AccuracyBucket {
  const AccuracyBucket({
    this.label,
    this.durationBucket,
    required this.pairs,
    required this.byCount,
    required this.byTime,
  });

  final String? label;
  final DurationBucket? durationBucket;
  final int pairs;

  /// Медиана без веса — каждая пара считается одинаково.
  final AccuracyMetric byCount;

  /// Медиана, взвешенная по estimatedMinutes — крупные задачи весят больше.
  final AccuracyMetric byTime;

  String displayLabel(AppLocalizations l10n) =>
      label ?? _durationBucketLabel(l10n, durationBucket!);
}

class EstimateAccuracy {
  const EstimateAccuracy({
    required this.pairs,
    required this.overall,
    required this.overallByTime,
    required this.buckets,
    required this.byTag,
  });

  final int pairs;

  /// Общая метрика по количеству задач (равный вес каждой пары).
  final AccuracyMetric overall;

  /// Общая метрика, взвешенная по времени (estimatedMinutes).
  final AccuracyMetric overallByTime;

  final List<AccuracyBucket> buckets;

  /// Точность в разрезе тегов (только теги с ≥ _kMinPairs пар; задача с
  /// несколькими тегами учитывается в каждом). Отсортированы по убыванию
  /// величины отклонения (по количеству задач).
  final List<AccuracyBucket> byTag;

  bool get isConfident => pairs >= _kConfidentPairs;
}

double _median(List<double> values) => stats_math.median(values);

double _weightedMedian(List<double> values, List<double> weights) =>
    stats_math.weightedMedian(values, weights);

DurationBucket _bucketOf(int estimate) {
  if (estimate <= 30) return DurationBucket.under30;
  if (estimate <= 60) return DurationBucket.m30to60;
  if (estimate <= 120) return DurationBucket.h1to2;
  return DurationBucket.over2h;
}

/// Собирает [AccuracyBucket] из уже накопленных отношений/разниц/весов одной
/// группы. [diffs] — разница факт−оценка в минутах, в том же порядке, что
/// [ratios] (используется для minutesBias).
AccuracyBucket _bucketFrom({
  String? label,
  DurationBucket? durationBucket,
  required List<double> ratios,
  required List<double> diffs,
  required List<double> weights,
}) =>
    AccuracyBucket(
      label: label,
      durationBucket: durationBucket,
      pairs: ratios.length,
      byCount: AccuracyMetric(_median(ratios), _median(diffs).round()),
      byTime: AccuracyMetric(
        _weightedMedian(ratios, weights),
        _weightedMedian(diffs, weights).round(),
      ),
    );

EstimateAccuracy? _compute(List<Task> tasks) {
  // Только выполненные задачи с обеими цифрами.
  final withBoth = tasks
      .where((t) =>
          t.isCompleted &&
          t.estimatedMinutes != null &&
          t.estimatedMinutes! > 0 &&
          t.actualMinutes != null &&
          t.actualMinutes! > 0)
      .toList();
  if (withBoth.length < _kMinPairs) return null;

  final ratios = [
    for (final t in withBoth) t.actualMinutes! / t.estimatedMinutes!,
  ];
  final diffs = [
    for (final t in withBoth)
      (t.actualMinutes! - t.estimatedMinutes!).toDouble(),
  ];
  final weights = [
    for (final t in withBoth) t.estimatedMinutes!.toDouble(),
  ];

  // Бакеты по размеру оценки (в порядке возрастания).
  const order = DurationBucket.values;
  final byBucketRatios = <DurationBucket, List<double>>{};
  final byBucketDiffs = <DurationBucket, List<double>>{};
  final byBucketWeights = <DurationBucket, List<double>>{};
  for (final t in withBoth) {
    final b = _bucketOf(t.estimatedMinutes!);
    byBucketRatios
        .putIfAbsent(b, () => [])
        .add(t.actualMinutes! / t.estimatedMinutes!);
    byBucketDiffs
        .putIfAbsent(b, () => [])
        .add((t.actualMinutes! - t.estimatedMinutes!).toDouble());
    byBucketWeights
        .putIfAbsent(b, () => [])
        .add(t.estimatedMinutes!.toDouble());
  }

  // По тегам: задача учитывается в каждом своём теге.
  final byTagRatios = <String, List<double>>{};
  final byTagDiffs = <String, List<double>>{};
  final byTagWeights = <String, List<double>>{};
  for (final t in withBoth) {
    final ratio = t.actualMinutes! / t.estimatedMinutes!;
    final diff = (t.actualMinutes! - t.estimatedMinutes!).toDouble();
    for (final tag in t.tags) {
      byTagRatios.putIfAbsent(tag, () => []).add(ratio);
      byTagDiffs.putIfAbsent(tag, () => []).add(diff);
      byTagWeights
          .putIfAbsent(tag, () => [])
          .add(t.estimatedMinutes!.toDouble());
    }
  }
  // Только теги с ≥ _kMinPairs пар; сортируем по убыванию величины отклонения
  // по количеству задач (где сильнее всего мажешь — сверху).
  final tagBuckets = <AccuracyBucket>[
    for (final e in byTagRatios.entries)
      if (e.value.length >= _kMinPairs)
        _bucketFrom(
          label: '#${e.key}',
          ratios: e.value,
          diffs: byTagDiffs[e.key]!,
          weights: byTagWeights[e.key]!,
        ),
  ]..sort((a, b) => (b.byCount.medianRatio - 1)
      .abs()
      .compareTo((a.byCount.medianRatio - 1).abs()));

  return EstimateAccuracy(
    pairs: withBoth.length,
    overall: AccuracyMetric(_median(ratios), _median(diffs).round()),
    overallByTime: AccuracyMetric(
      _weightedMedian(ratios, weights),
      _weightedMedian(diffs, weights).round(),
    ),
    buckets: [
      for (final b in order)
        if (byBucketRatios.containsKey(b))
          _bucketFrom(
            durationBucket: b,
            ratios: byBucketRatios[b]!,
            diffs: byBucketDiffs[b]!,
            weights: byBucketWeights[b]!,
          ),
    ],
    byTag: tagBuckets,
  );
}

/// null — данных меньше [_kMinPairs] пар (карточка скрыта).
final estimateAccuracyProvider = Provider<EstimateAccuracy?>((ref) {
  final tasks = ref.watch(allTasksProvider).value;
  if (tasks == null) return null;
  return _compute(tasks);
});

// ─── Компактная карточка для экрана Статистики ───────────────────────────────

class EstimateAccuracyCard extends ConsumerWidget {
  const EstimateAccuracyCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final acc = ref.watch(estimateAccuracyProvider);
    if (acc == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final l10n = context.l10n;

    final onSurface = theme.colorScheme.onSurface;
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
              builder: (_) => const EstimateAccuracyScreen()),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Заголовок + шеврон (намёк на переход).
              Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.estimateAccuracyCardTitle,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: onSurface.withValues(alpha: 0.9),
                      ),
                    ),
                  ),
                  Icon(Icons.chevron_right,
                      color: onSurface.withValues(alpha: 0.4)),
                ],
              ),
              const SizedBox(height: 12),
              _CardMetricRow(label: l10n.byTaskCountLabel, metric: acc.overall),
              Divider(
                height: 21,
                thickness: 1,
                color: onSurface.withValues(alpha: 0.08),
              ),
              _CardMetricRow(
                  label: l10n.byTimeLabel, metric: acc.overallByTime),
            ],
          ),
        ),
      ),
    );
  }
}

/// Одна строка карточки: мелкая серая подпись веса сверху, под ней —
/// крупное цветное смещение (слева) и короткая фраза (справа), обе на
/// одной базовой линии.
class _CardMetricRow extends StatelessWidget {
  const _CardMetricRow({required this.label, required this.metric});

  final String label;
  final AccuracyMetric metric;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final onSurface = theme.colorScheme.onSurface;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: onSurface.withValues(alpha: 0.5),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: metric.shortLabel,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: metric.magnitudeColor,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  TextSpan(
                    text: '  ${metric.minutesLabel(l10n)}',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                metric.phrase(l10n),
                textAlign: TextAlign.right,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: onSurface.withValues(alpha: 0.6),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ─── Детальный экран ─────────────────────────────────────────────────────────

class EstimateAccuracyScreen extends ConsumerWidget {
  const EstimateAccuracyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final acc = ref.watch(estimateAccuracyProvider);
    final theme = Theme.of(context);
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.estimateAccuracyTitle)),
      body: acc == null
          ? Center(
              child: NotebookEmptyState(
                icon: Icons.insert_chart_outlined,
                text: l10n.notEnoughData,
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // ── Вердикт (обе метрики) ────────────────────────────────
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _VerdictBlock(
                          label: l10n.byTaskCountLabel,
                          metric: acc.overall,
                          showExample: true,
                        ),
                        const SizedBox(height: 16),
                        _VerdictBlock(
                          label: l10n.byTimeLabel,
                          metric: acc.overallByTime,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          l10n.medianOfPairs(acc.pairs),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.5),
                          ),
                        ),
                        if (!acc.isConfident) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Icon(Icons.info_outline,
                                  size: 15, color: AppColors.warning),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  l10n.lowDataNote,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: AppColors.warning,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // ── По длительности ───────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 6),
                  child: Text(
                    l10n.bySizeLabel,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                for (final b in acc.buckets) _BucketRow(bucket: b),
                // ── По тегам (с поиском) ──────────────────────────────────
                if (acc.byTag.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _TagAccuracySection(byTag: acc.byTag),
                ],
                const SizedBox(height: 12),
                Text(
                  l10n.footerNote,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
    );
  }
}

/// Блок вердикта одной метрики: подпись веса, крупный цветной текст,
/// опционально — пример «оцениваешь в 60 мин → уходит ~X мин».
class _VerdictBlock extends StatelessWidget {
  const _VerdictBlock({
    required this.label,
    required this.metric,
    this.showExample = false,
  });

  final String label;
  final AccuracyMetric metric;
  final bool showExample;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        // «~X%» выделяем цветом по величине отклонения; минуты — рядом,
        // мельче и приглушённее (та же пара методов «по количеству»/
        // «по времени», просто в абсолютных единицах вместо процентов).
        Text.rich(
          TextSpan(
            children: [
              if (metric.isAccurate)
                TextSpan(text: metric.verdict(l10n))
              else ...[
                TextSpan(
                  text: metric.biasPercent > 0
                      ? l10n.underestimatingBy
                      : l10n.overestimatingBy,
                ),
                TextSpan(
                  text: '~${metric.absBias}%',
                  style: TextStyle(
                    color: metric.magnitudeColor,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
              TextSpan(
                text: '  (${metric.minutesLabel(l10n)})',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          style:
              theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        if (showExample) ...[
          const SizedBox(height: 6),
          Text(
            l10n.estimateExample((60 * metric.medianRatio).round()),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
        ],
      ],
    );
  }
}

/// Секция «По тегам» с поиском: заголовок + иконка-лупа справа, по тапу —
/// поле фильтра тегов.
class _TagAccuracySection extends StatefulWidget {
  const _TagAccuracySection({required this.byTag});
  final List<AccuracyBucket> byTag;

  @override
  State<_TagAccuracySection> createState() => _TagAccuracySectionState();
}

class _TagAccuracySectionState extends State<_TagAccuracySection> {
  bool _searching = false;
  String _query = '';
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.6);
    final q = _query.trim().toLowerCase();
    final filtered = q.isEmpty
        ? widget.byTag
        : widget.byTag
            .where((b) => (b.label ?? '').toLowerCase().contains(q))
            .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, right: 2, bottom: 6),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  l10n.byTagLabel,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: muted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              InkWell(
                onTap: () => setState(() {
                  _searching = !_searching;
                  if (!_searching) {
                    _query = '';
                    _ctrl.clear();
                  }
                }),
                borderRadius: BorderRadius.circular(20),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    _searching ? Icons.close : Icons.search,
                    size: 18,
                    color: muted,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (_searching)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: TextField(
              controller: _ctrl,
              autofocus: true,
              decoration: InputDecoration(
                isDense: true,
                hintText: l10n.searchTagTooltip,
                prefixIcon: const Icon(Icons.search, size: 18),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
        if (filtered.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            child: Text(
              l10n.noTagsFound,
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
          )
        else
          for (final b in filtered) _BucketRow(bucket: b),
      ],
    );
  }
}

/// Строка бакета (по размеру ИЛИ по тегу): заголовок + число пар сверху,
/// под ним — обе метрики («по количеству задач» / «по времени») рядом.
class _BucketRow extends StatelessWidget {
  const _BucketRow({required this.bucket});
  final AccuracyBucket bucket;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(bucket.displayLabel(l10n),
                      style: theme.textTheme.bodyLarge),
                ),
                Text(
                  l10n.pairsCount(bucket.pairs),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _MiniMetric(
                      label: l10n.byTaskCountLabel, metric: bucket.byCount),
                ),
                Expanded(
                  child: _MiniMetric(
                      label: l10n.byTimeLabel, metric: bucket.byTime),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Компактная пара «подпись + значение» для строки бакета.
class _MiniMetric extends StatelessWidget {
  const _MiniMetric({required this.label, required this.metric});

  final String label;
  final AccuracyMetric metric;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.5);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.labelSmall?.copyWith(color: muted)),
        const SizedBox(height: 2),
        Text(
          metric.rowLabel(l10n),
          style: theme.textTheme.titleSmall?.copyWith(
            color: metric.magnitudeColor,
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(
          metric.minutesLabel(l10n),
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
          ),
        ),
      ],
    );
  }
}
