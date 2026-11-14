import 'dart:async';

import 'package:enitor/core/theme/app_theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Переход между экранами: старый и новый никогда не видны одновременно
// (иначе новый проявляется поверх старого), а сплошной заливки нет вовсе —
// между ними виден общий фон приложения.

/// Видимость виджета: произведение прозрачностей всех FadeTransition над ним.
double _opacity(WidgetTester tester, String text) {
  final el = tester.element(find.text(text, skipOffstage: false));
  var o = 1.0;
  el.visitAncestorElements((a) {
    final w = a.widget;
    if (w is FadeTransition) o *= w.opacity.value;
    return true;
  });
  return o;
}

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.windows]) {
    testWidgets('$platform: экраны не накладываются, без заливки',
        (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      final nav = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: nav,
          theme: AppTheme.light(),
          home: const Scaffold(body: Text('старый')),
        ),
      );
      unawaited(
        nav.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('новый')),
          ),
        ),
      );

      Future<void> walk() async {
        await tester.pump();
        for (var ms = 0; ms < 300; ms += 15) {
          await tester.pump(const Duration(milliseconds: 15));
          final a = _opacity(tester, 'старый');
          final b = _opacity(tester, 'новый');
          expect(a == 0 || b == 0, isTrue, reason: '$ms мс: $a и $b');
          // Ни одной непрозрачной заливки во время перехода.
          expect(
            find.byWidgetPredicate(
              (w) => w is ColoredBox && w.color.a > 0,
            ),
            findsNothing,
          );
        }
        await tester.pumpAndSettle();
      }

      await walk();
      expect(_opacity(tester, 'новый'), 1);
      nav.currentState!.pop();
      await walk();
      expect(_opacity(tester, 'старый'), 1);
      debugDefaultTargetPlatformOverride = null;
    });
  }
}
