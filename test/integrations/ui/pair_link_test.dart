import 'dart:async';

import 'package:enitor/features/integrations/inbox/inbox_host.dart';
import 'package:enitor/features/integrations/sync/lan/lan_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

// Ссылка `enitor://pair…`: открытый экран синхронизации забирает её сам —
// второй экран поверх не открывается (иначе окно «Подключиться?» оказалось
// бы под ним и всплывало потом, на «Назад»).

/// Как экран синхронизации: забирает ссылку, как только она пришла.
class _Taker extends ConsumerWidget {
  const _Taker();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void take() => ref.read(lanPairLinkProvider.notifier).state = null;
    ref.listen(lanPairLinkProvider, (_, next) {
      if (next != null) take();
    });
    // Ссылка пришла до того, как экран построился.
    if (ref.read(lanPairLinkProvider) != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => take());
    }
    return const Text('sync');
  }
}

void main() {
  late ProviderContainer container;
  late GoRouter router;
  var syncBuilt = 0;

  setUp(() {
    container = ProviderContainer();
    syncBuilt = 0;
  });
  tearDown(() => container.dispose());

  Future<void> pump(WidgetTester tester, String initial) async {
    router = GoRouter(
      initialLocation: initial,
      routes: [
        // Как в приложении: приёмная — в оболочке вкладок, экран
        // синхронизации — поверх неё.
        ShellRoute(
          builder: (_, __, child) => InboxHost(child: child),
          routes: [GoRoute(path: '/', builder: (_, __) => const Text('home'))],
        ),
        GoRoute(
          path: '/settings/sync',
          builder: (_, __) {
            syncBuilt++;
            return const _Taker();
          },
        ),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  void link() => container.read(lanPairLinkProvider.notifier).state =
      Uri.parse('enitor://pair?code=GERHE0VBNZGF');

  testWidgets('экран синхронизации открыт — второй поверх не открывается',
      (tester) async {
    // Как в приложении: экран открыт переходом, а не стартовым адресом.
    await pump(tester, '/');
    unawaited(router.push('/settings/sync'));
    await tester.pumpAndSettle();
    expect(syncBuilt, 1);
    link();
    await tester.pumpAndSettle();
    expect(container.read(lanPairLinkProvider), isNull);
    expect(syncBuilt, 1);
  });

  testWidgets('экран не открыт — открывается и забирает ссылку', (tester) async {
    await pump(tester, '/');
    link();
    await tester.pumpAndSettle();
    expect(find.text('sync'), findsOneWidget);
    expect(container.read(lanPairLinkProvider), isNull);
  });
}
