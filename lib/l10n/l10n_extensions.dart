import 'package:flutter/widgets.dart';

import 'app_localizations.dart';

/// Короткий доступ к строкам: `context.l10n.today`.
extension L10nX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}
