import 'package:enitor/core/theme/app_theme.dart';
import 'package:enitor/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

// «UI-матрица»: один виджет прогоняется по всем сочетаниям тема × язык ×
// ширина × масштаб текста и проверяется на типовые UI-поломки:
//   • исключения рендера (переполнение RenderFlex и т.п.);
//   • текст, обрезанный многоточием (если его нет в allowedEllipsis);
//   • цели касания меньше 48×48 (Android) и без подписи;
//   • контраст текста;
//   • (опционально) слишком широкое содержимое на широком экране.
//
// Сочетания: 2 темы × 2 языка × ширины 360/412/900/1280 (высота 800) ×
// масштаб текста 1.0 и 1.3, а на 360 ещё 2.0 — 36 прогонов на один виджет.
//
// Проверка одной точки возвращает список нарушений, а не падает сама:
// так self-тест может убедиться, что помощник действительно что-то находит.

const _widths = [360.0, 412.0, 900.0, 1280.0];
const _height = 800.0;
const _maxContentWidth = 720.0;

/// Одна точка матрицы. [describe] — человекочитаемое место для сообщений.
class _UiPoint {
  const _UiPoint({
    required this.dark,
    required this.locale,
    required this.width,
    required this.textScale,
  });

  final bool dark;
  final Locale locale;
  final double width;
  final double textScale;

  String describe() =>
      'тема ${dark ? 'тёмная' : 'светлая'}, '
      'язык ${locale.languageCode}, '
      'ширина ${width.toInt()}, '
      'масштаб ${textScale.toStringAsFixed(1)}';
}

Iterable<_UiPoint> _matrixPoints() sync* {
  for (final dark in [false, true]) {
    for (final locale in const [Locale('ru'), Locale('en')]) {
      for (final width in _widths) {
        final scales = width == 360 ? [1.0, 1.3, 2.0] : [1.0, 1.3];
        for (final scale in scales) {
          yield _UiPoint(
            dark: dark,
            locale: locale,
            width: width,
            textScale: scale,
          );
        }
      }
    }
  }
}

/// Проверяет одну точку матрицы и возвращает список нарушений (пустой — всё ок).
Future<List<String>> _checkPoint(
  WidgetTester tester,
  Widget Function() build,
  _UiPoint point, {
  required Set<String> allowedEllipsis,
  required bool checkPageWidth,
}) async {
  final where = point.describe();
  final violations = <String>[];
  final semantics = tester.ensureSemantics();

  try {
    tester.view.physicalSize = Size(point.width, _height);
    tester.view.devicePixelRatio = 1.0;

    final root = build();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: point.dark ? ThemeMode.dark : ThemeMode.light,
        locale: point.locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(point.textScale),
          ),
          child: child!,
        ),
        // Отступ нужен: guideline по цели касания пропускает узлы, касающиеся
        // края вьюпорта (там их могут обрезать), то есть виджет в углу не
        // проверился бы вообще. Фон Scaffold явный: у приложения он прозрачный
        // (фон рисует AppBackground), а контраст без непрозрачного фона не
        // вычислить.
        home: Builder(
          builder: (context) => Scaffold(
            backgroundColor: Theme.of(context).colorScheme.surface,
            body: Padding(padding: const EdgeInsets.all(16), child: root),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // a) Исключения при отрисовке (переполнение и прочее).
    final exception = tester.takeException();
    if (exception != null) {
      violations.add('$where: исключение при отрисовке: $exception');
    }

    // b) Текст, обрезанный многоточием.
    final paragraphs = tester.renderObjectList<RenderParagraph>(
      find.byType(RichText),
    );
    for (final paragraph in paragraphs) {
      if (!paragraph.didExceedMaxLines) continue;
      final text = paragraph.text.toPlainText();
      if (!allowedEllipsis.contains(text)) {
        violations.add('$where: текст обрезан многоточием: «$text»');
      }
    }

    // c, d, e) Цели касания, подписи и контраст.
    final guidelines = <String, AccessibilityGuideline>{
      'цель касания Android (48×48)': androidTapTargetGuideline,
      'подпись цели касания': labeledTapTargetGuideline,
      'контраст текста': textContrastGuideline,
    };
    for (final entry in guidelines.entries) {
      final result = await entry.value.evaluate(tester);
      if (!result.passed) {
        violations.add('$where: ${entry.key}: ${result.reason}');
      }
    }

    // f) Ширина содержимого на широком экране.
    if (checkPageWidth && point.width >= 900) {
      final contentWidth = tester.getSize(find.byWidget(root)).width;
      if (contentWidth > _maxContentWidth) {
        violations.add(
          '$where: ширина содержимого ${contentWidth.toInt()} px больше '
          '${_maxContentWidth.toInt()} px',
        );
      }
    }
  } finally {
    semantics.dispose();
  }

  return violations;
}

/// Прогоняет всю матрицу и возвращает все нарушения с указанием точки.
/// Пустой список — виджет прошёл проверки во всех точках.
Future<List<String>> collectUiMatrixViolations(
  WidgetTester tester,
  Widget Function() build, {
  Set<String> allowedEllipsis = const {},
  bool checkPageWidth = false,
}) async {
  addTearDown(tester.view.reset);
  final violations = <String>[];

  for (final point in _matrixPoints()) {
    try {
      violations.addAll(
        await _checkPoint(
          tester,
          build,
          point,
          allowedEllipsis: allowedEllipsis,
          checkPageWidth: checkPageWidth,
        ),
      );
    } catch (error) {
      // Например, pumpAndSettle не дождался покоя. Сообщение всё равно
      // должно сказать, в какой точке это случилось.
      violations.add('${point.describe()}: $error');
    }
  }

  return violations;
}

/// Прогоняет матрицу и падает, если найдено хоть одно нарушение.
Future<void> runUiMatrix(
  WidgetTester tester,
  Widget Function() build, {
  Set<String> allowedEllipsis = const {},
  bool checkPageWidth = false,
}) async {
  final violations = await collectUiMatrixViolations(
    tester,
    build,
    allowedEllipsis: allowedEllipsis,
    checkPageWidth: checkPageWidth,
  );
  expect(
    violations,
    isEmpty,
    reason: 'Нарушения UI-матрицы:\n${violations.join('\n')}',
  );
}

/// Готовый testWidgets поверх [runUiMatrix].
void uiMatrixTest(
  String description,
  Widget Function() build, {
  Set<String> allowedEllipsis = const {},
  bool checkPageWidth = false,
}) {
  testWidgets(description, (tester) {
    return runUiMatrix(
      tester,
      build,
      allowedEllipsis: allowedEllipsis,
      checkPageWidth: checkPageWidth,
    );
  });
}
