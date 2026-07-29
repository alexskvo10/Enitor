/// Утилиты для работы с датами (без времени).

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

DateTime today() => dateOnly(DateTime.now());

/// Час, с которого начинается «день приложения»: до него ночные часы ещё
/// относятся к уходящему дню.
const kDayStartHour = 4;

/// День, которому принадлежит момент [d] с точки зрения приложения. До 4:00
/// это ВЧЕРАШНЯЯ дата: ночные часы засчитываются уходящему дню.
///
/// Единый источник правила — раньше оно было продублировано в UI
/// (`_effectiveToday`) и не применялось в статистике, из-за чего задача,
/// законченная в 01:30, попадала в «опоздания», хотя приложение всё ещё
/// показывало её вчерашним днём.
DateTime effectiveDay(DateTime d) => d.hour < kDayStartHour
    ? dateOnly(d).subtract(const Duration(days: 1))
    : dateOnly(d);

/// Минуты от начала [effectiveDay] для момента [d]. Ночь после полуночи
/// продолжает шкалу уходящего дня: 01:30 → 1530, а не 90. Нужно, чтобы
/// сравнение со временем окончания задачи не «перепрыгивало» через полночь.
int minutesFromDayStart(DateTime d) {
  final mins = d.hour * 60 + d.minute;
  return d.hour < kDayStartHour ? mins + 1440 : mins;
}

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
