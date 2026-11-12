import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' as intl;

import '../../../core/utils/date_utils.dart';
import '../../../data/models/schedule_item.dart';
import '../../../data/models/task.dart';
import '../../../data/repositories/schedule_repository.dart';
import '../../../data/repositories/task_repository.dart';
import '../../../data/sources/local/local_storage.dart';
import '../../../l10n/app_localizations.dart';
import 'integration_command.dart';
import 'integration_settings.dart';

/// Ответы на ключи идемпотентности (ключ «устройство», не в бэкап).
const kIdempotencyKey = 'device.integrations.idempotency';

/// Сколько хранится ответ на ключ идемпотентности.
const kIdempotencyTtl = Duration(days: 7);

/// Ответ на команду — то, что уйдёт в Tasker, консоль или MCP.
class CommandReply {
  const CommandReply.ok(this.result, {this.warnings = const []}) : error = null;

  const CommandReply.fail(this.error, {this.warnings = const []})
      : result = null;

  final Map<String, Object?>? result;
  final CommandError? error;
  final List<String> warnings;

  bool get ok => error == null;

  Map<String, Object?> toJson(AppLocalizations l10n) => {
        'v': kCommandFormatVersion,
        'ok': ok,
        if (ok) 'result': result,
        if (!ok)
          'error': {
            'code': error!.code.wire,
            'message': commandErrorText(error!, l10n),
            if (error!.field != null) 'field': error!.field,
          },
        'warnings': warnings,
      };

  factory CommandReply.fromJson(Map<String, Object?> j) {
    final warnings =
        (j['warnings'] as List?)?.whereType<String>().toList() ?? const [];
    if (j['ok'] == true) {
      return CommandReply.ok(
        (j['result'] as Map?)?.cast<String, Object?>() ?? const {},
        warnings: warnings,
      );
    }
    final e = (j['error'] as Map?)?.cast<String, Object?>() ?? const {};
    final code = CommandErrorCode.values
            .where((c) => c.wire == e['code'])
            .firstOrNull ??
        CommandErrorCode.internal;
    return CommandReply.fail(
      CommandError(code, field: e['field'] as String?),
      warnings: warnings,
    );
  }
}

/// Человеческий текст ошибки на языке приложения.
String commandErrorText(CommandError e, AppLocalizations l10n) {
  final field = e.field ?? '';
  return switch (e.code) {
    CommandErrorCode.invalidArgs => switch (e.problem) {
        FieldProblem.missing => l10n.cmdErrMissing(field),
        FieldProblem.tooLong => l10n.cmdErrTooLong(field),
        FieldProblem.outOfRange => l10n.cmdErrOutOfRange(field),
        FieldProblem.endBeforeStart => l10n.cmdErrEndBeforeStart,
        FieldProblem.badFormat || null => l10n.cmdErrBadFormat(field),
      },
    CommandErrorCode.unknownCommand => l10n.cmdErrUnknownCommand,
    CommandErrorCode.unsupportedVersion => l10n.cmdErrUnsupportedVersion,
    CommandErrorCode.forbidden => l10n.cmdErrForbidden,
    CommandErrorCode.badKey => l10n.cmdErrBadKey,
    CommandErrorCode.notFound => l10n.cmdErrNotFound,
    CommandErrorCode.internal => l10n.cmdErrInternal,
  };
}

/// Локализация вне дерева виджетов — тем же способом, что в BackupService.
AppLocalizations currentL10n() =>
    lookupAppLocalizations(Locale(intl.Intl.defaultLocale ?? 'ru'));

Map<String, Object?> taskToWire(Task t) => {
      'id': t.id,
      'title': t.title,
      if (t.description != null) 'description': t.description,
      'date': formatYmd(t.date),
      if (t.startMinutes != null) 'start': formatHm(t.startMinutes!),
      if (t.endMinutes != null) 'end': formatHm(t.endMinutes!),
      'priority': t.priority.name,
      'tags': t.tags,
      'done': t.isCompleted,
    };

Map<String, Object?> scheduleToWire(ScheduleItem i, DateTime day) => {
      'id': i.id,
      'title': i.title,
      'date': formatYmd(day),
      'start': formatHm(i.startMinutes),
      if (i.endMinutes != null) 'end': formatHm(i.endMinutes!),
      if (i.location != null) 'location': i.location,
      if (i.note != null) 'note': i.note,
    };

/// Единственный путь, которым внешние входы меняют данные. Пишет только
/// через репозитории — те же вызовы, что у ручного добавления, поэтому
/// уведомления, статистика и экраны обновляются сами (app.dart слушает
/// потоки репозиториев).
///
/// Анкету подтверждения для недоверенных входов показывает UI
/// ([CommandInbox]); сюда такие команды приходят уже после «Сохранить» —
/// через ту же анкету, мимо обработчика, — либо отклоняются.
class CommandHandler {
  CommandHandler({
    required TaskRepository tasks,
    required ScheduleRepository schedule,
    required LocalStorage storage,
    required IntegrationSettings Function() settings,
    DateTime Function()? clock,
  })  : _tasks = tasks,
        _schedule = schedule,
        _storage = storage,
        _settings = settings,
        _clock = clock ?? DateTime.now;

  final TaskRepository _tasks;
  final ScheduleRepository _schedule;
  final LocalStorage _storage;
  final IntegrationSettings Function() _settings;
  final DateTime Function() _clock;

  /// Выполняет команду доверенного входа. Недоверенные (ссылка,
  /// «Поделиться») сюда не попадают: им — только анкета.
  Future<CommandReply> execute(IntegrationCommand c) async {
    if (c.source.trust == CommandTrust.untrusted || !_settings().allows(c)) {
      return CommandReply.fail(
        const CommandError(CommandErrorCode.forbidden),
        warnings: c.warnings,
      );
    }
    final key = c.idempotencyKey == null
        ? null
        : '${c.source.name}:${c.name}:${c.idempotencyKey}';
    if (key != null) {
      final prev = _readIdempotent(key);
      if (prev != null) return prev;
    }
    CommandReply reply;
    try {
      reply = await _run(c);
    } catch (_) {
      reply = const CommandReply.fail(CommandError(CommandErrorCode.internal));
    }
    // Запоминаем только успех: неудачную попытку с тем же ключом можно
    // повторить, когда причина исправлена (включили право, поправили поле).
    if (key != null && reply.ok) await _writeIdempotent(key, reply);
    return reply;
  }

  Future<CommandReply> _run(IntegrationCommand c) async {
    switch (c) {
      case AddTask():
        final t = await _tasks.createAndAdd(
          title: c.title,
          description: c.description,
          date: c.date,
          startMinutes: c.startMinutes,
          endMinutes: c.endMinutes,
          priority: c.priority,
          tags: c.tags,
        );
        return CommandReply.ok({'task': taskToWire(t)}, warnings: c.warnings);
      case AddScheduleItem():
        final i = await _schedule.create(
          title: c.title,
          date: c.date,
          startMinutes: c.startMinutes,
          endMinutes: c.endMinutes,
          location: c.location,
          note: c.note,
        );
        return CommandReply.ok(
          {'item': scheduleToWire(i, c.date)},
          warnings: c.warnings,
        );
      case CompleteTask():
        final found = _findTask(c.id);
        if (found == null) {
          return CommandReply.fail(
            const CommandError(CommandErrorCode.notFound),
            warnings: c.warnings,
          );
        }
        await _complete(found);
        final now = _tasks.taskById(found.id) ?? found;
        return CommandReply.ok({'task': taskToWire(now)}, warnings: c.warnings);
      case ListToday():
        final day = c.date ?? effectiveDay(_clock());
        // Задачи из правил повторения материализуются при открытии дня —
        // так же, как когда этот день открывает пользователь.
        await _tasks.ensureRecurrencesForDay(day);
        return CommandReply.ok(
          {
            'date': formatYmd(day),
            'tasks': [for (final t in _tasks.tasksForDay(day)) taskToWire(t)],
            'schedule': [
              for (final i in _schedule.forDay(day)) scheduleToWire(i, day),
            ],
          },
          warnings: c.warnings,
        );
      case OpenScreen():
        // Открытие экрана — дело UI; обработчик только подтверждает.
        return CommandReply.ok(
          {'screen': c.target.name},
          warnings: c.warnings,
        );
    }
  }

  /// Полный id или однозначный префикс. Неоднозначный — как «не найдено»:
  /// угадывать, какую из задач отметить, нельзя.
  Task? _findTask(String id) {
    final exact = _tasks.taskById(id);
    if (exact != null) return exact;
    final matches =
        _tasks.allTasks.where((t) => t.id.startsWith(id)).toList();
    return matches.length == 1 ? matches.single : null;
  }

  /// Отмечает выполненной тем же путём, что галочка в списке. Уже
  /// выполненную не трогаем: повтор команды не должен снимать отметку.
  Future<void> _complete(Task t) async {
    if (t.isCompleted) return;
    if (t.isChecklist) {
      await _tasks.setAllSubtasksDone(t, true);
    } else if (t.isCounter) {
      await _tasks.setCounterProgress(t, t.targetCount!);
    } else {
      await _tasks.toggleCompleted(t);
    }
  }

  CommandReply? _readIdempotent(String key) {
    final all = _storage.readMap(kIdempotencyKey) ?? const {};
    final e = all[key];
    if (e is! Map<String, dynamic>) return null;
    final at = DateTime.tryParse(e['at'] as String? ?? '');
    if (at == null || _clock().difference(at) > kIdempotencyTtl) return null;
    return CommandReply.fromJson(
      (e['reply'] as Map).cast<String, Object?>(),
    );
  }

  Future<void> _writeIdempotent(String key, CommandReply reply) async {
    final now = _clock();
    final all = Map<String, dynamic>.of(
      _storage.readMap(kIdempotencyKey) ?? const {},
    )..removeWhere((_, v) {
        final at = v is Map ? DateTime.tryParse(v['at'] as String? ?? '') : null;
        return at == null || now.difference(at) > kIdempotencyTtl;
      });
    all[key] = {
      'at': now.toIso8601String(),
      'reply': {
        'ok': true,
        'result': reply.result,
        'warnings': reply.warnings,
      },
    };
    await _storage.writeMap(kIdempotencyKey, all);
  }
}

final commandHandlerProvider = Provider<CommandHandler>(
  (ref) => CommandHandler(
    tasks: ref.watch(taskRepositoryProvider),
    schedule: ref.watch(scheduleRepositoryProvider),
    storage: ref.watch(localStorageProvider),
    settings: () => ref.read(integrationSettingsProvider),
  ),
);
