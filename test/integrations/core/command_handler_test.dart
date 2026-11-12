import 'dart:convert';

import 'package:enitor/core/utils/date_utils.dart';
import 'package:enitor/data/models/task.dart';
import 'package:enitor/data/repositories/schedule_repository.dart';
import 'package:enitor/data/repositories/task_repository.dart';
import 'package:enitor/data/sources/local/local_storage.dart';
import 'package:enitor/features/integrations/core/command_handler.dart';
import 'package:enitor/features/integrations/core/integration_command.dart';
import 'package:enitor/features/integrations/core/integration_gateway.dart';
import 'package:enitor/features/integrations/core/integration_settings.dart';
import 'package:enitor/features/integrations/core/secret_store.dart';
import 'package:enitor/features/integrations/inbox/command_inbox.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Обработчик команд — единственный путь, которым внешние входы меняют
// данные. Здесь — права, идемпотентность, отказы без побочных эффектов и
// приёмная (ключ Tasker, адресат ответа, кадры канала Windows).

final _now = DateTime(2026, 10, 25, 12);

void main() {
  late ProviderContainer container;
  late LocalStorage storage;
  late MemorySecretBackend secrets;
  var clock = _now;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    storage = LocalStorage(await SharedPreferences.getInstance());
    secrets = MemorySecretBackend();
    clock = _now;
    container = ProviderContainer(
      overrides: [
        localStorageProvider.overrideWithValue(storage),
        secretStoreProvider.overrideWithValue(SecretStore(secrets)),
        commandHandlerProvider.overrideWith(
          (ref) => CommandHandler(
            tasks: ref.watch(taskRepositoryProvider),
            schedule: ref.watch(scheduleRepositoryProvider),
            storage: ref.watch(localStorageProvider),
            settings: () => ref.read(integrationSettingsProvider),
            clock: () => clock,
          ),
        ),
        integrationGatewayProvider
            .overrideWith((ref) => IntegrationGateway(ref, clock: () => clock)),
      ],
    );
  });
  tearDown(() => container.dispose());

  CommandHandler handler() => container.read(commandHandlerProvider);
  TaskRepository tasks() => container.read(taskRepositoryProvider);

  Future<void> allow(CommandSource s, {bool add = true, bool read = true}) =>
      container
          .read(integrationSettingsProvider.notifier)
          .setPermission(s, SourcePermission(add: add, read: read));

  IntegrationCommand cmd(String json, CommandSource s) {
    final r = parseJsonCommand(json, source: s, now: _now);
    expect(r.error, isNull, reason: json);
    return r.command!;
  }

  const addTask =
      '{"command":"add_task","args":{"title":"Молоко","date":"2026-10-25"}}';
  const addItem = '{"command":"add_schedule_item","args":'
      '{"title":"Физика","date":"2026-10-26","start":"09:00","end":"10:30"}}';
  const listToday = '{"command":"list_today"}';

  group('права: команда × источник × включено/выключено', () {
    const keyed = [
      CommandSource.tasker,
      CommandSource.cli,
      CommandSource.mcp,
    ];
    for (final source in keyed) {
      for (final enabled in [true, false]) {
        test('${source.name}, ${enabled ? 'включено' : 'выключено'}',
            () async {
          await allow(source, add: enabled, read: enabled);
          final t = await tasks().createAndAdd(title: 'Есть', date: _now);
          final replies = [
            await handler().execute(cmd(addTask, source)),
            await handler().execute(cmd(addItem, source)),
            await handler().execute(
              cmd('{"command":"complete_task","args":{"id":"${t.id}"}}', source),
            ),
            await handler().execute(cmd(listToday, source)),
          ];
          for (final r in replies) {
            expect(r.ok, enabled, reason: '${source.name}: ${r.error}');
            if (!enabled) expect(r.error!.code, CommandErrorCode.forbidden);
          }
          expect(tasks().allTasks.length, enabled ? 2 : 1);
          expect(
            container.read(scheduleRepositoryProvider).all.length,
            enabled ? 1 : 0,
          );
          expect(tasks().taskById(t.id)!.isCompleted, enabled);
        });
      }
    }

    test('по умолчанию у Tasker, консоли и MCP всё выключено', () async {
      for (final s in keyed) {
        final r = await handler().execute(cmd(addTask, s));
        expect(r.error?.code, CommandErrorCode.forbidden, reason: s.name);
      }
    });

    test('добавлять — не значит читать', () async {
      await allow(CommandSource.cli, add: true, read: false);
      expect((await handler().execute(cmd(addTask, CommandSource.cli))).ok,
          isTrue,);
      final r = await handler().execute(cmd(listToday, CommandSource.cli));
      expect(r.error?.code, CommandErrorCode.forbidden);
    });

    test('ссылка и «Поделиться» мимо анкеты не выполняются никогда', () async {
      await allow(CommandSource.link);
      await allow(CommandSource.share);
      final link = parseLink('enitor://add?title=x', now: _now).command!;
      expect((await handler().execute(link)).error?.code,
          CommandErrorCode.forbidden,);
      expect(tasks().allTasks, isEmpty);
    });

    test('виджет может отмечать, но не читает', () async {
      final t = await tasks().createAndAdd(title: 'Есть', date: _now);
      final done = await handler().execute(
        cmd('{"command":"complete_task","args":{"id":"${t.id}"}}',
            CommandSource.widget,),
      );
      expect(done.ok, isTrue);
      final read =
          await handler().execute(cmd(listToday, CommandSource.widget));
      expect(read.error?.code, CommandErrorCode.forbidden);
    });
  });

  test('отказ без прав не меняет хранилище ни на байт', () async {
    await tasks().createAndAdd(title: 'Есть', date: _now);
    final before = jsonEncode(storage.snapshot());
    for (final json in [addTask, addItem, listToday]) {
      await handler().execute(cmd(json, CommandSource.tasker));
    }
    expect(jsonEncode(storage.snapshot()), before);
  });

  group('идемпотентность', () {
    const keyed = '{"command":"add_task","idempotencyKey":"k1",'
        '"args":{"title":"Молоко"}}';

    test('повтор с тем же ключом возвращает прежний ответ и ничего не создаёт',
        () async {
      await allow(CommandSource.cli);
      final a = await handler().execute(cmd(keyed, CommandSource.cli));
      final b = await handler().execute(cmd(keyed, CommandSource.cli));
      expect(a.ok, isTrue);
      expect(b.result, a.result);
      expect(tasks().allTasks.length, 1);
    });

    test('без ключа повтор создаёт вторую задачу — так задумано', () async {
      await allow(CommandSource.cli);
      await handler().execute(cmd(addTask, CommandSource.cli));
      await handler().execute(cmd(addTask, CommandSource.cli));
      expect(tasks().allTasks.length, 2);
    });

    test('ключи разных входов не пересекаются', () async {
      await allow(CommandSource.cli);
      await allow(CommandSource.mcp);
      await handler().execute(cmd(keyed, CommandSource.cli));
      await handler().execute(cmd(keyed, CommandSource.mcp));
      expect(tasks().allTasks.length, 2);
    });

    test('отказ не запоминается: после включения права ключ срабатывает',
        () async {
      final denied = await handler().execute(cmd(keyed, CommandSource.cli));
      expect(denied.ok, isFalse);
      await allow(CommandSource.cli);
      final ok = await handler().execute(cmd(keyed, CommandSource.cli));
      expect(ok.ok, isTrue);
      expect(tasks().allTasks.length, 1);
    });

    test('через 7 дней ключ забывается', () async {
      await allow(CommandSource.cli);
      await handler().execute(cmd(keyed, CommandSource.cli));
      clock = _now.add(const Duration(days: 7, minutes: 1));
      await handler().execute(cmd(keyed, CommandSource.cli));
      expect(tasks().allTasks.length, 2);
      // Просроченная запись вычищена, а не копится вечно.
      final stored = storage.readMap(kIdempotencyKey)!;
      expect(stored.length, 1);
    });

    test('ключ идемпотентности — ключ «устройство», не в бэкапе', () async {
      await allow(CommandSource.cli);
      await handler().execute(cmd(keyed, CommandSource.cli));
      expect(kIdempotencyKey.startsWith(kDeviceKeyPrefix), isTrue);
      expect(storage.snapshot().containsKey(kIdempotencyKey), isFalse);
    });
  });

  group('complete_task', () {
    setUp(() => allow(CommandSource.cli));

    Future<CommandReply> complete(String id) => handler().execute(
          cmd('{"command":"complete_task","args":{"id":"$id"}}',
              CommandSource.cli,),
        );

    test('по однозначному префиксу', () async {
      final t = await tasks().createAndAdd(title: 'A', date: _now);
      final r = await complete(t.id.substring(0, 8));
      expect(r.ok, isTrue);
      expect((r.result!['task'] as Map)['done'], isTrue);
    });

    test('неоднозначный префикс — «не найдено», ничего не отмечено', () async {
      for (final id in ['abcd-1', 'abcd-2']) {
        await tasks().addTask(
          Task(
            id: id,
            title: id,
            date: dateOnly(_now),
            createdAt: _now,
            updatedAt: _now,
          ),
        );
      }
      expect((await complete('abcd')).error?.code, CommandErrorCode.notFound);
      expect((await complete('zzzz')).error?.code, CommandErrorCode.notFound);
      expect(tasks().allTasks.where((t) => t.isCompleted), isEmpty);
      expect((await complete('abcd-2')).ok, isTrue);
    });

    test('повтор не снимает отметку', () async {
      final t = await tasks().createAndAdd(title: 'A', date: _now);
      await complete(t.id);
      await complete(t.id);
      expect(tasks().taskById(t.id)!.isCompleted, isTrue);
    });

    test('чек-лист и счётчик отмечаются целиком', () async {
      final list = await tasks().createAndAdd(
        title: 'Список',
        date: _now,
        subtaskTitles: ['a', 'b'],
      );
      final counter =
          await tasks().createAndAdd(title: 'Вода', date: _now, targetCount: 5);
      await complete(list.id);
      await complete(counter.id);
      expect(tasks().taskById(list.id)!.subtasks.every((s) => s.done), isTrue);
      expect(tasks().taskById(counter.id)!.progressCount, 5);
      expect(tasks().taskById(counter.id)!.isCompleted, isTrue);
    });

    test('выполнение даёт событие completedEvents — ровно одно', () async {
      final t = await tasks().createAndAdd(title: 'A', date: _now);
      final events = <String>[];
      final sub = tasks().completedEvents.listen((t) => events.add(t.id));
      await complete(t.id);
      await complete(t.id);
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      expect(events, [t.id]);
    });
  });

  test('list_today: задачи и расписание дня, до 4:00 — ещё вчера', () async {
    await allow(CommandSource.mcp);
    final yesterday = DateTime(2026, 10, 24);
    await tasks().createAndAdd(title: 'Вчера', date: yesterday);
    await tasks().createAndAdd(title: 'Сегодня', date: DateTime(2026, 10, 25));
    await container.read(scheduleRepositoryProvider).create(
          title: 'Пара',
          date: yesterday,
          startMinutes: 540,
        );
    clock = DateTime(2026, 10, 25, 1, 30);
    final r = await handler().execute(cmd(listToday, CommandSource.mcp));
    expect(r.result!['date'], '2026-10-24');
    expect(
      (r.result!['tasks'] as List).map((t) => (t as Map)['title']),
      ['Вчера'],
    );
    expect((r.result!['schedule'] as List).single, containsPair('start', '09:00'));
  });

  group('приёмная', () {
    IntegrationGateway gateway() => container.read(integrationGatewayProvider);

    Future<Map<String, Object?>> tasker(String? key, {String? reply}) =>
        gateway().receiveCommand(
          addTask,
          source: CommandSource.tasker,
          key: key,
          replyPackage: reply,
        );

    Map<String, Object?> decode(Map<String, Object?> out) =>
        jsonDecode(out['reply']! as String) as Map<String, Object?>;

    test('ключ Tasker: неверный, пустой, старый после перевыпуска, верный',
        () async {
      await allow(CommandSource.tasker);
      final store = container.read(secretStoreProvider);
      final key = await store.taskerKey();
      expect(decode(await tasker('wrong'))['ok'], isFalse);
      expect(decode(await tasker(''))['ok'], isFalse);
      expect(decode(await tasker(null))['ok'], isFalse);
      expect(
        (decode(await tasker('wrong'))['error']! as Map)['code'],
        'bad_key',
      );
      final fresh = await store.rotateTaskerKey();
      expect(decode(await tasker(key))['ok'], isFalse);
      expect(decode(await tasker(fresh))['ok'], isTrue);
      expect(tasks().allTasks.length, 1);
    });

    test('ответ уходит только разрешённому пакету', () async {
      await allow(CommandSource.tasker);
      final key = await container.read(secretStoreProvider).taskerKey();
      expect(
        (await tasker(key, reply: 'net.dinglisch.android.taskerm'))['replyTo'],
        'net.dinglisch.android.taskerm',
      );
      expect((await tasker(key, reply: 'com.evil.app'))['replyTo'], isNull);
      expect((await tasker(key))['replyTo'], isNull);
    });

    test('ссылка → в очередь анкет; битая → тост; выключенная → тост',
        () async {
      gateway().receiveLink('enitor://add?title=Молоко');
      gateway().receiveLink('https://example.com');
      await allow(CommandSource.link, add: false, read: false);
      gateway().receiveLink('enitor://add?title=x');
      final items = container.read(commandInboxProvider);
      expect(items[0], isA<InboxCommand>());
      expect(items[1], isA<InboxError>());
      expect(
        (items[2] as InboxError).error.code,
        CommandErrorCode.forbidden,
      );
      expect(tasks().allTasks, isEmpty);
    });

    test('кадры канала Windows', () async {
      await allow(CommandSource.cli);
      Future<Map<String, Object?>> pipe(String f) async =>
          jsonDecode(await gateway().receivePipe(f)) as Map<String, Object?>;
      expect((await pipe('{"v":1,"kind":"ping"}'))['ok'], isTrue);
      expect((await pipe('not json'))['ok'], isFalse);
      expect(
        ((await pipe('{"v":9,"kind":"ping"}'))['error']! as Map)['code'],
        'unsupported_version',
      );
      final added = await pipe(
        '{"v":1,"kind":"command","source":"cli","request":$addTask}',
      );
      expect(added['ok'], isTrue);
      // Незнакомый источник — как консоль, без повышения прав до MCP.
      final asCli = await pipe(
        '{"v":1,"kind":"command","source":"tasker","request":$listToday}',
      );
      expect(asCli['ok'], isTrue);
      await pipe('{"v":1,"kind":"link","url":"enitor://add?title=a"}');
      expect(container.read(commandInboxProvider).single, isA<InboxCommand>());
      expect(tasks().allTasks.length, 1);
    });

    test('канал платформы: метод link кладёт в очередь', () async {
      await gateway().handleCall(
        const MethodCall('link', {'url': 'enitor://open?screen=goals'}),
      );
      final item = container.read(commandInboxProvider).single as InboxCommand;
      expect((item.command as OpenScreen).target, OpenTarget.goals);
    });
  });

  test('дата по умолчанию — день приложения', () {
    final r = parseLink('enitor://add?title=a', now: DateTime(2026, 1, 1, 3));
    expect((r.command! as AddTask).date, effectiveDay(DateTime(2026, 1, 1, 3)));
  });
}
