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

  /// Конец фокуса или перерыва — импульсы в такт нотам сигнала.
  static void focusDone() {
    if (!_supported) return;
    unawaited(
      Vibration.vibrate(pattern: focusDonePattern).catchError((_) {}),
    );
  }

  /// Пауза/импульс, мс: три ноты через 0,6 с, секунда тишины, ещё раз —
  /// как в pomodoro_done.wav. Тот же рисунок у уведомления в фоне.
  static const focusDonePattern = [
    0, 120, 480, 120, 480, 120, //
    1510, 120, 480, 120, 480, 120,
  ];
}
