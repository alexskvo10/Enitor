/// Компактное представление целых чисел: 10000 → «10k», 2500000 → «2.5M».
String compactCount(int n) {
  final abs = n.abs();
  if (abs < 1000) return '$n';
  if (abs < 1000000) return '${_trim(n / 1000)}k';
  if (abs < 1000000000) return '${_trim(n / 1000000)}M';
  return '${_trim(n / 1000000000)}B';
}

/// Одна десятичная без хвоста .0: 10.0 → «10», 2.5 → «2.5».
String _trim(double v) =>
    v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);
