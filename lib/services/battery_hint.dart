import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../data/sources/local/local_storage.dart';

const _kBatteryHintKey = 'battery_hint';

/// «Умная» подсказка про оптимизацию батареи.
///
/// Смотрит ТОЛЬКО на постоянный флажок «приложение исключено из фоновых
/// ограничений» (`ignoreBatteryOptimizations`), а НЕ на уровень заряда и НЕ на
/// режим энергосбережения. Поэтому не дёргает в неподходящий момент: если
/// разрешение уже есть или пользователь скрыл подсказку — она больше не
/// показывается.
class BatteryHintController extends ChangeNotifier {
  BatteryHintController(this._storage) {
    final raw = _storage.readMap(_kBatteryHintKey);
    _dismissed = raw?['dismissed'] as bool? ?? false;
    _refresh();
  }

  final LocalStorage _storage;

  bool _dismissed = false;
  bool _granted = true; // до проверки считаем «ок», чтобы не мигало
  bool _checked = false;

  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Показывать ли подсказку: только Android, проверка прошла, ещё не выдано и
  /// не скрыто пользователем.
  bool get shouldShow => _isAndroid && _checked && !_granted && !_dismissed;

  Future<void> _refresh() async {
    if (!_isAndroid) {
      _checked = true;
      notifyListeners();
      return;
    }
    try {
      _granted = await Permission.ignoreBatteryOptimizations.isGranted;
    } catch (_) {
      _granted = true; // плагин недоступен — не навязываемся
    }
    _checked = true;
    notifyListeners();
  }

  /// Системный диалог «разрешить работу в фоне» (одним тапом).
  Future<void> allow() async {
    if (!_isAndroid) return;
    try {
      await Permission.ignoreBatteryOptimizations.request();
    } catch (_) {}
    await _refresh();
  }

  /// Скрыть навсегда.
  Future<void> dismiss() async {
    _dismissed = true;
    notifyListeners();
    await _storage.writeMap(_kBatteryHintKey, {'dismissed': true});
  }

  /// Перепроверить статус (например, при возврате на экран).
  Future<void> recheck() => _refresh();
}

final batteryHintProvider =
    ChangeNotifierProvider<BatteryHintController>((ref) {
  return BatteryHintController(ref.read(localStorageProvider));
});
