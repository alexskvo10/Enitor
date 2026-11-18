import 'package:flutter/widgets.dart';

import '../core/utils/format_utils.dart';
import '../data/models/goal.dart';
import 'app_localizations.dart';

/// Короткий доступ к строкам: `context.l10n.today`.
extension L10nX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}

/// Короткая длительность: «25м», «1ч 30м» / "25m", "1h 30m".
String fmtDuration(int minutes, BuildContext context) {
  final ru = Localizations.localeOf(context).languageCode == 'ru';
  final hSuffix = ru ? 'ч' : 'h';
  final mSuffix = ru ? 'м' : 'm';
  if (minutes < 60) return '$minutes$mSuffix';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return m == 0 ? '$h$hSuffix' : '$h$hSuffix $m$mSuffix';
}

/// Число цели-счётчика в её единице: «12» или «5ч 30м».
String fmtGoalAmount(int v, Goal g, BuildContext context) =>
    g.isTime ? fmtDuration(v, context) : compactCount(v);

/// Названия дней недели по порядку [DateTime.weekday] — индекс `weekday - 1`.
/// Общее для всех мест, где день недели показывается списком или по номеру
/// (итоги недели, выбор дня разбора в настройках).
List<String> weekdayNames(AppLocalizations l10n) => [
      l10n.weekdayMonday,
      l10n.weekdayTuesday,
      l10n.weekdayWednesday,
      l10n.weekdayThursday,
      l10n.weekdayFriday,
      l10n.weekdaySaturday,
      l10n.weekdaySunday,
    ];
