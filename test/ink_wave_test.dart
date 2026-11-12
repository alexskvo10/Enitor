import 'dart:math' as math;

import 'package:enitor/core/theme/app_theme.dart';
import 'package:enitor/core/theme/ink_wave.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('обе темы берут InkWave и без серой pressed-подсветки', () {
    for (final t in [AppTheme.light(), AppTheme.dark()]) {
      expect(t.splashFactory, same(InkWave.splashFactory));
      expect(t.highlightColor, Colors.transparent);
    }
  });

  test('coverRadius — до дальнего угла', () {
    const r = Rect.fromLTWH(0, 0, 200, 50);
    expect(
      InkWave.coverRadius(r, const Offset(10, 10)),
      closeTo(math.sqrt(190 * 190 + 40 * 40) + 1, 1e-9),
    );
    expect(
      InkWave.coverRadius(r, const Offset(190, 45)),
      closeTo(math.sqrt(190 * 190 + 45 * 45) + 1, 1e-9),
    );
  });

  Future<RenderBox> pumpTile(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Center(
          child: Material(
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {},
              child: const SizedBox(width: 200, height: 50),
            ),
          ),
        ),
      ),
    );
    return tester.renderObject<RenderBox>(find.byType(InkWell));
  }

  RenderObject material(WidgetTester tester) => tester.allRenderObjects
      .firstWhere((r) => r.runtimeType.toString() == '_RenderInkFeatures');

  testWidgets('держу — волна из точки касания закрывает плитку и стоит',
      (tester) async {
    final box = await pumpTile(tester);
    final origin = box.localToGlobal(Offset.zero);
    final g = await tester.startGesture(origin + const Offset(10, 10));
    await tester.pump(const Duration(milliseconds: 150)); // tapDown
    await tester.pump(const Duration(seconds: 2)); // держу долго
    final cover = InkWave.coverRadius(Offset.zero & box.size, const Offset(10, 10));
    expect(
      material(tester),
      paints
        ..clipRRect(
          rrect: RRect.fromRectAndRadius(
            Offset.zero & box.size,
            const Radius.circular(12),
          ),
        )
        ..circle(x: 10, y: 10, radius: cover),
    );

    await g.up();
    await tester.pump(const Duration(milliseconds: 100));
    expect(material(tester), paints..circle()); // гаснет плавно, не рывком
    await tester.pump(InkWave.fadeOut);
    expect(material(tester), paintsExactlyCountTimes(#drawCircle, 0));
  });

  testWidgets('отмена — быстро тает', (tester) async {
    final box = await pumpTile(tester);
    final g = await tester.startGesture(box.localToGlobal(const Offset(100, 25)));
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump(const Duration(milliseconds: 16)); // кадр проявления
    expect(material(tester), paints..circle(x: 100, y: 25));
    await g.cancel();
    await tester.pump();
    await tester.pump(InkWave.cancelFade);
    expect(material(tester), paintsExactlyCountTimes(#drawCircle, 0));
  });

  testWidgets('быстрый тап — дорастает до краёв и гаснет', (tester) async {
    final box = await pumpTile(tester);
    await tester.tapAt(box.localToGlobal(const Offset(190, 40)));
    await tester.pump();
    await tester.pump(InkWave.tapGrow);
    final cover = InkWave.coverRadius(Offset.zero & box.size, const Offset(190, 40));
    expect(material(tester), paints..circle(x: 190, y: 40, radius: cover));
    await tester.pump(const Duration(milliseconds: 16)); // угасание — со след. кадра
    await tester.pump(InkWave.fadeOut);
    expect(material(tester), paintsExactlyCountTimes(#drawCircle, 0));
  });
}
