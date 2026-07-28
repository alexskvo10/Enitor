import 'package:flutter_test/flutter_test.dart';
import 'package:enitor/services/update_service.dart';

void main() {
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
