import 'package:enitor/core/theme/app_theme.dart';
import 'package:enitor/core/theme/appearance.dart';
import 'package:enitor/data/sources/local/local_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Фон — отдельный слой: анимация экрана над ним (переход вкладок, волна)
// не должна его перерисовывать — иначе каждый кадр заново вся текстура.

Future<void> _pump(
  WidgetTester tester, {
  required int style,
  required bool dark,
  Widget child = const SizedBox.expand(),
}) async {
  SharedPreferences.setMockInitialValues({
    'appearance': '{"style":$style,"vignette":true,"themeMode":0}',
  });
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(), // новый стиль — новый контроллер оформления
      overrides: [localStorageProvider.overrideWithValue(LocalStorage(prefs))],
      child: MaterialApp(
        theme: dark ? AppTheme.dark() : AppTheme.light(),
        home: AppBackground(child: child),
      ),
    ),
  );
}

void main() {
  testWidgets('все стили в обеих темах рисуются без ошибок', (tester) async {
    for (final dark in [false, true]) {
      for (final style in BackgroundStyle.values) {
        await _pump(tester, style: style.index, dark: dark);
        expect(tester.takeException(), isNull, reason: '$style dark=$dark');
      }
    }
  });

  testWidgets('анимация над фоном его не перерисовывает', (tester) async {
    await _pump(
      tester,
      style: BackgroundStyle.paper.index,
      dark: false,
      child: const Center(child: CircularProgressIndicator()),
    );
    final boundary = tester
        .renderObject<RenderCustomPaint>(
          find.descendant(
            of: find.byType(AppBackground),
            matching: find.byWidgetPredicate(
              (w) => w is CustomPaint && w.painter != null,
            ),
          ).first,
        )
        .parent! as RenderRepaintBoundary;
    // Symmetric — слой перерисован вместе с родителем; когда готовый слой
    // просто переиспользуют, растёт только asymmetric.
    final before = boundary.debugSymmetricPaintCount;
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(
      boundary.debugSymmetricPaintCount,
      before,
    );
  });
}
