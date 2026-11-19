import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../inbox/command_inbox.dart';
import '../sync/lan/lan_service.dart';
import 'command_handler.dart';
import 'integration_command.dart';
import 'integration_settings.dart';
import 'secret_store.dart';

/// Канал платформа → Dart, общий для Android и Windows: обработчик команд не
/// знает, откуда пришла команда физически.
const kCommandsChannel = MethodChannel('dev.enitor.app/commands');

/// Ключ журнала вызовов ИИ-ассистентов (ключ «устройство»).
const kMcpLogKey = 'device.integrations.mcp_log';
const kMcpLogSize = 10;

/// Приёмная всех внешних входов. Недоверенные (ссылка, «Поделиться») уходят
/// в [CommandInbox] — к анкете; доверенные — в [CommandHandler], ответ
/// возвращается тому, кто спросил.
class IntegrationGateway {
  IntegrationGateway(this._ref, {DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final Ref _ref;
  final DateTime Function() _clock;

  /// Срабатывает после каждой выполненной фоновой команды — для
  /// уведомления-следа (Tasker) и журнала (MCP).
  final _executed =
      StreamController<(IntegrationCommand, CommandReply)>.broadcast();
  Stream<(IntegrationCommand, CommandReply)> get executed => _executed.stream;

  /// Подключает канал и говорит платформе «Dart готов»: команды, пришедшие
  /// раньше (холодный старт по ссылке), лежат в буфере на той стороне.
  Future<void> attach() async {
    kCommandsChannel.setMethodCallHandler(handleCall);
    try {
      await kCommandsChannel.invokeMethod<void>('ready');
    } on MissingPluginException {
      // Платформа без нативной части (тесты, Linux) — входов просто нет.
    } on PlatformException catch (e) {
      debugPrint('IntegrationGateway.ready: $e');
    }
  }

  @visibleForTesting
  Future<Object?> handleCall(MethodCall call) async {
    // Windows: кадр из именованного канала — строка JSON как есть.
    if (call.method == 'pipe') return receivePipe(call.arguments as String? ?? '');
    final args = (call.arguments as Map?)?.cast<String, Object?>() ?? const {};
    switch (call.method) {
      case 'link':
        receiveLink(args['url'] as String? ?? '');
        return null;
      case 'share':
        receiveShare(args['text'] as String?);
        return null;
      case 'command':
        final source = CommandSource.values
                .where((s) => s.name == args['source'])
                .firstOrNull ??
            CommandSource.cli;
        return receiveCommand(
          args['json'] as String? ?? '',
          source: source,
          key: args['key'] as String?,
          replyPackage: args['replyPackage'] as String?,
        );
    }
    throw MissingPluginException(call.method);
  }

  /// Кадр канала Windows (`enitor-cli`, MCP, второй экземпляр со ссылкой):
  /// `{"v":1,"kind":"command","source":"cli"|"mcp","request":{…}}`,
  /// `{"v":1,"kind":"link","url":"…"}` или `{"v":1,"kind":"ping"}`.
  /// Ответ — JSON-строка (formats.md, «Replies»).
  Future<String> receivePipe(String frame) async {
    final l10n = currentL10n();
    String fail(CommandError e) =>
        jsonEncode(CommandReply.fail(e).toJson(l10n));
    final Object? env;
    try {
      env = jsonDecode(frame);
    } on FormatException {
      return fail(
        const CommandError(
          CommandErrorCode.invalidArgs,
          field: 'request',
          problem: FieldProblem.badFormat,
        ),
      );
    }
    if (env is! Map<String, Object?>) {
      return fail(
        const CommandError(
          CommandErrorCode.invalidArgs,
          field: 'request',
          problem: FieldProblem.badFormat,
        ),
      );
    }
    final v = env['v'];
    if (v is int && v > kCommandFormatVersion) {
      return fail(const CommandError(CommandErrorCode.unsupportedVersion));
    }
    switch (env['kind']) {
      case 'ping':
        return jsonEncode(const CommandReply.ok({}).toJson(l10n));
      case 'permissions':
        // MCP показывает ассистенту только разрешённые инструменты: без
        // права «читать» list_today нет в списке вовсе.
        final p = _ref
            .read(integrationSettingsProvider)
            .of(env['source'] == 'mcp' ? CommandSource.mcp : CommandSource.cli);
        return jsonEncode(
          CommandReply.ok({'add': p.add, 'read': p.read}).toJson(l10n),
        );
      case 'link':
        // Кадр приходит снаружи процесса — тип поля не принимаем на веру.
        final url = env['url'];
        receiveLink(url is String ? url : '');
        return jsonEncode(const CommandReply.ok({}).toJson(l10n));
      case 'command':
        // С канала Windows приходят только консоль и ИИ-ассистенты; всё
        // прочее — как консоль, без повышения прав.
        final source =
            env['source'] == 'mcp' ? CommandSource.mcp : CommandSource.cli;
        final request = env['request'];
        if (request is! Map<String, Object?>) {
          return fail(
            const CommandError(
              CommandErrorCode.invalidArgs,
              field: 'request',
              problem: FieldProblem.missing,
            ),
          );
        }
        final out = await _execute(
          parseCommandMap(request, source: source, now: _clock()),
        );
        return jsonEncode(out.toJson(l10n));
    }
    return fail(const CommandError(CommandErrorCode.unknownCommand));
  }

  Future<CommandReply> _execute(ParseResult parsed) async {
    final cmd = parsed.command;
    if (cmd == null) return CommandReply.fail(parsed.error);
    final reply = await _ref.read(commandHandlerProvider).execute(cmd);
    _executed.add((cmd, reply));
    return reply;
  }

  void receiveLink(String url, {CommandSource source = CommandSource.link}) {
    // `enitor://pair?…` (QR-код или любая ссылка — открыть её может и
    // сайт) — не команда, а знакомство устройств:
    // экран синхронизации спросит, подключаться ли.
    final uri = Uri.tryParse(url.trim());
    if (uri != null &&
        uri.scheme.toLowerCase() == 'enitor' &&
        (uri.host.isNotEmpty ? uri.host : uri.path).toLowerCase() == 'pair') {
      _ref.read(lanPairLinkProvider.notifier).state = uri;
      return;
    }
    final r = parseLink(url, now: _clock(), source: source);
    _toInbox(r, source);
  }

  void receiveShare(String? text) =>
      _toInbox(parseSharedText(text, now: _clock()), CommandSource.share);

  void _toInbox(ParseResult r, CommandSource source) {
    final inbox = _ref.read(commandInboxProvider.notifier);
    final cmd = r.command;
    if (cmd == null) {
      inbox.push(InboxError(r.error!, source));
    } else if (!_ref.read(integrationSettingsProvider).allows(cmd)) {
      inbox.push(InboxError(const CommandError(CommandErrorCode.forbidden), source));
    } else {
      inbox.push(InboxCommand(cmd));
    }
  }

  /// Доверенная команда → ответ. Для Tasker сначала проверяется ключ, а в
  /// ответе — кому его можно отправить (`replyTo`, только пакет из списка
  /// разрешённых, иначе ответа нет вовсе).
  Future<Map<String, Object?>> receiveCommand(
    String json, {
    required CommandSource source,
    String? key,
    String? replyPackage,
  }) async {
    final l10n = currentL10n();
    final settings = _ref.read(integrationSettingsProvider);
    final replyTo = replyPackage != null &&
            settings.replyPackages.contains(replyPackage)
        ? replyPackage
        : null;
    Map<String, Object?> out(CommandReply r) =>
        {'reply': jsonEncode(r.toJson(l10n)), 'replyTo': replyTo};

    if (source == CommandSource.tasker) {
      final ok = await _ref.read(secretStoreProvider).checkTaskerKey(key);
      if (!ok) {
        return out(
          const CommandReply.fail(CommandError(CommandErrorCode.badKey)),
        );
      }
    }
    return out(
      await _execute(parseJsonCommand(json, source: source, now: _clock())),
    );
  }

  void dispose() => _executed.close();
}

final integrationGatewayProvider = Provider<IntegrationGateway>((ref) {
  final g = IntegrationGateway(ref);
  ref.onDispose(g.dispose);
  return g;
});
