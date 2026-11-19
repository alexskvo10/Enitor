import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../data/sources/local/local_storage.dart';

/// Файл из релиза на GitHub.
class ReleaseAsset {
  const ReleaseAsset({
    required this.name,
    required this.downloadUrl,
    required this.size,
    this.digest,
  });

  final String name;
  final String downloadUrl;
  final int size;

  /// Хеш файла от GitHub (`sha256:…`); у старых релизов его может не быть.
  final String? digest;
}

/// Запуск после неудачной замены файлов на Windows: скрипт обновления
/// передаёт этот аргумент старой версии, чтобы она сказала об этом, а не
/// делала вид, что обновилась.
const kUpdateFailedArg = '--update-failed';

/// Выставляется в main по [kUpdateFailedArg]; стартовые окна показывают
/// сообщение один раз.
bool updateFailedOnLaunch = false;

/// Последний релиз репозитория (ответ GitHub API `releases/latest`).
class ReleaseInfo {
  const ReleaseInfo({
    required this.version,
    required this.tagName,
    required this.htmlUrl,
    required this.assets,
    this.notes,
  });

  /// Версия без ведущей `v` (напр. `0.2.0`), для сравнения с
  /// `PackageInfo.version`.
  final String version;
  final String tagName;
  final String htmlUrl;
  final String? notes;
  final List<ReleaseAsset> assets;

  ReleaseAsset? get androidAsset => _findAsset('.apk');
  ReleaseAsset? get windowsAsset => _findAsset('.zip');

  ReleaseAsset? _findAsset(String extension) {
    for (final a in assets) {
      if (a.name.toLowerCase().endsWith(extension)) return a;
    }
    return null;
  }
}

/// `true`, если [remote] строго новее [local] по семверу (major.minor.patch;
/// build-номер после `+` игнорируется, отсутствующие компоненты = 0).
bool isNewerVersion(String remote, String local) {
  final r = _parseVersion(remote);
  final l = _parseVersion(local);
  for (var i = 0; i < 3; i++) {
    if (r[i] != l[i]) return r[i] > l[i];
  }
  return false;
}

List<int> _parseVersion(String v) {
  final clean = v.split('+').first; // без build-номера
  final parts = clean.split('.');
  return List.generate(
      3, (i) => i < parts.length ? int.tryParse(parts[i]) ?? 0 : 0);
}

enum UpdateCheckStatus { upToDate, available, error, throttled }

class UpdateCheckResult {
  const UpdateCheckResult(this.status,
      {this.release, this.currentVersion, this.error});

  final UpdateCheckStatus status;
  final ReleaseInfo? release;
  final String? currentVersion;
  final String? error;
}

/// Проверка и установка обновлений с GitHub Releases. Приложение
/// распространяется вне сторов (sideload), поэтому это единственный способ
/// узнать о новой версии без ручного похода на GitHub.
///
/// Важно: данные пользователя хранятся отдельно от файлов программы
/// (SharedPreferences/APPDATA, вне каталога установки) — замена файлов
/// приложения на новую версию их не затрагивает, никакого экспорта/импорта
/// вокруг обновления не требуется.
/// Превращает markdown-тело релиза в обычный текст для окна обновления.
///
/// GitHub отдаёт заметки ровно так, как они написаны на странице релиза, а
/// диалог рисует их простым [Text] — без разбора разметки. Стоило поставить
/// в начало заметок баннер, и пользователю вывалилась вся HTML-строка
/// `<img ...>` с длинным URL вместо описания. Разметка в заметках будет
/// всегда, поэтому чистим её здесь, а не подгоняем текст релиза под диалог.
String? releaseNotesToPlainText(String? raw) {
  if (raw == null) return null;
  var s = raw;
  s = s.replaceAll(RegExp(r'<[^>]+>'), ''); // HTML-теги целиком
  s = s.replaceAll(RegExp(r'!\[[^\]]*\]\([^)]*\)'), ''); // картинки markdown
  // ссылки → их текст
  s = s.replaceAllMapped(
    RegExp(r'\[([^\]]*)\]\([^)]*\)'),
    (m) => m[1] ?? '',
  );
  // Везде [ \t], а не \s: \s включает перевод строки, и жадная группа
  // съедала пустые строки вокруг разделителя, склеивая абзацы в один.
  s = s.replaceAll(
    RegExp(r'^[ \t]*[-*_]{3,}[ \t]*$', multiLine: true),
    '',
  ); // разделители ---
  s = s.replaceAll(
    RegExp(r'^[ \t]{0,3}#{1,6}[ \t]*', multiLine: true),
    '',
  ); // заголовки ## …
  s = s.replaceAll(
    RegExp(r'^[ \t]{0,3}>[ \t]?', multiLine: true),
    '',
  ); // цитаты
  s = s.replaceAll(RegExp(r'\*\*|__|`'), ''); // жирный и код
  // Курсив одной звёздочкой — отдельным проходом и обязательно после жирного:
  // пары `**` к этому моменту уже сняты, поэтому здесь остаются только
  // настоящие одиночные пары. Запрет на перенос строки внутри бережёт списки
  // вида `* пункт`: там закрывающей звёздочки нет, и строка не пострадает.
  s = s.replaceAllMapped(RegExp(r'\*([^*\n]+)\*'), (m) => m[1] ?? '');
  // Схлопываем пустоту, оставшуюся от вырезанного, чтобы текст не начинался
  // с десятка переводов строки.
  s = s.replaceAll(RegExp(r'[ \t]+\n'), '\n');
  s = s.replaceAll(RegExp(r'\n{3,}'), '\n\n');
  s = s.trim();
  return s.isEmpty ? null : s;
}

class UpdateService {
  UpdateService(this._storage);

  final LocalStorage _storage;

  static const _repo = 'alexskvo10/Enitor';
  static const _apiUrl = 'https://api.github.com/repos/$_repo/releases/latest';
  static const _prefsKey = 'update_check_state';
  static const _throttle = Duration(hours: 24);

  Future<ReleaseInfo?> fetchLatestRelease() async {
    final res = await http.get(
      Uri.parse(_apiUrl),
      headers: const {'Accept': 'application/vnd.github+json'},
    ).timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) return null;
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    final tag = (json['tag_name'] as String? ?? '').trim();
    if (tag.isEmpty) return null;
    final version = tag.startsWith('v') ? tag.substring(1) : tag;
    final assets = (json['assets'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>()
        .map((a) => ReleaseAsset(
              name: a['name'] as String,
              downloadUrl: a['browser_download_url'] as String,
              size: (a['size'] as num?)?.toInt() ?? 0,
              digest: a['digest'] as String?,
            ))
        .toList();
    return ReleaseInfo(
      version: version,
      tagName: tag,
      htmlUrl: json['html_url'] as String? ?? '',
      notes: releaseNotesToPlainText(json['body'] as String?),
      assets: assets,
    );
  }

  /// [force] — игнорирует суточный троттлинг (ручная кнопка «Проверить
  /// обновления»). Без него авто-проверка при старте молчит, если уже
  /// проверяли за последние 24 часа — чтобы не дёргать GitHub на каждый запуск.
  Future<UpdateCheckResult> checkForUpdate({bool force = false}) async {
    PackageInfo? info;
    try {
      if (!force) {
        final last = _storage.readMap(_prefsKey)?['lastCheckMs'] as int?;
        if (last != null &&
            DateTime.now().difference(
                  DateTime.fromMillisecondsSinceEpoch(last),
                ) <
                _throttle) {
          return const UpdateCheckResult(UpdateCheckStatus.throttled);
        }
      }
      info = await PackageInfo.fromPlatform();
      final release = await fetchLatestRelease();
      if (release == null) {
        // Ответ без релиза (лимит GitHub, сбой) — не проверка: отметку не
        // ставим, иначе следующие сутки проверка молчала бы.
        return UpdateCheckResult(UpdateCheckStatus.error,
            currentVersion: info.version, error: 'no release found');
      }
      await _storage.writeMap(_prefsKey, {
        'lastCheckMs': DateTime.now().millisecondsSinceEpoch,
      });
      if (isNewerVersion(release.version, info.version)) {
        return UpdateCheckResult(UpdateCheckStatus.available,
            release: release, currentVersion: info.version);
      }
      return UpdateCheckResult(UpdateCheckStatus.upToDate,
          currentVersion: info.version);
    } catch (e) {
      return UpdateCheckResult(UpdateCheckStatus.error,
          currentVersion: info?.version, error: '$e');
    }
  }

  /// Скачивает файл релиза с прогрессом (0..1). Возвращает путь к файлу.
  Future<String> downloadAsset(
    ReleaseAsset asset, {
    void Function(double progress)? onProgress,
  }) async {
    final dir = await getTemporaryDirectory();
    final destPath = p.join(dir.path, asset.name);
    final file = File(destPath);
    final client = http.Client();
    try {
      final req = http.Request('GET', Uri.parse(asset.downloadUrl));
      final res = await client.send(req);
      // Страница ошибки GitHub/прокси иначе записалась бы как «APK».
      if (res.statusCode != 200) {
        throw http.ClientException(
          'HTTP ${res.statusCode}',
          Uri.parse(asset.downloadUrl),
        );
      }
      final total = res.contentLength ?? asset.size;
      final sink = file.openWrite();
      var received = 0;
      try {
        await for (final chunk in res.stream) {
          sink.add(chunk);
          received += chunk.length;
          if (total > 0) onProgress?.call(received / total);
        }
      } finally {
        await sink.close();
      }
      await verifyDownload(file, asset);
      return destPath;
    } catch (_) {
      // Оборванный или подменённый файл не должен дожить до установки.
      if (await file.exists()) await file.delete();
      rethrow;
    } finally {
      client.close();
    }
  }

  /// Размер и (если GitHub его дал) sha256 скачанного файла совпадают с
  /// релизом — иначе исключение.
  static Future<void> verifyDownload(File file, ReleaseAsset asset) async {
    final length = await file.length();
    if (asset.size > 0 && length != asset.size) {
      throw Exception('Download incomplete: $length of ${asset.size} bytes');
    }
    final digest = asset.digest;
    if (digest == null || !digest.startsWith('sha256:')) return;
    final actual = (await sha256.bind(file.openRead()).first).toString();
    if (actual != digest.substring(7).toLowerCase()) {
      throw Exception('Download checksum mismatch');
    }
  }

  /// Android: отдаёт скачанный APK системному установщику. Тихо (без
  /// вопросов) ОС ставить не даёт — покажет свой экран подтверждения, это
  /// ограничение платформы, не обходится без root.
  Future<void> installAndroidApk(String apkPath) async {
    final result = await OpenFilex.open(apkPath);
    if (result.type != ResultType.done) {
      throw Exception(result.message);
    }
  }

  /// Windows: `.exe` не может заменить сам себя, пока запущен. Скачанный zip
  /// распаковывается во временную папку, дальше маленький bat-скрипт ждёт
  /// закрытия приложения, копирует новые файлы поверх каталога установки и
  /// перезапускает `enitor.exe`. Каталог с данными пользователя (`%APPDATA%`)
  /// в этом процессе не участвует.
  Future<void> installWindowsUpdate(String zipPath) async {
    final exePath = Platform.resolvedExecutable;
    final installDir = File(exePath).parent;
    final exeName = p.basename(exePath);

    final tempDir = await Directory.systemTemp.createTemp('enitor_update_');
    final bytes = await File(zipPath).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    for (final entry in archive) {
      final outPath = p.join(tempDir.path, entry.name);
      // Защита от zip slip: запись должна остаться внутри tempDir.
      if (!p.isWithin(tempDir.path, outPath)) {
        throw Exception('Unsafe archive entry: ${entry.name}');
      }
      if (entry.isFile) {
        final outFile = File(outPath);
        await outFile.create(recursive: true);
        await outFile.writeAsBytes(entry.content as List<int>);
      } else {
        await Directory(outPath).create(recursive: true);
      }
    }

    // Релизный zip содержит один корневой каталог (enitor-vX.Y.Z-windows/) —
    // копируем содержимое именно его, а не сам временный каталог.
    final children = tempDir.listSync();
    final sourceDir = children.length == 1 && children.first is Directory
        ? children.first as Directory
        : tempDir;

    // Проверяем ДО того, как закрыть приложение: битый/неполный архив не
    // должен привести к тихому «фейковому успеху» — xcopy без нужных файлов
    // просто ничего не скопирует, а bat-скрипт после этого молча
    // перезапустит СТАРУЮ версию, и никто не узнает, что обновление не
    // применилось.
    final newExe = File(p.join(sourceDir.path, exeName));
    if (!await newExe.exists()) {
      throw Exception('Update archive is missing $exeName');
    }

    final batPath = p.join(tempDir.path, 'enitor_update.bat');
    await File(batPath).writeAsString(windowsUpdateScript);
    // Пути — аргументами, а не текстом скрипта: cmd читает .bat в кодировке
    // OEM, и кириллица в пути (C:\Users\Иван\…) превращалась в мусор.
    // Командная строка процесса — UTF-16, %~1 приходит целым.
    await Process.start(
      'cmd',
      [
        '/c',
        batPath,
        exeName,
        sourceDir.path,
        installDir.path,
        tempDir.path,
      ],
      mode: ProcessStartMode.detached,
    );
    // Освобождаем файлы exe/dll, чтобы xcopy выше мог их перезаписать.
    exit(0);
  }
}

/// Скрипт замены файлов: %1 — имя exe, %2 — откуда, %3 — куда, %4 —
/// временная папка. Ждёт закрытия приложения, копирует (с повторами:
/// антивирус может ненадолго держать exe) и запускает новую версию; если
/// скопировать так и не вышло — запускает старую с [kUpdateFailedArg].
const windowsUpdateScript = r'''
@echo off
:waitloop
tasklist /FI "IMAGENAME eq %~1" 2>NUL | find /I "%~1" >NUL
if not errorlevel 1 (
  timeout /t 1 /nobreak >NUL
  goto waitloop
)
set tries=0
:copy
xcopy "%~2" "%~3" /E /H /Y /I >NUL
if not errorlevel 1 goto ok
set /a tries+=1
if %tries% geq 5 goto failed
timeout /t 2 /nobreak >NUL
goto copy
:failed
start "" "%~3\%~1" --update-failed
exit /b 1
:ok
start "" "%~3\%~1"
rmdir /S /Q "%~4"
''';

final updateServiceProvider = Provider<UpdateService>(
  (ref) => UpdateService(ref.read(localStorageProvider)),
);
