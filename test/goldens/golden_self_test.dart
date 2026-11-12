@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'golden_helpers.dart';

// Самопроверка golden-инфраструктуры: простая карточка с засемплённым шрифтом.
// Эталон: test/goldens/font_check-light-360-ru.png. Если он чёрно-белые
// прямоугольники вместо букв — шрифты не загрузились (см. loadAppFonts).
// Обновить эталон: flutter test --update-goldens --tags golden test/goldens/golden_self_test.dart

void main() {
  testWidgets('карточка с SourceSerif4 совпадает с эталоном', (tester) async {
    await expectGoldenScreen(
      tester,
      const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Проверка шрифтов',
            style: TextStyle(fontFamily: 'SourceSerif4', fontSize: 28),
          ),
        ),
      ),
      name: 'font_check',
      dark: false,
      width: 360,
    );
  });
}
