/// Утилиты для работы с датами (без времени).

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

DateTime today() => dateOnly(DateTime.now());

/// Понедельник текущей недели для переданной даты.
DateTime startOfWeek(DateTime d) {
  final day = dateOnly(d);
  return day.subtract(Duration(days: day.weekday - 1));
}

DateTime startOfMonth(DateTime d) => DateTime(d.year, d.month);

DateTime startOfYear(DateTime d) => DateTime(d.year);

/// Дата за [months] месяцев до [d] (день зажимается по длине целевого месяца,
/// чтобы не «перепрыгнуть»: 31 марта − 1 месяц = 28/29 февраля, а не 3 марта,
/// как получилось бы у сырого DateTime(y, m - 1, 31)).
DateTime subtractMonths(DateTime d, int months) {
  var y = d.year;
  var m = d.month - months;
  while (m <= 0) {
    m += 12;
    y -= 1;
  }
  while (m > 12) {
    m -= 12;
    y += 1;
  }
  final lastDay = DateTime(y, m + 1, 0).day; // последний день месяца m
  final day = d.day < lastDay ? d.day : lastDay;
  return DateTime(y, m, day);
}

/// Итерирует даты из [from] в [to] включительно.
Iterable<DateTime> daysBetween(DateTime from, DateTime to) sync* {
  var current = dateOnly(from);
  final end = dateOnly(to);
  while (!current.isAfter(end)) {
    yield current;
    current = current.add(const Duration(days: 1));
  }
}
