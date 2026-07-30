import 'package:flutter/widgets.dart';

import 'app_localizations.dart';

/// Короткий доступ к строкам: `context.l10n.today`.
extension L10nX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}

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
