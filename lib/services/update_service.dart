import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
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
  });

  final String name;
  final String downloadUrl;
  final int size;
}

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
            ))
        .toList();
    return ReleaseInfo(
      version: version,
      tagName: tag,
      htmlUrl: json['html_url'] as String? ?? '',
      notes: (json['body'] as String?)?.trim(),
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
      await _storage.writeMap(_prefsKey, {
        'lastCheckMs': DateTime.now().millisecondsSinceEpoch,
      });
      if (release == null) {
        return UpdateCheckResult(UpdateCheckStatus.error,
            currentVersion: info.version, error: 'no release found');
      }
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
    final client = http.Client();
    try {
      final req = http.Request('GET', Uri.parse(asset.downloadUrl));
      final res = await client.send(req);
      final total = res.contentLength ?? asset.size;
      final file = File(destPath);
      final sink = file.openWrite();
      var received = 0;
      await for (final chunk in res.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) onProgress?.call(received / total);
      }
      await sink.close();
      return destPath;
    } finally {
      client.close();
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
    final batContent = '''
@echo off
:waitloop
tasklist /FI "IMAGENAME eq $exeName" 2>NUL | find /I "$exeName" >NUL
if "%ERRORLEVEL%"=="0" (
  timeout /t 1 /nobreak >NUL
  goto waitloop
)
xcopy "${sourceDir.path}" "${installDir.path}" /E /H /Y /I >NUL
start "" "${p.join(installDir.path, exeName)}"
rmdir /S /Q "${tempDir.path}"
''';
    await File(batPath).writeAsString(batContent);
    await Process.start('cmd', ['/c', batPath],
        mode: ProcessStartMode.detached);
    // Освобождаем файлы exe/dll, чтобы xcopy выше мог их перезаписать.
    exit(0);
  }
}

final updateServiceProvider = Provider<UpdateService>(
  (ref) => UpdateService(ref.read(localStorageProvider)),
);
