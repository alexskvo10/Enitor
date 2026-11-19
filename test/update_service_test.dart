import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:enitor/services/update_service.dart';

void main() {
  group('проверка скачанного обновления', () {
    late File file;
    final bytes = List<int>.generate(1000, (i) => i % 251);
    setUp(() async {
      final dir = await Directory.systemTemp.createTemp('enitor_upd_test');
      file = File('${dir.path}/a.apk')..writeAsBytesSync(bytes);
      addTearDown(() => dir.delete(recursive: true));
    });
    ReleaseAsset asset({int? size, String? digest}) => ReleaseAsset(
          name: 'a.apk',
          downloadUrl: 'https://example.invalid/a.apk',
          size: size ?? bytes.length,
          digest: digest,
        );

    test('совпали размер и sha256 — принято', () async {
      await UpdateService.verifyDownload(
        file,
        asset(digest: 'sha256:${sha256.convert(bytes)}'),
      );
      await UpdateService.verifyDownload(file, asset()); // старый релиз
    });

    test('оборванный файл — отказ', () {
      expect(
        UpdateService.verifyDownload(file, asset(size: 2000)),
        throwsException,
      );
    });

    test('чужой хеш — отказ', () {
      expect(
        UpdateService.verifyDownload(
          file,
          asset(digest: 'sha256:${sha256.convert([1, 2, 3])}'),
        ),
        throwsException,
      );
    });
  });

  test('скрипт Windows: пути из аргументов, при неудаче — флаг', () {
    expect(windowsUpdateScript, contains(kUpdateFailedArg));
    expect(windowsUpdateScript, contains('xcopy "%~2" "%~3"'));
  });

  group('isNewerVersion', () {
    test('remote patch bump is newer', () {
      expect(isNewerVersion('0.1.1', '0.1.0'), isTrue);
    });

    test('remote minor/major bump is newer', () {
      expect(isNewerVersion('0.2.0', '0.1.9'), isTrue);
      expect(isNewerVersion('1.0.0', '0.9.9'), isTrue);
    });

    test('same version is not newer', () {
      expect(isNewerVersion('0.1.0', '0.1.0'), isFalse);
    });

    test('remote older is not newer', () {
      expect(isNewerVersion('0.1.0', '0.2.0'), isFalse);
    });

    test('build number after + is ignored', () {
      expect(isNewerVersion('0.1.0+5', '0.1.0+1'), isFalse);
    });

    test('missing components default to 0', () {
      expect(isNewerVersion('0.2', '0.1.9'), isTrue);
      expect(isNewerVersion('1', '0.9.9'), isTrue);
    });
  });
}
