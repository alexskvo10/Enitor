@TestOn('windows')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:enitor/cli/cli.dart';
import 'package:enitor/cli/mcp.dart';
import 'package:enitor/cli/transport.dart';
import 'package:enitor/data/repositories/task_repository.dart';
import 'package:enitor/data/sources/local/local_storage.dart';
import 'package:enitor/features/integrations/core/integration_command.dart';
import 'package:enitor/features/integrations/core/integration_gateway.dart';
import 'package:enitor/features/integrations/core/integration_settings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Сквозной путь Windows: enitor-cli (настоящий клиент канала) → именованный
// канал → приёмная → обработчик → задача. Сервер канала в тесте — на
// dart:ffi в отдельном изоляте, по тому же протоколу, что раннер на C++
// (кадр «4 байта длины + JSON»); C++-сервер проверяется ручной проверкой.

typedef _CreateNative = IntPtr Function(
  Pointer<Uint16>,
  Uint32,
  Uint32,
  Uint32,
  Uint32,
  Uint32,
  Uint32,
  Pointer<Void>,
);
typedef _Create = int Function(
  Pointer<Uint16>,
  int,
  int,
  int,
  int,
  int,
  int,
  Pointer<Void>,
);
typedef _HandleNative = Int32 Function(IntPtr, Pointer<Void>);
typedef _Handle = int Function(int, Pointer<Void>);
typedef _IoNative = Int32 Function(
  IntPtr,
  Pointer<Uint8>,
  Uint32,
  Pointer<Uint32>,
  Pointer<Void>,
);
typedef _Io = int Function(int, Pointer<Uint8>, int, Pointer<Uint32>, Pointer<Void>);
typedef _OneNative = Int32 Function(IntPtr);
typedef _One = int Function(int);
typedef _AllocNative = Pointer<Uint8> Function(Uint32, IntPtr);
typedef _Alloc = Pointer<Uint8> Function(int, int);

/// Сервер одного соединения за раз: читает кадр, отдаёт его главному
/// изоляту, пишет ответ. [requests] — сколько соединений обслужить.
Future<void> _serve((String, SendPort, int) args) async {
  final (name, toMain, requests) = args;
  final k = DynamicLibrary.open('kernel32.dll');
  final create = k.lookupFunction<_CreateNative, _Create>('CreateNamedPipeW');
  final connect = k.lookupFunction<_HandleNative, _Handle>('ConnectNamedPipe');
  final read = k.lookupFunction<_IoNative, _Io>('ReadFile');
  final write = k.lookupFunction<_IoNative, _Io>('WriteFile');
  final flush = k.lookupFunction<_OneNative, _One>('FlushFileBuffers');
  final disconnect = k.lookupFunction<_OneNative, _One>('DisconnectNamedPipe');
  final close = k.lookupFunction<_OneNative, _One>('CloseHandle');
  final alloc = k.lookupFunction<_AllocNative, _Alloc>('LocalAlloc');

  final path = '\\\\.\\pipe\\$name';
  final wide = alloc(0x40, (path.length + 1) * 2).cast<Uint16>();
  for (var i = 0; i < path.length; i++) {
    wide[i] = path.codeUnitAt(i);
  }
  final buf = alloc(0x40, 70000);
  final got = alloc(0x40, 4).cast<Uint32>();
  final fromMain = ReceivePort();
  final replies = StreamIterator(fromMain);
  toMain.send(fromMain.sendPort);

  for (var n = 0; n < requests; n++) {
    // PIPE_ACCESS_DUPLEX, PIPE_TYPE_BYTE | PIPE_WAIT | REJECT_REMOTE_CLIENTS.
    final h = create(wide, 3, 0x8, 1, 70000, 70000, 0, nullptr);
    toMain.send('listening');
    connect(h, nullptr);
    var have = 0;
    int need() => have < 4
        ? 4
        : 4 + (buf[0] | buf[1] << 8 | buf[2] << 16 | buf[3] << 24);
    while (have < need()) {
      if (read(h, buf + have, need() - have, got, nullptr) == 0 ||
          got.value == 0) {
        break;
      }
      have += got.value;
    }
    final body = utf8.decode([for (var i = 4; i < have; i++) buf[i]]);
    toMain.send(body);
    await replies.moveNext();
    final reply = replies.current as List<int>;
    final frame = [
      reply.length & 0xFF,
      reply.length >> 8 & 0xFF,
      reply.length >> 16 & 0xFF,
      reply.length >> 24 & 0xFF,
      ...reply,
    ];
    for (var i = 0; i < frame.length; i++) {
      buf[i] = frame[i];
    }
    write(h, buf, frame.length, got, nullptr);
    flush(h);
    disconnect(h);
    close(h);
  }
  fromMain.close();
}

void main() {
  late ProviderContainer container;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    container = ProviderContainer(
      overrides: [
        localStorageProvider.overrideWithValue(
          LocalStorage(await SharedPreferences.getInstance()),
        ),
      ],
    );
  });
  tearDown(() => container.dispose());

  /// Поднимает сервер на [requests] соединений; запросы обслуживает
  /// настоящая приёмная приложения.
  Future<String> startServer(int requests) async {
    final name = 'Enitor-test-$pid-${DateTime.now().microsecondsSinceEpoch}';
    final fromServer = ReceivePort();
    final events = StreamIterator(fromServer);
    await Isolate.spawn(_serve, (name, fromServer.sendPort, requests));
    await events.moveNext();
    final toServer = events.current as SendPort;
    unawaited(() async {
      for (var n = 0; n < requests; n++) {
        await events.moveNext(); // listening
        await events.moveNext();
        final frame = events.current as String;
        final reply = await container
            .read(integrationGatewayProvider)
            .receivePipe(frame);
        toServer.send(utf8.encode(reply));
      }
      fromServer.close();
    }());
    // Дать серверу создать канал до первого подключения.
    await Future<void>.delayed(const Duration(milliseconds: 200));
    return name;
  }

  test('enitor-cli add → канал → обработчик → задача; код 0', () async {
    await container
        .read(integrationSettingsProvider.notifier)
        .setPermission(CommandSource.cli, const SourcePermission(add: true));
    final name = await startServer(1);
    final out = StringBuffer(), err = StringBuffer();
    final code = await runCli(
      ['add', 'Buy', 'milk', '--at', '18:00'],
      transport: WindowsPipeTransport(pipeName: name),
      out: out,
      err: err,
    );
    expect(code, 0, reason: '$err');
    final t = container.read(taskRepositoryProvider).allTasks.single;
    expect(t.title, 'Buy milk');
    expect(t.startMinutes, 18 * 60);
    expect(out.toString(), contains(t.id));
  });

  test('запрет в настройках → код 4, данные не изменились', () async {
    final name = await startServer(1);
    final err = StringBuffer();
    final code = await runCli(
      ['add', 'Nope'],
      transport: WindowsPipeTransport(pipeName: name),
      out: StringBuffer(),
      err: err,
    );
    expect(code, 4);
    expect(container.read(taskRepositoryProvider).allTasks, isEmpty);
  });

  test('канала нет → код 3', () async {
    final code = await runCli(
      ['today'],
      transport: WindowsPipeTransport(pipeName: 'Enitor-test-missing-$pid'),
      out: StringBuffer(),
      err: StringBuffer(),
    );
    expect(code, 3);
  });

  test('MCP → канал → обработчик; права выключены → инструмента нет', () async {
    await container.read(integrationSettingsProvider.notifier).setPermission(
          CommandSource.mcp,
          const SourcePermission(add: true),
        );
    final name = await startServer(2);
    final t = WindowsPipeTransport(pipeName: name);
    final server = McpServer(send: t.send);
    final list = await server.handleLine(
      '{"jsonrpc":"2.0","id":1,"method":"tools/list"}',
    );
    final tools = [
      for (final x in ((list!['result']! as Map)['tools'] as List))
        (x as Map)['name'],
    ];
    expect(tools, isNot(contains('list_today')));
    final call = await server.handleLine(
      '{"jsonrpc":"2.0","id":2,"method":"tools/call",'
      '"params":{"name":"add_task","arguments":{"title":"From MCP"}}}',
    );
    expect((call!['result']! as Map)['isError'], isFalse);
    expect(
      container.read(taskRepositoryProvider).allTasks.single.title,
      'From MCP',
    );
  });
}
