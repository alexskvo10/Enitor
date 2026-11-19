import 'dart:math';

/// Компактное представление целых чисел: 10000 → «10k», 2500000 → «2.5M».
String compactCount(int n) {
  if (n.abs() < 1000) return '$n';
  // Округляем до десятых сразу: 9999 → 10.0k → «10k», 999950 → «1M».
  const units = ['k', 'M', 'B'];
  for (var i = 0; i < units.length; i++) {
    final v = (n / pow(1000, i + 1) * 10).round() / 10;
    if (v.abs() < 1000 || i == units.length - 1) {
      return '${_trim(v)}${units[i]}';
    }
  }
  throw StateError('unreachable');
}

/// Одна десятичная без хвоста .0: 10.0 → «10», 2.5 → «2.5».
String _trim(double v) =>
    v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);

/// Текст для поиска: без регистра и «ё» = «е» — «елка» находит «Ёлку».
String searchNorm(String s) => s.toLowerCase().replaceAll('ё', 'е');
