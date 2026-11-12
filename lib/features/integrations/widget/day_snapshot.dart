import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import '../../../core/l10n/locale_controller.dart';
import '../../../core/utils/date_utils.dart';
import '../../../data/models/task.dart';
import '../../../data/repositories/task_repository.dart';
import '../../../data/sources/local/local_storage.dart';
import '../../../l10n/app_localizations.dart';
import '../core/command_handler.dart';
import '../core/integration_command.dart';
import '../core/integration_gateway.dart';

/// Снимок для виджета «Сегодня» (ключ «устройство»: не в бэкап). Kotlin
/// читает его из SharedPreferences как `flutter.device.widget.today`.
const kWidgetSnapshotKey = 'device.widget.today';

/// Сколько задач влезает в самый высокий виджет.
const kWidgetMaxTasks = 6;

/// Снимок на «день приложения» и следующий за ним: в 4:00 виджет сам
/// переключается на завтрашний, не будя приложение. Тексты — уже на языке
/// приложения: у виджета своей локализации нет.
Map<String, Object?> buildWidgetSnapshot({
  required List<Task> Function(DateTime day) tasksForDay,
  required DateTime now,
  required AppLocalizations l10n,
}) {
  final today = effectiveDay(now);
  final tomorrow = DateTime(today.year, today.month, today.day + 1);
  Map<String, Object?> day(DateTime d) {
    final tasks = tasksForDay(d);
    // Невыполненные — вперёд: в маленьком виджете важнее то, что осталось.
    final ordered = [
      ...tasks.where((t) => !t.isCompleted),
      ...tasks.where((t) => t.isCompleted),
    ];
    final done = tasks.where((t) => t.isCompleted).length;
    return {
      'date': DateFormat('EEE, d MMMM', l10n.localeName).format(d),
      'done': done,
      'total': tasks.length,
      'counter': tasks.isEmpty ? '' : '$done/${tasks.length}',
      'tasks': [
        for (final t in ordered.take(kWidgetMaxTasks))
          {
            'id': t.id,
            'title': t.title,
            'done': t.isCompleted,
            'priority': t.priority.name,
            if (t.startMinutes != null) 'time': formatHm(t.startMinutes!),
            // Виджет сам красит время: жёлтым — скоро конец, красным —
            // просрочено (как корешок задачи в приложении).
            if (t.startMinutes != null) 'start': t.startMinutes,
            if (t.endMinutes != null) 'end': t.endMinutes,
          },
      ],
    };
  }

  return {
    'v': 1,
    'title': l10n.todayTitle,
    'empty': l10n.widgetEmpty,
    'openApp': l10n.widgetOpenApp,
    'addLabel': l10n.widgetAddLabel,
    'allDone': l10n.widgetAllDone,
    // Сколько строк влезает, знает только виджет: число он подставит сам.
    'more': l10n.widgetMore('%d'),
    'days': {formatYmd(today): day(today), formatYmd(tomorrow): day(tomorrow)},
  };
}

/// Держит снимок свежим: после каждой правки задач (с небольшой задержкой,
/// чтобы серия правок дала одну запись) и при старте. Только Android.
class WidgetSnapshotWriter {
  WidgetSnapshotWriter(this._container, {DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final ProviderContainer _container;
  final DateTime Function() _clock;
  Timer? _debounce;
  final _subs = <ProviderSubscription<void>>[];

  void start() {
    _subs
      ..add(
        _container.listen(
          allTasksProvider,
          (_, __) => _schedule(),
          fireImmediately: true,
        ),
      )
      // Тексты снимка — на языке приложения: сменили язык — переписываем.
      ..add(
        _container.listen(
          localeControllerProvider.select((c) => c.option),
          (_, __) => _schedule(),
        ),
      );
  }

  void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () => unawaited(write()));
  }

  @visibleForTesting
  Future<void> write() async {
    final repo = _container.read(taskRepositoryProvider);
    final now = _clock();
    // Завтрашние задачи из повторений появляются при открытии дня —
    // открываем его так же, как это сделал бы пользователь.
    final tomorrow = effectiveDay(now).add(const Duration(days: 1));
    await repo.ensureRecurrencesForDay(effectiveDay(now));
    await repo.ensureRecurrencesForDay(tomorrow);
    final l10n = currentL10n();
    // Названия дней и месяцев для даты в шапке: запись может случиться
    // раньше, чем их подгрузят локализации Material.
    await initializeDateFormatting(l10n.localeName);
    await _container.read(localStorageProvider).writeMap(
          kWidgetSnapshotKey,
          buildWidgetSnapshot(
            tasksForDay: repo.tasksForDay,
            now: now,
            l10n: l10n,
          ),
        );
    try {
      await kCommandsChannel.invokeMethod<void>('widgetChanged');
    } on MissingPluginException {
      // Нет нативной части (тесты).
    } on PlatformException catch (e) {
      debugPrint('widgetChanged: $e');
    }
  }

  void dispose() {
    _debounce?.cancel();
    for (final s in _subs) {
      s.close();
    }
  }
}
