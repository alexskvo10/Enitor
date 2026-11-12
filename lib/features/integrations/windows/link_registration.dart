import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Состояние регистрации схемы `enitor://` в Windows.
enum LinkRegistrationState {
  /// Не зарегистрирована (выключено или ещё ни разу не включали).
  off,

  /// Зарегистрирована для этой папки.
  current,

  /// Зарегистрирована на другой путь — папку с Enitor перенесли.
  stale,
}

typedef ProcessRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments,
);

/// Регистрация `enitor://` в HKCU (без прав администратора, только для
/// текущего пользователя). Через системную `reg.exe` — тем же способом, что
/// и прописка уведомлений в NotificationService.
class LinkRegistration {
  LinkRegistration({ProcessRunner? run, String? exePath})
      : _run = run ?? Process.run,
        _exe = exePath ?? Platform.resolvedExecutable;

  final ProcessRunner _run;
  final String _exe;

  static const _root = r'HKCU\Software\Classes\enitor';
  static const _command = r'HKCU\Software\Classes\enitor\shell\open\command';

  /// Команда, которую Windows выполнит по ссылке.
  String get expectedCommand => '"$_exe" "%1"';

  Future<LinkRegistrationState> state() async {
    final r = await _run('reg', ['query', _command, '/ve']);
    if (r.exitCode != 0) return LinkRegistrationState.off;
    // Строка вида «    (Default)    REG_SZ    "C:\…\enitor.exe" "%1"».
    final line = (r.stdout as String)
        .split('\n')
        .map((l) => l.trim())
        .firstWhere((l) => l.contains('REG_SZ'), orElse: () => '');
    final i = line.indexOf('REG_SZ');
    final value = i < 0 ? '' : line.substring(i + 'REG_SZ'.length).trim();
    return value.toLowerCase() == expectedCommand.toLowerCase()
        ? LinkRegistrationState.current
        : LinkRegistrationState.stale;
  }

  Future<void> register() async {
    for (final args in [
      ['add', _root, '/ve', '/d', 'URL:Enitor', '/f'],
      ['add', _root, '/v', 'URL Protocol', '/d', '', '/f'],
      ['add', '$_root\\DefaultIcon', '/ve', '/d', '"$_exe",0', '/f'],
      ['add', _command, '/ve', '/d', expectedCommand, '/f'],
    ]) {
      await _run('reg', args);
    }
  }

  Future<void> unregister() => _run('reg', ['delete', _root, '/f']);

  /// При запуске: включено — регистрируем или чиним путь, выключено —
  /// убираем. Возвращает состояние до починки: `stale` значит «путь
  /// устарел — исправлено».
  Future<LinkRegistrationState> sync({required bool enabled}) async {
    try {
      final before = await state();
      if (enabled && before != LinkRegistrationState.current) {
        await register();
      } else if (!enabled && before != LinkRegistrationState.off) {
        await unregister();
      }
      return before;
    } catch (e) {
      debugPrint('LinkRegistration: $e');
      return LinkRegistrationState.off;
    }
  }
}

final linkRegistrationProvider = Provider<LinkRegistration>(
  (ref) => LinkRegistration(),
);

/// Что было при последней сверке на этом запуске — для строки состояния.
final linkSyncResultProvider =
    StateProvider<LinkRegistrationState?>((ref) => null);
