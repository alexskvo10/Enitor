import 'package:enitor/features/integrations/windows/link_registration.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('кириллица из reg query в чужой кодировке — тот же путь', () {
    // «Загрузки» в cp866, прочитанные как cp1251.
    expect(
      regTextEquals(
        r'"C:\Users\Ђ€ђг§Єў\enitor.exe" "%1"',
        r'"C:\Users\Загрузк\enitor.exe" "%1"',
      ),
      isTrue,
    );
    expect(
      regTextEquals(r'"C:\Old\enitor.exe" "%1"', r'"C:\New\enitor.exe" "%1"'),
      isFalse,
    );
  });
}
