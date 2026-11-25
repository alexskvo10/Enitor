import 'package:enitor/features/tour/tour.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Экскурсия подсвечивает элемент по ключу. В длинном списке далёкий
/// элемент ещё не построен — у ключа нет контекста, и рамка оставалась на
/// прошлом шаге (у человека с длинным списком задач и в настройках).
void main() {
  Future<BuildContext?> reveal(WidgetTester tester, GlobalKey key) async {
    BuildContext? result;
    var done = false;
    revealTarget(key).then((c) {
      result = c;
      done = true;
    });
    for (var i = 0; i < 100 && !done; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(done, isTrue, reason: 'поиск должен закончиться');
    return result;
  }

  Widget list(ScrollController c, GlobalKey key, int keyAt) => MaterialApp(
        home: Scaffold(
          body: ListView.builder(
            controller: c,
            itemCount: 300,
            itemBuilder: (_, i) => SizedBox(
              key: i == keyAt ? key : null,
              height: 60,
              child: Text('строка $i'),
            ),
          ),
        ),
      );

  testWidgets('элемент далеко внизу: список докручивается до него',
      (tester) async {
    final key = GlobalKey();
    final c = ScrollController();
    await tester.pumpWidget(list(c, key, 250));
    expect(key.currentContext, isNull, reason: 'ещё не построен');

    final ctx = await reveal(tester, key);
    expect(ctx, isNotNull);
    expect(c.offset, greaterThan(0));
  });

  testWidgets('экран прокручен вниз, элемент наверху — находится',
      (tester) async {
    final key = GlobalKey();
    final c = ScrollController();
    await tester.pumpWidget(list(c, key, 2));
    c.jumpTo(c.position.maxScrollExtent);
    await tester.pump();
    expect(key.currentContext, isNull, reason: 'выпал из запаса');

    expect(await reveal(tester, key), isNotNull);
  });

  testWidgets('элемента нет вовсе — прокрутка возвращается на место',
      (tester) async {
    final key = GlobalKey();
    final c = ScrollController();
    await tester.pumpWidget(list(c, key, -1));
    c.jumpTo(1234);
    await tester.pump();

    expect(await reveal(tester, key), isNull);
    expect(c.offset, 1234);
  });

  testWidgets('скрытый экран (тикеры выключены) не листается', (tester) async {
    final key = GlobalKey();
    final c = ScrollController();
    await tester.pumpWidget(
      TickerMode(enabled: false, child: list(c, key, 250)),
    );

    expect(await reveal(tester, key), isNull);
    expect(c.offset, 0);
  });
}
