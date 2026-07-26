import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/sources/local/local_storage.dart';

const _kLocaleKey = 'app_locale';

/// Язык приложения. `system` — берём язык устройства (если он входит в
/// список поддерживаемых, иначе фолбэк на русский).
enum AppLocaleOption { system, ru, en }

/// Выбор языка интерфейса. Persist в SharedPreferences — как [AppearanceController].
class LocaleController extends ChangeNotifier {
  LocaleController(this._storage) {
    final raw = _storage.readMap(_kLocaleKey);
    if (raw != null) {
      final idx = (raw['option'] as int? ?? 0)
          .clamp(0, AppLocaleOption.values.length - 1);
      _option = AppLocaleOption.values[idx];
    }
  }

  final LocalStorage _storage;

  AppLocaleOption _option = AppLocaleOption.system;
  AppLocaleOption get option => _option;

  /// null — отдать выбор системе (MaterialApp сам разрешит через
  /// supportedLocales); иначе — принудительная локаль.
  Locale? get locale => switch (_option) {
        AppLocaleOption.system => null,
        AppLocaleOption.ru => const Locale('ru'),
        AppLocaleOption.en => const Locale('en'),
      };

  Future<void> setOption(AppLocaleOption v) async {
    if (v == _option) return;
    _option = v;
    notifyListeners();
    await _storage.writeMap(_kLocaleKey, {'option': _option.index});
  }
}

final localeControllerProvider = ChangeNotifierProvider<LocaleController>((ref) {
  return LocaleController(ref.read(localStorageProvider));
});
