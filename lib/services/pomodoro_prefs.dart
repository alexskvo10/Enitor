import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/sources/local/local_storage.dart';

const _kPomodoroPrefsKey = 'pomodoro_prefs';

/// Классические 25/5 остаются значениями ПО УМОЛЧАНИЮ — но именно значениями
/// по умолчанию, а не законом: кому-то 25 минут не хватает войти в работу,
/// кому-то они уже слишком длинные.
const kPomodoroDefaultFocusMinutes = 25;
const kPomodoroDefaultBreakMinutes = 5;

/// Допустимые длины. Список закрытый, а не свободный ввод: длина отрезка —
/// это про ритм, а не про точность, и произвольное поле пришлось бы защищать
/// от нуля, отрицательных значений и «600». Заодно эти же списки задают
/// пункты выпадашки в настройках.
const kPomodoroFocusOptions = <int>[10, 15, 20, 25, 30, 35, 40, 45, 50, 60, 90];
const kPomodoroBreakOptions = <int>[3, 5, 7, 10, 15, 20, 30];

/// Длины отрезков Помодоро. Отдельно от [PomodoroController] намеренно: тот
/// шлёт уведомление каждую секунду, пока идёт отсчёт, и экран настроек,
/// подписанный на него, перерисовывался бы столько же раз.
class PomodoroPrefsController extends ChangeNotifier {
  PomodoroPrefsController(this._storage) {
    final raw = _storage.readMap(_kPomodoroPrefsKey);
    if (raw != null) {
      _focusMinutes = _sanitize(
        raw['focusMinutes'],
        kPomodoroFocusOptions,
        kPomodoroDefaultFocusMinutes,
      );
      _breakMinutes = _sanitize(
        raw['breakMinutes'],
        kPomodoroBreakOptions,
        kPomodoroDefaultBreakMinutes,
      );
    }
  }

  final LocalStorage _storage;

  int _focusMinutes = kPomodoroDefaultFocusMinutes;
  int _breakMinutes = kPomodoroDefaultBreakMinutes;

  int get focusMinutes => _focusMinutes;
  int get breakMinutes => _breakMinutes;

  Future<void> setFocusMinutes(int v) async {
    if (v == _focusMinutes || !kPomodoroFocusOptions.contains(v)) return;
    _focusMinutes = v;
    notifyListeners();
    await _save();
  }

  Future<void> setBreakMinutes(int v) async {
    if (v == _breakMinutes || !kPomodoroBreakOptions.contains(v)) return;
    _breakMinutes = v;
    notifyListeners();
    await _save();
  }

  /// «Настройки → Сбросить настройки» — как и у оформления, через контроллер,
  /// а не удалением ключа: иначе экран остался бы со старыми значениями в
  /// памяти и перезаписал бы их при первой правке.
  Future<void> resetToDefaults() async {
    _focusMinutes = kPomodoroDefaultFocusMinutes;
    _breakMinutes = kPomodoroDefaultBreakMinutes;
    notifyListeners();
    await _save();
  }

  Future<void> _save() => _storage.writeMap(_kPomodoroPrefsKey, {
        'focusMinutes': _focusMinutes,
        'breakMinutes': _breakMinutes,
      });

  /// Значение вне списка (чужой бэкап, будущая версия с другими пресетами,
  /// битый ключ) заменяется дефолтом, а не зажимается в диапазон: выпадашка
  /// в настройках падает на значении, которого нет среди её пунктов.
  static int _sanitize(Object? raw, List<int> allowed, int fallback) {
    final v = raw is int ? raw : null;
    return v != null && allowed.contains(v) ? v : fallback;
  }
}

final pomodoroPrefsProvider =
    ChangeNotifierProvider<PomodoroPrefsController>((ref) {
  return PomodoroPrefsController(ref.read(localStorageProvider));
});
