import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:enitor/widgets/productivity_ring.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// Кольцо рисуется SweepGradient со сдвинутым началом: дуга стартует сверху,
/// то есть на -90°. Skia же считает угол точки в диапазоне [0°, 360°) и только
/// потом переводит его в позицию градиента как (angle - start) / (end - start).
/// Для верхней четверти круга (270°..360°) это даёт долю больше единицы, её
/// зажимает TileMode.clamp — и первые 25% дуги заливаются одним плоским
/// цветом, а на трёх часах цвет скачком догоняет градиент. Это и есть «шов».
///
/// Тест рисует кольцо в картинку и щупает цвет вдоль дуги: если на четверти
/// пути цвет не сдвинулся с начального, значит участок зажат.

void main() {
  const size = 240.0;
  const stroke = 20.0;
  const start = Color(0xFFFF0000); // красный
  const end = Color(0xFF0000FF);   // синий

  /// Цвет пикселя на середине толщины кольца, на доле [f] пути от верха
  /// по часовой стрелке.
  int blueAt(ByteData px, int w, double f) {
    const c = size / 2;
    const r = (size - stroke) / 2;
    final a = 2 * math.pi * f;
    final x = (c + r * math.sin(a)).round();
    final y = (c - r * math.cos(a)).round();
    return px.getUint8((y * w + x) * 4 + 2); // B в RGBA
  }

  testWidgets('градиент кольца идёт от самого верха, без шва на четверти',
      (tester) async {
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: RepaintBoundary(
              key: key,
              child: const ProductivityRing(
                value: 1,
                size: size,
                strokeWidth: stroke,
                duration: Duration.zero,
                ringColors: [start, end],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;

    // Снимок обязателен внутри runAsync: у testWidgets время поддельное, и
    // Future от toImage() под ним не завершается никогда — тест просто виснет.
    late ByteData px;
    late int w;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1);
      px = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      w = image.width;
      image.dispose();
    });

    final atTop = blueAt(px, w, 0.001);
    final atEighth = blueAt(px, w, 0.125);
    final atQuarter = blueAt(px, w, 0.25);
    final atHalf = blueAt(px, w, 0.5);

    // Общая проверка направления: от красного к синему.
    expect(
      atHalf,
      greaterThan(atTop + 100),
      reason: 'на половине пути кольцо должно стать заметно синее',
    );

    // Ключевое: восьмая часть пути обязана лежать МЕЖДУ верхом и четвертью.
    // При зажатом участке atTop == atEighth — ровно этот баг и ловим.
    expect(
      atEighth,
      greaterThan(atTop + 8),
      reason: 'первая четверть залита плоским цветом: градиент зажат '
          'TileMode.clamp, потому что начало градиента не совпало с началом дуги',
    );
    expect(
      atEighth,
      lessThan(atQuarter - 8),
      reason: 'переход должен быть плавным, без скачка на четверти',
    );
  });
}
