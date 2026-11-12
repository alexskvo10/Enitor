import 'package:enitor/data/sources/local/local_storage.dart';
import 'package:enitor/features/integrations/core/secret_store.dart';
import 'package:enitor/features/integrations/sync/sync_client.dart';
import 'package:enitor/features/integrations/sync/sync_service.dart';
import 'package:enitor/features/integrations/ui/server_section.dart';
import 'package:enitor/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ui_matrix.dart';

// Раздел «Свой сервер»: без подключения — кнопка «Подключить»; подключённый —
// адрес, состояние, журнал; ошибки подключения — текстом. Служба подменена
// фейком, который наследует SyncService и читает настройки из хранилища.

class _FakeSync extends SyncService {
  _FakeSync(Ref ref) : super(ref);

  SyncException? connectError;
  int syncCalls = 0;
  int disconnectCalls = 0;
  final connects = <String>[];

  @override
  Future<void> connect({
    required String url,
    required String token,
    required bool takeServer,
  }) async {
    connects.add('$url|$token|$takeServer');
    final e = connectError;
    if (e != null) throw e;
  }

  List<SyncDevice>? deviceList;

  @override
  Future<List<SyncDevice>?> devices() async => deviceList;

  @override
  Future<void> syncNow() async => syncCalls++;

  @override
  Future<void> disconnect() async => disconnectCalls++;
}

void main() {
  late ProviderContainer container;
  late _FakeSync fake;

  setUp(() async {
    await initializeDateFormatting('ru');
    await initializeDateFormatting('en');
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    container = ProviderContainer(
      overrides: [
        localStorageProvider.overrideWithValue(LocalStorage(prefs)),
        secretStoreProvider
            .overrideWithValue(SecretStore(MemorySecretBackend())),
        syncServiceProvider.overrideWith((ref) => _FakeSync(ref)),
      ],
    );
    fake = container.read(syncServiceProvider) as _FakeSync;
  });
  tearDown(() => container.dispose());

  Widget scoped(Widget child) => UncontrolledProviderScope(
        container: container,
        child: child,
      );

  Widget app(Widget child) => scoped(
        MaterialApp(
          locale: const Locale('ru'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(child: child),
          ),
        ),
      );

  /// Телефонный экран: диалог подключения с кнопкой внизу помещается целиком.
  Future<void> openConnectDialog(WidgetTester tester) async {
    tester.view.physicalSize = const Size(412, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(const ServerSection()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Подключить сервер'));
    await tester.pumpAndSettle();
  }

  /// Записать состояние «подключён» и два обмена в журнале.
  Future<void> seedConnected() async {
    final storage = container.read(localStorageProvider);
    await storage.writeMap(
      kSyncSettingsKey,
      SyncSettings(
        url: 'https://enitor.example.test',
        deviceId: 'dev-1',
        lastSyncAt: DateTime(2026, 10, 27, 9, 5),
      ).toJson(),
    );
    await storage.writeList(kSyncLogKey, [
      SyncLogEntry(at: DateTime(2026, 10, 27, 9, 5), sent: 2, received: 3)
          .toJson(),
      SyncLogEntry(
        at: DateTime(2026, 10, 27, 8, 0),
        error: 'Not an Enitor server reply',
      ).toJson(),
      SyncLogEntry(
        at: DateTime(2026, 10, 27, 7, 0),
        error: 'Server did not answer in time',
        code: 'network',
      ).toJson(),
    ]);
  }

  testWidgets('без подключения: кнопка «Подключить сервер» и сноска',
      (tester) async {
    await tester.pumpWidget(app(const ServerSection()));
    await tester.pumpAndSettle();
    expect(find.text('Подключить сервер'), findsOneWidget);
    expect(find.textContaining('хранит задачи'), findsOneWidget);
    expect(find.text('Синхронизировать сейчас'), findsNothing);
    expect(find.text('Журнал обменов'), findsNothing);
  });

  testWidgets('подключён: адрес, состояние, кнопки и журнал', (tester) async {
    await seedConnected();
    await tester.pumpWidget(app(const ServerSection()));
    await tester.pumpAndSettle();
    expect(find.text('https://enitor.example.test'), findsOneWidget);
    expect(find.textContaining('Синхронизировано:'), findsOneWidget);
    expect(find.text('Синхронизировать сейчас'), findsOneWidget);
    expect(find.text('Отключить'), findsOneWidget);
    expect(find.text('↑2 ↓3'), findsOneWidget);
    expect(find.text('Not an Enitor server reply'), findsOneWidget);
    expect(find.text('Очистить журнал'), findsOneWidget);
    expect(find.text('Подключить сервер'), findsNothing);
    // Ошибка с кодом — на языке интерфейса, не исходным английским текстом.
    expect(find.text('Сервер не отвечает. Проверь адрес и сеть'), findsOneWidget);
    expect(find.text('Server did not answer in time'), findsNothing);

    await tester.tap(find.text('Синхронизировать сейчас'));
    await tester.pumpAndSettle();
    expect(fake.syncCalls, 1);
  });

  testWidgets('устройства: это — первым, значки по виду, планшет по-русски',
      (tester) async {
    await seedConnected();
    fake.deviceList = const [
      SyncDevice(id: 'a', name: 'Android tablet'),
      SyncDevice(id: 'b', name: 'Android'),
      SyncDevice(id: 'c', name: ''),
      SyncDevice(id: 'dev-1', name: 'Windows · my tablet'),
    ];
    await tester.pumpWidget(app(const ServerSection()));
    await tester.pumpAndSettle();

    Icon iconOf(String text) => tester.widget<Icon>(
          find.descendant(
            of: find.ancestor(
              of: find.text(text),
              matching: find.byType(ListTile),
            ),
            matching: find.byType(Icon),
          ).first,
        );
    expect(iconOf('Android · планшет').icon, Icons.tablet_android_rounded);
    expect(iconOf('Android').icon, Icons.smartphone_rounded);
    expect(iconOf('Устройство без имени').icon, Icons.devices_other_rounded);
    // «tablet» в имени компьютера — не планшет и не переводится.
    expect(iconOf('Windows · my tablet').icon, Icons.computer_rounded);
    final titles = tester
        .widgetList<ListTile>(find.byType(ListTile))
        .map((t) => t.title is Text ? (t.title! as Text).data : null)
        .toList();
    expect(
      titles.indexOf('Windows · my tablet'),
      lessThan(titles.indexOf('Android · планшет')),
    );
  });

  testWidgets('журнал свёрнут до трёх записей', (tester) async {
    await seedConnected();
    await container.read(localStorageProvider).writeList(kSyncLogKey, [
      for (var i = 0; i < 5; i++)
        SyncLogEntry(at: DateTime(2026, 10, 27, 9, i), sent: i, received: 0)
            .toJson(),
    ]);
    await tester.pumpWidget(app(const ServerSection()));
    await tester.pumpAndSettle();
    expect(find.text('↑3 ↓0'), findsNothing);
    await tester.tap(find.text('Показать все (5)'));
    await tester.pumpAndSettle();
    expect(find.text('↑3 ↓0'), findsOneWidget);
    expect(find.text('Свернуть'), findsOneWidget);
  });

  testWidgets('пустой журнал — строка «Обменов ещё не было»', (tester) async {
    await container.read(localStorageProvider).writeMap(
          kSyncSettingsKey,
          const SyncSettings(url: 'https://enitor.example.test').toJson(),
        );
    await tester.pumpWidget(app(const ServerSection()));
    await tester.pumpAndSettle();
    expect(find.text('Обменов ещё не было'), findsOneWidget);
    expect(find.text('Ещё не синхронизировано'), findsOneWidget);
    expect(find.text('Очистить журнал'), findsNothing);
  });

  testWidgets('отключение: подтверждение, потом обмен прекращается',
      (tester) async {
    await seedConnected();
    await tester.pumpWidget(app(const ServerSection()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Отключить'));
    await tester.pumpAndSettle();
    expect(
      find.text('Данные останутся на устройстве, обмен прекратится.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
    expect(fake.disconnectCalls, 0);

    await tester.tap(find.text('Отключить'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Отключить').last);
    await tester.pumpAndSettle();
    expect(fake.disconnectCalls, 1);
  });

  testWidgets('ошибка unauthorized из connect показывается текстом',
      (tester) async {
    fake.connectError =
        const SyncException('unauthorized', 'Wrong token', status: 401);
    await openConnectDialog(tester);
    await tester.enterText(
      find.byType(TextField).at(0),
      'https://enitor.example.test',
    );
    await tester.enterText(find.byType(TextField).at(1), 'secret-token');
    await tester.tap(find.text('Подключить'));
    await tester.pumpAndSettle();
    expect(find.text('Сервер не принял токен'), findsOneWidget);
    expect(fake.connects, ['https://enitor.example.test|secret-token|false']);
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('неверный адрес отклоняется без запроса к службе',
      (tester) async {
    await openConnectDialog(tester);
    await tester.enterText(find.byType(TextField).at(0), 'not a url');
    await tester.enterText(find.byType(TextField).at(1), 'token');
    await tester.tap(find.text('Подключить'));
    await tester.pumpAndSettle();
    expect(find.text('Это не похоже на адрес — проверь его'), findsOneWidget);
    expect(fake.connects, isEmpty);
  });

  testWidgets('http:// — только после предупреждения', (tester) async {
    await openConnectDialog(tester);
    await tester.enterText(
      find.byType(TextField).at(0),
      'http://192.168.1.5:8080',
    );
    await tester.enterText(find.byType(TextField).at(1), 'token');
    await tester.tap(find.text('Подключить'));
    await tester.pumpAndSettle();
    expect(find.text('Незащищённая ссылка'), findsOneWidget);
    // Две «Отмена»: у предупреждения и у диалога подключения — верхняя первая.
    await tester.tap(find.text('Отмена').last);
    await tester.pumpAndSettle();
    expect(fake.connects, isEmpty);
  });

  testWidgets('успешное подключение передаёт выбор «заменить»', (tester) async {
    await openConnectDialog(tester);
    await tester.enterText(
      find.byType(TextField).at(0),
      'https://enitor.example.test',
    );
    await tester.enterText(find.byType(TextField).at(1), 'token');
    await tester
        .tap(find.text('Заменить данные этого устройства данными сервера'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Подключить'));
    await tester.pumpAndSettle();
    expect(fake.connects, ['https://enitor.example.test|token|true']);
    expect(find.text('Подключить сервер'), findsOneWidget);
  });

  uiMatrixTest(
    'UI-матрица: не подключён',
    () => scoped(const SingleChildScrollView(child: ServerSection())),
  );

  testWidgets('UI-матрица: подключён, с журналом', (tester) async {
    await seedConnected();
    await runUiMatrix(
      tester,
      () => scoped(const SingleChildScrollView(child: ServerSection())),
    );
  });
}
