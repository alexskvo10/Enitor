import 'package:enitor/core/theme/app_theme.dart';
import 'package:enitor/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// Помощники golden-снимков. Снимки делаются на Windows и в CI не запускаются
// (см. dart_test.yaml), поэтому тесты с ними помечены тегом golden.
//
// Путь эталона: matchesGoldenFile считает путь ОТНОСИТЕЛЬНО папки того
// `*_test.dart`, из которого вызван (comparator ищет его по стеку вызовов).
// Helper сам — не `_test.dart`, поэтому относительный путь идёт от файла теста.
// Все эталоны лежат рядом с тестом: test/goldens/*.png для тестов в test/goldens/.

const _fontFiles = <String, List<String>>{
  'Inter': [
    'assets/fonts/Inter-Regular.ttf',
    'assets/fonts/Inter-Medium.ttf',
  ],
  'Manrope': [
    'assets/fonts/Manrope-Regular.ttf',
    'assets/fonts/Manrope-Bold.ttf',
  ],
  // Иконки Material: без шрифта на снимках вместо них квадраты.
  'MaterialIcons': ['fonts/MaterialIcons-Regular.otf'],
  'SourceSerif4': [
    'assets/fonts/SourceSerif4-Regular.ttf',
    'assets/fonts/SourceSerif4-SemiBold.ttf',
    'assets/fonts/SourceSerif4-Bold.ttf',
    'assets/fonts/SourceSerif4-Italic.ttf',
  ],
};

bool _fontsLoaded = false;

/// Грузит шрифты проекта из assets/fonts. Без этого в тестах вместо текста
/// рисуются чёрные прямоугольники (шрифт Ahem). Идемпотентно. Кэшируется
/// флаг, а не Future: Future из зоны прошлого теста в следующем тесте
/// никогда не завершится, и тест повиснет.
Future<void> loadAppFonts() async {
  if (_fontsLoaded) return;
  await _loadFonts();
  _fontsLoaded = true;
}

Future<void> _loadFonts() async {
  for (final entry in _fontFiles.entries) {
    final loader = FontLoader(entry.key);
    for (final path in entry.value) {
      loader.addFont(rootBundle.load(path));
    }
    await loader.load();
  }
}

/// Снимает экран [child] в MaterialApp с темой приложения и сравнивает с эталоном.
/// Имя файла эталона: `<name>-<light|dark>-<width>-<lang>.png`.
Future<void> expectGoldenScreen(
  WidgetTester tester,
  Widget child, {
  required String name,
  required bool dark,
  required double width,
  Locale locale = const Locale('ru'),
}) async {
  await loadAppFonts();

  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          backgroundColor: Theme.of(context).colorScheme.surface,
          body: Padding(padding: const EdgeInsets.all(16), child: child),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  final file = '$name-${dark ? 'dark' : 'light'}-'
      '${width.toInt()}-${locale.languageCode}.png';
  await expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile(file),
  );
}
