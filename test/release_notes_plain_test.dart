import 'package:flutter_test/flutter_test.dart';
import 'package:enitor/services/update_service.dart';

// Диалог обновления рисует заметки простым Text. Пока в начале заметок стоял
// заголовок, это сходило с рук; стоило поставить баннер — и пользователю
// вывалился сырой <img ...> с длинным URL вместо описания релиза.

void main() {
  test('картинка-баннер в начале не попадает в текст', () {
    const raw = '<img width="2560" height="1280" alt="Enitor v0.2.0 — the '
        'first release that feels finished." '
        'src="https://github.com/user-attachments/assets/326831b4" />\n\n'
        '# Enitor v0.2.0 — The first release that feels finished\n\n'
        'Calm on purpose.';
    final s = releaseNotesToPlainText(raw)!;
    expect(s, startsWith('Enitor v0.2.0'));
    expect(s, isNot(contains('<img')));
    expect(s, isNot(contains('src=')));
    expect(s, isNot(contains('githubusercontent')));
    expect(s, isNot(contains('#')));
    expect(s, endsWith('Calm on purpose.'));
  });

  test('ссылки превращаются в свой текст, картинки markdown исчезают', () {
    final s = releaseNotesToPlainText(
      '![banner](https://example.com/a.png)\n'
      'See the [full changelog](https://example.com/compare) for details.',
    )!;
    expect(s, 'See the full changelog for details.');
  });

  test('заголовки, цитаты, линейки и жирный убираются', () {
    final s = releaseNotesToPlainText(
      '## Fixed\n\n'
      '---\n\n'
      '> **If you use an antivirus**, add `enitor.exe` to its trusted list.\n',
    )!;
    expect(s, 'Fixed\n\nIf you use an antivirus, add enitor.exe to its '
        'trusted list.');
  });

  test('пустота после вырезанного схлопывается', () {
    final s = releaseNotesToPlainText(
      '<img src="a" />\n\n\n\n<img src="b" />\n\n\n\nТекст.',
    )!;
    expect(s, 'Текст.');
  });

  test('заметки только из картинки дают null, а не пустое окно', () {
    expect(releaseNotesToPlainText('<img src="a" />'), isNull);
    expect(releaseNotesToPlainText('   \n\n  '), isNull);
    expect(releaseNotesToPlainText(null), isNull);
  });

  test('обычный текст не портится', () {
    const raw = 'Enitor treats a day as ending at 4:00 AM, not midnight.';
    expect(releaseNotesToPlainText(raw), raw);
  });
}
