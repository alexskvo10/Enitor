import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/sources/local/local_storage.dart';
import '../../../services/notification_service.dart';
import 'command_handler.dart';
import 'integration_command.dart';
import 'integration_gateway.dart';
import 'integration_settings.dart';

/// Запись журнала вызовов ИИ-ассистента: что вызвано, когда и чем кончилось.
class McpLogEntry {
  const McpLogEntry({
    required this.at,
    required this.command,
    required this.ok,
    this.detail,
  });

  final DateTime at;
  final String command;
  final bool ok;

  /// Название задачи или код ошибки — чтобы было видно, что именно делал
  /// ассистент.
  final String? detail;

  Map<String, dynamic> toJson() => {
        'at': at.toIso8601String(),
        'command': command,
        'ok': ok,
        if (detail != null) 'detail': detail,
      };

  factory McpLogEntry.fromJson(Map<String, dynamic> j) => McpLogEntry(
        at: DateTime.tryParse(j['at'] as String? ?? '') ?? DateTime(2000),
        command: j['command'] as String? ?? '',
        ok: j['ok'] as bool? ?? false,
        detail: j['detail'] as String?,
      );
}

/// Последние [kMcpLogSize] вызовов, новые сверху. Ключ «устройство».
class McpLog extends Notifier<List<McpLogEntry>> {
  @override
  List<McpLogEntry> build() => [
        for (final j in ref.read(localStorageProvider).readList(kMcpLogKey))
          McpLogEntry.fromJson(j),
      ];

  Future<void> add(McpLogEntry e) async {
    state = [e, ...state].take(kMcpLogSize).toList();
    await ref
        .read(localStorageProvider)
        .writeList(kMcpLogKey, [for (final x in state) x.toJson()]);
  }

  Future<void> clear() async {
    state = const [];
    await ref.read(localStorageProvider).remove(kMcpLogKey);
  }
}

final mcpLogProvider =
    NotifierProvider<McpLog, List<McpLogEntry>>(McpLog.new);

/// О чём команда — для следа и журнала: название задачи или пункта.
String? commandSubject(IntegrationCommand c, CommandReply r) {
  final task = r.result?['task'] ?? r.result?['item'];
  if (task is Map && task['title'] is String) return task['title'] as String;
  return r.error?.code.wire;
}

/// Подписка на выполненные фоновые команды: уведомление-след для Tasker,
/// журнал для MCP. Держится всё время работы приложения.
StreamSubscription<void> watchExecutedCommands(ProviderContainer container) {
  final gateway = container.read(integrationGatewayProvider);
  return gateway.executed.listen((event) async {
    final (cmd, reply) = event;
    switch (cmd.source) {
      case CommandSource.mcp:
        await container.read(mcpLogProvider.notifier).add(
              McpLogEntry(
                at: DateTime.now(),
                command: cmd.name,
                ok: reply.ok,
                detail: commandSubject(cmd, reply),
              ),
            );
      case CommandSource.tasker:
        if (!reply.ok || cmd.isRead) return;
        if (!container.read(integrationSettingsProvider).backgroundTrace) {
          return;
        }
        final l10n = currentL10n();
        await container.read(notificationServiceProvider).showTrace(
              cmd is CompleteTask
                  ? l10n.traceCompletedFromTasker
                  : l10n.traceAddedFromTasker,
              commandSubject(cmd, reply) ?? '',
            );
      default:
        break;
    }
  });
}
