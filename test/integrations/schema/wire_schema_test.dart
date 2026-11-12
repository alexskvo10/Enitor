import 'dart:convert';
import 'dart:io';

import 'package:enitor/data/models/goal.dart';
import 'package:enitor/data/models/task.dart';
import 'package:enitor/data/repositories/goal_repository.dart';
import 'package:enitor/data/repositories/schedule_repository.dart';
import 'package:enitor/data/repositories/task_repository.dart';
import 'package:enitor/data/sources/local/local_storage.dart';
import 'package:enitor/features/integrations/core/command_handler.dart';
import 'package:enitor/features/integrations/core/integration_command.dart';
import 'package:enitor/features/integrations/core/integration_gateway.dart';
import 'package:enitor/features/integrations/core/integration_settings.dart';
import 'package:enitor/features/integrations/webhooks/webhooks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:json_schema/json_schema.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Настоящие ответы обработчика и настоящие события вебхуков проходят схемы:
// reply.schema.json, task.schema.json, schedule-item.schema.json,
// event.schema.json.

final _now = DateTime(2026, 10, 25, 12);
const _today = '2026-10-25';

Map<String, dynamic> _read(String name) =>
    jsonDecode(File('docs/integrations/schema/$name').readAsStringSync())
        as Map<String, dynamic>;

JsonSchema _schema(String name) => JsonSchema.create(_read(name));

List<String> _problems(JsonSchema schema, Object? instance) => [
      for (final e in schema.validate(instance).errors) e.toString(),
    ];

void main() {
  late ProviderContainer container;
  late IntegrationGateway gateway;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    final storage = LocalStorage(await SharedPreferences.getInstance());
    container = ProviderContainer(
      overrides: [
        localStorageProvider.overrideWithValue(storage),
        commandHandlerProvider.overrideWith(
          (ref) => CommandHandler(
            tasks: ref.watch(taskRepositoryProvider),
            schedule: ref.watch(scheduleRepositoryProvider),
            storage: ref.watch(localStorageProvider),
            settings: () => ref.read(integrationSettingsProvider),
            clock: () => _now,
          ),
        ),
        integrationGatewayProvider
            .overrideWith((ref) => IntegrationGateway(ref, clock: () => _now)),
      ],
    );
    gateway = container.read(integrationGatewayProvider);
  });
  tearDown(() => container.dispose());

  /// Кадр канала Windows с командой; ответ разбирается и возвращается как Map.
  Future<Map<String, dynamic>> send(
    Map<String, Object?> request, {
    String source = 'cli',
  }) async {
    final frame = jsonEncode({
      'v': 1,
      'kind': 'command',
      'source': source,
      'request': request,
    });
    return jsonDecode(await gateway.receivePipe(frame)) as Map<String, dynamic>;
  }

  Future<void> allow(CommandSource s) => container
      .read(integrationSettingsProvider.notifier)
      .setPermission(s, const SourcePermission(add: true, read: true));

  group('ответы обработчика проходят reply.schema.json', () {
    final reply = _schema('reply.schema.json');

    test('ping', () async {
      final raw = await gateway.receivePipe(jsonEncode({'v': 1, 'kind': 'ping'}));
      final decoded = jsonDecode(raw);
      expect(_problems(reply, decoded), isEmpty);
      expect(decoded['ok'], isTrue);
    });

    test('успешный add_task: result.task — Task по task.schema.json', () async {
      await allow(CommandSource.cli);
      final decoded = await send({
        'v': 1,
        'command': 'add_task',
        'idempotencyKey': 'wire-1',
        'args': {
          'title': 'Молоко',
          'date': _today,
          'priority': 'high',
          'tags': ['home'],
          'description': 'Два пакета',
        },
      });
      expect(_problems(reply, decoded), isEmpty);
      expect(decoded['ok'], isTrue);
      final task = (decoded['result'] as Map<String, dynamic>)['task'];
      expect(_problems(_schema('task.schema.json'), task), isEmpty);
    });

    test('успешный add_schedule_item: result.item — по schedule-item.schema.json',
        () async {
      await allow(CommandSource.cli);
      final decoded = await send({
        'v': 1,
        'command': 'add_schedule_item',
        'args': {
          'title': 'Физика',
          'date': _today,
          'start': '09:00',
          'end': '10:30',
          'location': 'Room 214',
        },
      });
      expect(_problems(reply, decoded), isEmpty);
      final item = (decoded['result'] as Map<String, dynamic>)['item'];
      expect(_problems(_schema('schedule-item.schema.json'), item), isEmpty);
    });

    test('успешный complete_task: result.task с done true', () async {
      await allow(CommandSource.cli);
      final task = await container
          .read(taskRepositoryProvider)
          .createAndAdd(title: 'Позвонить', date: _now);
      final decoded = await send({
        'v': 1,
        'command': 'complete_task',
        'args': {'id': task.id.substring(0, 8)},
      });
      expect(_problems(reply, decoded), isEmpty);
      final done = (decoded['result'] as Map<String, dynamic>)['task'] as Map<String, dynamic>;
      expect(_problems(_schema('task.schema.json'), done), isEmpty);
      expect(done['done'], isTrue);
    });

    test('успешный list_today: tasks и schedule проходят свои схемы', () async {
      await allow(CommandSource.cli);
      await send({
        'v': 1,
        'command': 'add_task',
        'args': {'title': 'Для списка', 'date': _today, 'start': '08:00'},
      });
      await send({
        'v': 1,
        'command': 'add_schedule_item',
        'args': {'title': 'Встреча', 'date': _today, 'start': '11:00'},
      });
      final decoded = await send({
        'v': 1,
        'command': 'list_today',
        'args': {'date': _today},
      });
      expect(_problems(reply, decoded), isEmpty);
      final result = decoded['result'] as Map<String, dynamic>;
      final tasks = result['tasks'] as List<dynamic>;
      final schedule = result['schedule'] as List<dynamic>;
      expect(tasks, isNotEmpty);
      expect(schedule, isNotEmpty);
      for (final t in tasks) {
        expect(_problems(_schema('task.schema.json'), t), isEmpty);
      }
      for (final s in schedule) {
        expect(_problems(_schema('schedule-item.schema.json'), s), isEmpty);
      }
    });

    test('отказ forbidden — error без result', () async {
      final decoded = await send(
        {'v': 1, 'command': 'add_task', 'args': {'title': 'Нельзя', 'date': _today}},
        source: 'mcp',
      );
      expect(_problems(reply, decoded), isEmpty);
      expect(decoded['ok'], isFalse);
      expect((decoded['error'] as Map<String, dynamic>)['code'], 'forbidden');
    });

    test('отказ invalid_args — error с field', () async {
      await allow(CommandSource.cli);
      final decoded = await send({'v': 1, 'command': 'add_task', 'args': <String, Object?>{}});
      expect(_problems(reply, decoded), isEmpty);
      final error = decoded['error'] as Map<String, dynamic>;
      expect(error['code'], 'invalid_args');
      expect(error['field'], 'title');
    });
  });

  group('события вебхуков проходят event.schema.json', () {
    final event = _schema('event.schema.json');

    String body(WebhookEvent type, Map<String, Object?> data, String recordId) =>
        webhookBody(
          type: type,
          eventId: webhookEventId(recordId, type),
          at: _now,
          data: data,
        );

    test('task.completed — настоящий Task после отметки', () async {
      final tasks = container.read(taskRepositoryProvider);
      final t = await tasks.createAndAdd(title: 'Позвонить маме', date: _now, priority: TaskPriority.high);
      await tasks.toggleCompleted(t);
      final done = tasks.taskById(t.id)!;
      final text = body(
        WebhookEvent.taskCompleted,
        {'task': taskToWire(done)},
        done.id,
      );
      expect(_problems(event, jsonDecode(text)), isEmpty);
    });

    test('day.closed — день, где все задачи выполнены', () async {
      final day = DateTime(2026, 10, 27);
      final tasks = container.read(taskRepositoryProvider);
      final t = await tasks.createAndAdd(title: 'Единственная', date: day);
      await tasks.toggleCompleted(t);
      final data = dayClosedData(day, tasks.tasksForDay(day));
      expect(data, isNotNull, reason: 'день должен быть закрыт');
      final decoded = jsonDecode(body(WebhookEvent.dayClosed, data!, formatYmd(day)));
      expect(_problems(event, decoded), isEmpty);
    });

    test('goal.achieved — настоящая цель', () async {
      final goal = await container.read(goalRepositoryProvider).addGoal(
            title: 'Пробежать 2 км',
            period: GoalPeriod.month,
            year: 2026,
            month: 10,
            targetCount: 2,
          );
      final text = body(
        WebhookEvent.goalAchieved,
        {'goal': goalToWire(goal)},
        goal.id,
      );
      expect(_problems(event, jsonDecode(text)), isEmpty);
    });

    test('ping — пустой data', () {
      final decoded = jsonDecode(body(WebhookEvent.ping, const {}, 'ping'));
      expect(_problems(event, decoded), isEmpty);
    });
  });
}
