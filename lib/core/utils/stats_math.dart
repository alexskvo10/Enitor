/// Общая статистическая арифметика для аналитики (точность оценок задач,
/// просрочка дедлайнов целей и т.п.) — вынесено, чтобы не дублировать в
/// каждом месте, где считается медиана/взвешенная медиана одной и той же
/// выборки.

double median(List<double> values) {
  final sorted = [...values]..sort();
  final mid = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[mid]
      : (sorted[mid - 1] + sorted[mid]) / 2;
}

/// Взвешенная медиана: идём по значениям в порядке возрастания и накапливаем
/// вес, пока не наберём половину суммарного веса — это и есть взвешенная
/// медиана. Крупные по весу элементы сильнее двигают результат, мелкие —
/// почти не влияют, даже если отклонение на них огромное.
double weightedMedian(List<double> values, List<double> weights) {
  final order = List.generate(values.length, (i) => i)
    ..sort((a, b) => values[a].compareTo(values[b]));
  final total = weights.fold<double>(0, (s, w) => s + w);
  final half = total / 2;
  var cum = 0.0;
  for (final i in order) {
    cum += weights[i];
    if (cum >= half) return values[i];
  }
  return values[order.last];
}
