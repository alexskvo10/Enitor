import 'dart:convert';

import '../../../core/utils/date_utils.dart';
import '../../../data/models/task.dart';

/// Откуда пришла команда. Источник решает две вещи: нужна ли анкета
/// подтверждения ([trust]) и какие права проверять (Интеграции → Права).
enum CommandSource { link, share, tasker, cli, mcp, widget }

/// `untrusted` — кто угодно мог подсунуть (ссылка на сайте, текст из чужого
/// приложения): только анкета, и только добавление. `keyed` — вход проверен
/// ключом (Tasker), каналом текущего пользователя (консоль, MCP) или это
/// наш же виджет.
enum CommandTrust { untrusted, keyed }

extension CommandSourceTrust on CommandSource {
  CommandTrust get trust => switch (this) {
        CommandSource.link || CommandSource.share => CommandTrust.untrusted,
        _ => CommandTrust.keyed,
      };
}

/// Экраны, которые можно открыть ссылкой `enitor://open?screen=…`.
enum OpenTarget { today, schedule, goals, settings, integrations }

/// Версия форматов ссылок и команд. Понимаем текущую и предыдущую
/// (`docs/integrations/formats.md`, «Versions»); предыдущей пока нет.
const kCommandFormatVersion = 1;

// Ограничения полей — те же, что в formats.md. Длинное отклоняем, а не
// режем: обрезанное название молча исказило бы задачу.
const kMaxTitle = 500;
const kMaxLongText = 5000;
const kMaxLocation = 500;
const kMaxTags = 10;
const kMaxTagLength = 40;
const kMaxIdempotencyKey = 100;
const kDateRangeYears = 5;

sealed class IntegrationCommand {
  const IntegrationCommand({
    required this.source,
    this.idempotencyKey,
    this.warnings = const [],
  });

  final CommandSource source;

  /// Повтор с тем же ключом за 7 дней возвращает прежний ответ.
  final String? idempotencyKey;

  /// Незнакомые поля: их не выбрасываем молча — анкета и ответ называют их.
  final List<String> warnings;

  /// Имя команды в формате (`add_task`, …). У [OpenScreen] — `open`.
  String get name;

  /// Команда только читает — для неё нужно право «читать», а не «добавлять».
  bool get isRead => false;
}

class AddTask extends IntegrationCommand {
  const AddTask({
    required super.source,
    required this.title,
    required this.date,
    this.description,
    this.startMinutes,
    this.endMinutes,
    this.priority = TaskPriority.none,
    this.tags = const [],
    super.idempotencyKey,
    super.warnings,
  });

  final String title;
  final String? description;
  final DateTime date;
  final int? startMinutes;
  final int? endMinutes;
  final TaskPriority priority;
  final List<String> tags;

  @override
  String get name => 'add_task';
}

class AddScheduleItem extends IntegrationCommand {
  const AddScheduleItem({
    required super.source,
    required this.title,
    required this.date,
    required this.startMinutes,
    this.endMinutes,
    this.location,
    this.note,
    super.idempotencyKey,
    super.warnings,
  });

  final String title;
  final DateTime date;
  final int startMinutes;
  final int? endMinutes;
  final String? location;
  final String? note;

  @override
  String get name => 'add_schedule_item';
}

class CompleteTask extends IntegrationCommand {
  const CompleteTask({
    required super.source,
    required this.id,
    super.idempotencyKey,
    super.warnings,
  });

  /// Полный id или однозначный префикс от 4 символов.
  final String id;

  @override
  String get name => 'complete_task';
}

class ListToday extends IntegrationCommand {
  const ListToday({
    required super.source,
    this.date,
    super.idempotencyKey,
    super.warnings,
  });

  /// null — «сегодня» по правилу приложения (до 4:00 — ещё вчера).
  final DateTime? date;

  @override
  String get name => 'list_today';

  @override
  bool get isRead => true;
}

class OpenScreen extends IntegrationCommand {
  const OpenScreen({
    required super.source,
    required this.target,
    super.warnings,
  });

  final OpenTarget target;

  @override
  String get name => 'open';
}

/// Коды ошибок — те же, что в formats.md.
enum CommandErrorCode {
  invalidArgs('invalid_args'),
  unknownCommand('unknown_command'),
  unsupportedVersion('unsupported_version'),
  forbidden('forbidden'),
  badKey('bad_key'),
  notFound('not_found'),
  internal('internal');

  const CommandErrorCode(this.wire);
  final String wire;
}

/// Почему поле не подошло — по нему UI подбирает человеческий текст.
enum FieldProblem { missing, tooLong, badFormat, outOfRange, endBeforeStart }

/// Ошибка — значение, не исключение: её показывают тостом или отдают
/// ответом, и ни один вход не падает от мусора на входе.
class CommandError {
  const CommandError(this.code, {this.field, this.problem});

  final CommandErrorCode code;

  /// Поле, которое не подошло (для [CommandErrorCode.invalidArgs]).
  final String? field;
  final FieldProblem? problem;

  @override
  String toString() =>
      'CommandError(${code.wire}${field == null ? '' : ', $field'}'
      '${problem == null ? '' : ', ${problem!.name}'})';
}

/// Итог разбора: ровно одно из двух.
typedef ParseResult = ({IntegrationCommand? command, CommandError? error});

ParseResult _fail(CommandErrorCode code, {String? field, FieldProblem? p}) =>
    (command: null, error: CommandError(code, field: field, problem: p));

ParseResult _ok(IntegrationCommand c) => (command: c, error: null);

/// Внутренний сигнал «поле не подошло» — ловится в [_build] и становится
/// [CommandError]. Наружу никогда не выходит.
class _Bad implements Exception {
  const _Bad(this.field, this.problem);
  final String field;
  final FieldProblem problem;
}

/// Ссылка `enitor://…` → команда. Источник — ссылка или (для плитки и
/// виджета, которые открывают ту же анкету) переданный [source].
ParseResult parseLink(
  String link, {
  required DateTime now,
  CommandSource source = CommandSource.link,
}) {
  final Uri uri;
  try {
    uri = Uri.parse(link.trim());
  } on FormatException {
    return _fail(
      CommandErrorCode.invalidArgs,
      field: 'link',
      p: FieldProblem.badFormat,
    );
  }
  if (uri.scheme.toLowerCase() != 'enitor') {
    return _fail(
      CommandErrorCode.invalidArgs,
      field: 'link',
      p: FieldProblem.badFormat,
    );
  }
  // `enitor://add?…` — действие в host; `enitor:add?…` — в path.
  final action = (uri.host.isNotEmpty ? uri.host : uri.path).toLowerCase();
  final Map<String, String> params;
  try {
    // queryParameters декодирует ровно один раз: `%2520` → текст `%20`.
    params = uri.queryParameters;
  } on FormatException {
    return _fail(
      CommandErrorCode.invalidArgs,
      field: 'link',
      p: FieldProblem.badFormat,
    );
  } on ArgumentError {
    return _fail(
      CommandErrorCode.invalidArgs,
      field: 'link',
      p: FieldProblem.badFormat,
    );
  }
  final version = params['v'];
  final args = Map<String, Object?>.of(params)..remove('v');
  final name = switch (action) {
    'add' => 'add_task',
    'schedule' => 'add_schedule_item',
    'open' => 'open',
    _ => null,
  };
  if (name == null) return _fail(CommandErrorCode.unknownCommand);
  // В ссылке описание задачи — короткое `desc`.
  if (name == 'add_task' && args.containsKey('desc')) {
    args['description'] = args.remove('desc');
  }
  return _build(
    name: name,
    version: version,
    args: args,
    source: source,
    idempotencyKey: null,
    now: now,
    // Ссылка без названия (плитка «+ задача», «+» на виджете) открывает
    // пустую анкету: сохранить её без названия всё равно нельзя.
    titleRequired: false,
  );
}

/// JSON-запрос (Tasker, консоль, MCP) → команда.
ParseResult parseJsonCommand(
  String json, {
  required CommandSource source,
  required DateTime now,
}) {
  final Object? decoded;
  try {
    decoded = jsonDecode(json);
  } on FormatException {
    return _fail(
      CommandErrorCode.invalidArgs,
      field: 'request',
      p: FieldProblem.badFormat,
    );
  }
  if (decoded is! Map<String, Object?>) {
    return _fail(
      CommandErrorCode.invalidArgs,
      field: 'request',
      p: FieldProblem.badFormat,
    );
  }
  return parseCommandMap(decoded, source: source, now: now);
}

ParseResult parseCommandMap(
  Map<String, Object?> request, {
  required CommandSource source,
  required DateTime now,
}) {
  final name = request['command'];
  // «Открыть экран» — действие ссылок, не команда: программам открывать
  // экраны в чужом окне незачем.
  if (name == 'open') return _fail(CommandErrorCode.unknownCommand);
  if (name is! String) {
    return _fail(
      CommandErrorCode.invalidArgs,
      field: 'command',
      p: FieldProblem.missing,
    );
  }
  final rawArgs = request['args'] ?? const <String, Object?>{};
  if (rawArgs is! Map<String, Object?>) {
    return _fail(
      CommandErrorCode.invalidArgs,
      field: 'args',
      p: FieldProblem.badFormat,
    );
  }
  final key = request['idempotencyKey'];
  if (key != null && key is! String) {
    return _fail(
      CommandErrorCode.invalidArgs,
      field: 'idempotencyKey',
      p: FieldProblem.badFormat,
    );
  }
  if (key is String && key.length > kMaxIdempotencyKey) {
    return _fail(
      CommandErrorCode.invalidArgs,
      field: 'idempotencyKey',
      p: FieldProblem.tooLong,
    );
  }
  final v = request['v'];
  if (v != null && v is! int) {
    return _fail(
      CommandErrorCode.invalidArgs,
      field: 'v',
      p: FieldProblem.badFormat,
    );
  }
  final warnings = [
    for (final k in request.keys)
      if (!const {'v', 'command', 'args', 'idempotencyKey'}.contains(k)) k,
  ];
  return _build(
    name: name,
    version: v?.toString(),
    args: rawArgs,
    source: source,
    idempotencyKey: key is String && key.isNotEmpty ? key : null,
    now: now,
    extraWarnings: warnings,
  );
}

const _knownArgs = <String, Set<String>>{
  'add_task': {
    'title',
    'description',
    'date',
    'start',
    'end',
    'priority',
    'tags',
  },
  'add_schedule_item': {'title', 'date', 'start', 'end', 'location', 'note'},
  'complete_task': {'id'},
  'list_today': {'date'},
  'open': {'screen'},
};

ParseResult _build({
  required String name,
  required String? version,
  required Map<String, Object?> args,
  required CommandSource source,
  required String? idempotencyKey,
  required DateTime now,
  List<String> extraWarnings = const [],
  bool titleRequired = true,
}) {
  if (version != null) {
    final v = int.tryParse(version);
    if (v == null) {
      return _fail(
        CommandErrorCode.invalidArgs,
        field: 'v',
        p: FieldProblem.badFormat,
      );
    }
    if (v > kCommandFormatVersion) {
      return _fail(CommandErrorCode.unsupportedVersion);
    }
    if (v < 1) {
      return _fail(
        CommandErrorCode.invalidArgs,
        field: 'v',
        p: FieldProblem.outOfRange,
      );
    }
  }
  final known = _knownArgs[name];
  if (known == null) return _fail(CommandErrorCode.unknownCommand);
  final warnings = [
    ...extraWarnings,
    for (final k in args.keys)
      if (!known.contains(k)) k,
  ];
  final a = _Args(args, now);
  try {
    final IntegrationCommand cmd = switch (name) {
      'add_task' => () {
          final start = a.time('start');
          final end = a.time('end');
          _checkOrder(start, end);
          return AddTask(
            source: source,
            title: a.text('title', kMaxTitle, required: titleRequired) ?? '',
            description: a.text('description', kMaxLongText),
            date: a.date('date') ?? effectiveDay(now),
            startMinutes: start,
            endMinutes: end,
            priority: a.priority('priority'),
            tags: a.tags('tags'),
            idempotencyKey: idempotencyKey,
            warnings: warnings,
          );
        }(),
      'add_schedule_item' => () {
          final start = a.time('start');
          final end = a.time('end');
          if (start == null) throw const _Bad('start', FieldProblem.missing);
          _checkOrder(start, end);
          return AddScheduleItem(
            source: source,
            title: a.text('title', kMaxTitle, required: titleRequired) ?? '',
            date: a.date('date') ?? effectiveDay(now),
            startMinutes: start,
            endMinutes: end,
            location: a.text('location', kMaxLocation),
            note: a.text('note', kMaxLongText),
            idempotencyKey: idempotencyKey,
            warnings: warnings,
          );
        }(),
      'complete_task' => () {
          final id = a.text('id', 100, required: true)!;
          if (id.length < 4) throw const _Bad('id', FieldProblem.outOfRange);
          return CompleteTask(
            source: source,
            id: id,
            idempotencyKey: idempotencyKey,
            warnings: warnings,
          );
        }(),
      'list_today' => ListToday(
          source: source,
          date: a.date('date'),
          idempotencyKey: idempotencyKey,
          warnings: warnings,
        ),
      _ => () {
          final screen = a.text('screen', 40, required: true)!;
          final target = OpenTarget.values
              .where((t) => t.name == screen.toLowerCase())
              .firstOrNull;
          if (target == null) {
            throw const _Bad('screen', FieldProblem.badFormat);
          }
          return OpenScreen(source: source, target: target, warnings: warnings);
        }(),
    };
    return _ok(cmd);
  } on _Bad catch (e) {
    return _fail(CommandErrorCode.invalidArgs, field: e.field, p: e.problem);
  }
}

void _checkOrder(int? start, int? end) {
  if (start != null && end != null && end <= start) {
    throw const _Bad('end', FieldProblem.endBeforeStart);
  }
}

/// Чтение полей с проверкой. Ссылка даёт только строки, JSON — что угодно:
/// здесь оба сводятся к одним правилам.
class _Args {
  _Args(this._m, this._now);

  final Map<String, Object?> _m;
  final DateTime _now;

  static final _dateRe = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');
  static final _timeRe = RegExp(r'^(\d{1,2}):(\d{2})$');

  String? _string(String k) {
    final v = _m[k];
    if (v == null) return null;
    if (v is! String) throw _Bad(k, FieldProblem.badFormat);
    return v;
  }

  String? text(String k, int max, {bool required = false}) {
    final v = _string(k)?.trim();
    if (v == null || v.isEmpty) {
      if (required) throw _Bad(k, FieldProblem.missing);
      return null;
    }
    // Длину считаем в символах Юникода, а не в UTF-16: эмодзи — один символ.
    if (v.runes.length > max) throw _Bad(k, FieldProblem.tooLong);
    if (v.contains('\u0000')) throw _Bad(k, FieldProblem.badFormat);
    return v;
  }

  DateTime? date(String k) {
    final v = _string(k)?.trim();
    if (v == null || v.isEmpty) return null;
    final m = _dateRe.firstMatch(v);
    if (m == null) throw _Bad(k, FieldProblem.badFormat);
    final y = int.parse(m[1]!), mo = int.parse(m[2]!), d = int.parse(m[3]!);
    final date = DateTime(y, mo, d);
    // DateTime молча переносит 31.02 на март — такую дату не принимаем.
    if (date.year != y || date.month != mo || date.day != d) {
      throw _Bad(k, FieldProblem.badFormat);
    }
    final today = dateOnly(_now);
    final min = DateTime(today.year - kDateRangeYears, today.month, today.day);
    final max = DateTime(today.year + kDateRangeYears, today.month, today.day);
    if (date.isBefore(min) || date.isAfter(max)) {
      throw _Bad(k, FieldProblem.outOfRange);
    }
    return date;
  }

  int? time(String k) {
    final v = _string(k)?.trim();
    if (v == null || v.isEmpty) return null;
    final m = _timeRe.firstMatch(v);
    if (m == null) throw _Bad(k, FieldProblem.badFormat);
    final h = int.parse(m[1]!), min = int.parse(m[2]!);
    if (h > 23 || min > 59) throw _Bad(k, FieldProblem.outOfRange);
    return h * 60 + min;
  }

  TaskPriority priority(String k) {
    final v = _string(k)?.trim().toLowerCase();
    if (v == null || v.isEmpty) return TaskPriority.none;
    return TaskPriority.values.where((p) => p.name == v).firstOrNull ??
        (throw _Bad(k, FieldProblem.badFormat));
  }

  List<String> tags(String k) {
    final v = _m[k];
    if (v == null) return const [];
    final List<String> raw;
    if (v is String) {
      raw = v.split(',');
    } else if (v is List && v.every((e) => e is String)) {
      raw = v.cast<String>();
    } else {
      throw _Bad(k, FieldProblem.badFormat);
    }
    final out = <String>[];
    for (final t in raw) {
      final tag = t.trim().replaceFirst(RegExp(r'^#+'), '').trim();
      if (tag.isEmpty) continue;
      if (tag.runes.length > kMaxTagLength) throw _Bad(k, FieldProblem.tooLong);
      if (!out.contains(tag)) out.add(tag);
    }
    if (out.length > kMaxTags) throw _Bad(k, FieldProblem.tooLong);
    return out;
  }
}

/// «HH:MM» для ответов и событий.
String formatHm(int minutes) => '${(minutes ~/ 60).toString().padLeft(2, '0')}:'
    '${(minutes % 60).toString().padLeft(2, '0')}';

/// «YYYY-MM-DD» для ответов и событий.
String formatYmd(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';
