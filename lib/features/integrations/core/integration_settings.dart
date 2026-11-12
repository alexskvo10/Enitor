import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/sources/local/local_storage.dart';
import 'integration_command.dart';

/// Ключ настроек интеграций. Префикс `device.` — состояние этого устройства:
/// в бэкап не попадает и при восстановлении не стирается (см. [LocalStorage]).
const kIntegrationSettingsKey = 'device.integrations';

/// Права одного входа.
class SourcePermission {
  const SourcePermission({this.add = false, this.read = false});

  /// Добавлять задачи и пункты расписания, отмечать выполненное.
  final bool add;

  /// Отдавать список дел наружу.
  final bool read;

  SourcePermission copyWith({bool? add, bool? read}) =>
      SourcePermission(add: add ?? this.add, read: read ?? this.read);

  Map<String, dynamic> toJson() => {'add': add, 'read': read};

  factory SourcePermission.fromJson(Map<String, dynamic> j) => SourcePermission(
        add: j['add'] as bool? ?? false,
        read: j['read'] as bool? ?? false,
      );
}

/// Пакеты, которым по умолчанию можно отвечать адресным broadcast: Tasker и
/// Automate. Пользователь может убрать их или добавить свой.
const kDefaultReplyPackages = [
  'net.dinglisch.android.taskerm',
  'com.llamalab.automate',
];

class IntegrationSettings {
  const IntegrationSettings({
    this.permissions = const {},
    this.replyPackages = kDefaultReplyPackages,
    this.backgroundTrace = true,
    this.windowsLinks = true,
  });

  final Map<CommandSource, SourcePermission> permissions;

  /// Кому Tasker-ответ может уйти адресным broadcast.
  final List<String> replyPackages;

  /// Тихое уведомление о каждой фоновой команде («Добавлено из Tasker: …»):
  /// чужая автоматизация не должна действовать незаметно.
  final bool backgroundTrace;

  /// Windows: зарегистрирована ли схема `enitor://` для этой папки.
  final bool windowsLinks;

  /// Права входа с учётом умолчаний. Ссылки и «Поделиться» ничего не отдают
  /// и не добавляют без анкеты — включены сразу; виджет — наш собственный
  /// экран. Всё остальное выключено, пока пользователь не включит сам.
  SourcePermission of(CommandSource s) =>
      permissions[s] ??
      switch (s) {
        CommandSource.link ||
        CommandSource.share ||
        CommandSource.widget =>
          const SourcePermission(add: true),
        _ => const SourcePermission(),
      };

  /// Разрешена ли команда этому входу. Ссылки и «Поделиться» никогда не
  /// читают и ничего не отмечают — только предлагают добавить или открыть.
  bool allows(IntegrationCommand c) {
    final p = of(c.source);
    if (c.source.trust == CommandTrust.untrusted) {
      return switch (c) {
        AddTask() || AddScheduleItem() => p.add,
        OpenScreen() => true,
        _ => false,
      };
    }
    if (c is OpenScreen) return true;
    return c.isRead ? p.read : p.add;
  }

  IntegrationSettings copyWith({
    Map<CommandSource, SourcePermission>? permissions,
    List<String>? replyPackages,
    bool? backgroundTrace,
    bool? windowsLinks,
  }) =>
      IntegrationSettings(
        permissions: permissions ?? this.permissions,
        replyPackages: replyPackages ?? this.replyPackages,
        backgroundTrace: backgroundTrace ?? this.backgroundTrace,
        windowsLinks: windowsLinks ?? this.windowsLinks,
      );

  IntegrationSettings withPermission(CommandSource s, SourcePermission p) =>
      copyWith(permissions: {...permissions, s: p});

  Map<String, dynamic> toJson() => {
        'permissions': {
          for (final e in permissions.entries) e.key.name: e.value.toJson(),
        },
        'replyPackages': replyPackages,
        'backgroundTrace': backgroundTrace,
        'windowsLinks': windowsLinks,
      };

  factory IntegrationSettings.fromJson(Map<String, dynamic> j) {
    final perms = <CommandSource, SourcePermission>{};
    final raw = j['permissions'];
    if (raw is Map<String, dynamic>) {
      for (final e in raw.entries) {
        final s = CommandSource.values.where((v) => v.name == e.key).firstOrNull;
        if (s != null && e.value is Map<String, dynamic>) {
          perms[s] = SourcePermission.fromJson(e.value as Map<String, dynamic>);
        }
      }
    }
    return IntegrationSettings(
      permissions: perms,
      replyPackages: (j['replyPackages'] as List?)?.cast<String>() ??
          kDefaultReplyPackages,
      backgroundTrace: j['backgroundTrace'] as bool? ?? true,
      windowsLinks: j['windowsLinks'] as bool? ?? true,
    );
  }
}

class IntegrationSettingsController extends Notifier<IntegrationSettings> {
  @override
  IntegrationSettings build() {
    final raw = ref.read(localStorageProvider).readMap(kIntegrationSettingsKey);
    return raw == null
        ? const IntegrationSettings()
        : IntegrationSettings.fromJson(raw);
  }

  Future<void> update(IntegrationSettings next) async {
    state = next;
    await ref
        .read(localStorageProvider)
        .writeMap(kIntegrationSettingsKey, next.toJson());
  }

  Future<void> setPermission(CommandSource s, SourcePermission p) =>
      update(state.withPermission(s, p));
}

final integrationSettingsProvider =
    NotifierProvider<IntegrationSettingsController, IntegrationSettings>(
  IntegrationSettingsController.new,
);
