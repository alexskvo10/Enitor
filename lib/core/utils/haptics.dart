import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:vibration/vibration.dart';

/// Тактильный отклик. Только мобильные платформы — на десктопе/вебе тихий no-op.
///
/// Используем ПРЯМОЙ вибромотор (`vibration`), а не `HapticFeedback`: последний
/// подчиняется системному тумблеру «виброотклик при касании», который у
/// пользователя может быть выключен — тогда отклик молчит. Прямой импульс
/// (как у уведомлений) срабатывает независимо.
abstract final class Haptics {
  static bool get _supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  /// Задача/цель выполнена — короткий резкий импульс «готово».
  static void completed() {
    if (!_supported) return;
    unawaited(
      Vibration.vibrate(duration: 50, amplitude: 200).catchError((_) {}),
    );
  }
}
