import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' as intl;
import 'package:path_provider/path_provider.dart';

import '../data/sources/local/local_storage.dart';
import '../l10n/app_localizations.dart';

AppLocalizations get _l10n =>
    lookupAppLocalizations(Locale(intl.Intl.defaultLocale ?? 'ru'));

/// Резервное копирование (этап 6-lite): экспорт/импорт всех данных одним JSON,
/// плюс авто-бэкап в папку приложения и авто-восстановление при пустом старте.
///
/// Бэкапит ВЕСЬ слепок SharedPreferences — значит новые сущности попадают в
/// бэкап автоматически, без правок здесь.
class BackupService {
  BackupService(this._storage);

  final LocalStorage _storage;

  static const _formatVersion = 1;
  static const _autoBackupName = 'auto_backup.json';

  /// Собирает JSON-бэкап (с метаданными).
  String buildJson() {
    final payload = <String, Object?>{
      'app': 'todo',
      'format': _formatVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'platform': defaultTargetPlatform.name,
      'data': _storage.snapshot(),
    };
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  /// Восстанавливает данные из JSON-строки. Бросает [FormatException] на чужом
  /// файле. [clear] — полная замена (по умолчанию).
  Future<void> restoreFromJson(String jsonStr, {bool clear = true}) async {
    final decoded = jsonDecode(jsonStr);
    if (decoded is! Map || decoded['app'] != 'todo' || decoded['data'] is! Map) {
      throw FormatException(_l10n.notBackupFileError);
    }
    final data = (decoded['data'] as Map).map(
      (k, v) => MapEntry(k.toString(), v as Object?),
    );
    await _storage.restore(data, clear: clear);
  }

  // ── Экспорт/импорт через файловый диалог ────────────────────────────────

  /// Сохраняет бэкап в выбранный файл. Возвращает путь или null (отмена).
  Future<String?> exportToFile() async {
    final json = buildJson();
    final name = 'enitor-backup-${_stamp()}.json';

    // На мобиле saveFile сам пишет файл (нужны bytes); на десктопе — только
    // возвращает путь, писать надо самим.
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      return FilePicker.platform.saveFile(
        dialogTitle: _l10n.saveBackupDialogTitle,
        fileName: name,
        type: FileType.custom,
        allowedExtensions: const ['json'],
        bytes: Uint8List.fromList(utf8.encode(json)),
      );
    }
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Сохранить бэкап',
      fileName: name,
      type: FileType.custom,
      allowedExtensions: const ['json'],
    );
    if (path != null) {
      final fixed = path.toLowerCase().endsWith('.json') ? path : '$path.json';
      await File(fixed).writeAsString(json);
      return fixed;
    }
    return null;
  }

  /// Импортирует бэкап из выбранного файла. Возвращает true при успехе.
  /// Бросает [FormatException] на чужом/битом файле.
  Future<bool> importFromFile() async {
    final res = await FilePicker.platform.pickFiles(
      dialogTitle: _l10n.pickBackupFileDialogTitle,
      type: FileType.custom,
      allowedExtensions: const ['json'],
      withData: true,
    );
    if (res == null || res.files.isEmpty) return false;
    final f = res.files.first;
    final content = f.bytes != null
        ? utf8.decode(f.bytes!)
        : await File(f.path!).readAsString();
    await restoreFromJson(content);
    return true;
  }

  // ── Авто-бэкап в папке приложения ───────────────────────────────────────

  Future<File> _autoBackupFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_autoBackupName');
  }

  /// Пишет авто-бэкап АТОМАРНО: сначала во временный `.tmp`, и лишь когда он
  /// полностью записан — заменяет им основной файл. Так прерванная запись
  /// (вылет/потеря питания) не уничтожит уже существующий целый бэкап.
  /// Тихо: ошибки глотаются — авто-бэкап не критичен для работы.
  Future<void> writeAutoBackup() async {
    try {
      final f = await _autoBackupFile();
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(buildJson(), flush: true);
      // rename на существующий файл на Windows бросает — удаляем основной.
      if (await f.exists()) await f.delete();
      await tmp.rename(f.path);
    } catch (_) {}
  }

  /// Читает авто-бэкап. Если основной файл пропал (крайне редко — крах ровно
  /// между удалением и переименованием), берём целый `.tmp`.
  Future<String?> readAutoBackup() async {
    try {
      final f = await _autoBackupFile();
      if (await f.exists()) return await f.readAsString();
      final tmp = File('${f.path}.tmp');
      if (await tmp.exists()) return await tmp.readAsString();
    } catch (_) {}
    return null;
  }

  String _stamp() {
    final n = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${n.year}${two(n.month)}${two(n.day)}-${two(n.hour)}${two(n.minute)}';
  }
}

final backupServiceProvider = Provider<BackupService>(
  (ref) => BackupService(ref.read(localStorageProvider)),
);
