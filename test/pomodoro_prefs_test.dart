import 'package:enitor/data/repositories/task_repository.dart';
import 'package:enitor/data/sources/local/local_storage.dart';
import 'package:enitor/services/pomodoro_controller.dart';
import 'package:enitor/services/pomodoro_prefs.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Длины отрезков Помодоро настраиваемые: 25/5 — только значения по умолчанию.
// Проверяем и сам контроллер настроек, и то, что таймер берёт длину из него.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<ProviderContainer> makeContainer([
    Map<String, Object> initial = const {},
  ]) async {
    SharedPreferences.setMockInitialValues(initial);
    final prefs = await SharedPreferences.getInstance();
    return ProviderContainer(
      overrides: [localStorageProvider.overrideWithValue(LocalStorage(prefs))],
    );
  }

  test('по умолчанию — классические 25/5', () async {
    final container = await makeContainer();
    addTearDown(container.dispose);
    final prefs = container.read(pomodoroPrefsProvider);

    expect(prefs.focusMinutes, 25);
    expect(prefs.breakMinutes, 5);
  });

  test('выбранные длины переживают перезапуск', () async {
    final container = await makeContainer();
    final prefs = container.read(pomodoroPrefsProvider);
    await prefs.setFocusMinutes(50);
    await prefs.setBreakMinutes(10);
    container.dispose();

    // Второй контейнер поверх того же хранилища — как новый запуск.
    final restored = ProviderContainer(
      overrides: [
        localStorageProvider.overrideWithValue(
          LocalStorage(await SharedPreferences.getInstance()),
        ),
      ],
    );
    addTearDown(restored.dispose);

    expect(restored.read(pomodoroPrefsProvider).focusMinutes, 50);
    expect(restored.read(pomodoroPrefsProvider).breakMinutes, 10);
  });

  test('значение вне списка пресетов заменяется дефолтом', () async {
    // Такое приезжает из чужого бэкапа или из будущей версии с другими
    // пресетами. Пустить его дальше нельзя: выпадашка в настройках падает на
    // значении, которого нет среди её пунктов.
    final container = await makeContainer({
      'pomodoro_prefs': '{"focusMinutes":37,"breakMinutes":0}',
    });
    addTearDown(container.dispose);
    final prefs = container.read(pomodoroPrefsProvider);

    expect(prefs.focusMinutes, 25);
    expect(prefs.breakMinutes, 5);
    expect(kPomodoroFocusOptions, contains(prefs.focusMinutes));
    expect(kPomodoroBreakOptions, contains(prefs.breakMinutes));
  });

  test('setter не принимает длину вне пресетов', () async {
    final container = await makeContainer();
    addTearDown(container.dispose);
    final prefs = container.read(pomodoroPrefsProvider);

    await prefs.setFocusMinutes(7);
    await prefs.setBreakMinutes(120);

    expect(prefs.focusMinutes, 25);
    expect(prefs.breakMinutes, 5);
  });

  test('сброс настроек возвращает 25/5', () async {
    final container = await makeContainer();
    addTearDown(container.dispose);
    final prefs = container.read(pomodoroPrefsProvider);
    await prefs.setFocusMinutes(90);

    await prefs.resetToDefaults();

    expect(prefs.focusMinutes, 25);
    expect(prefs.breakMinutes, 5);
  });

  test('таймер стартует с настроенной длиной', () async {
    final container = await makeContainer();
    addTearDown(container.dispose);
    await container.read(pomodoroPrefsProvider).setFocusMinutes(15);
    // Задача обязательно настоящая, из репозитория: таймер следит за списком
    // задач и выключается, не найдя отслеживаемую.
    final task = await container
        .read(taskRepositoryProvider)
        .createAndAdd(title: 'Написать письмо', date: DateTime(2026, 8, 4));

    final timer = container.read(pomodoroProvider);
    timer.startFocus(task);

    expect(timer.phase, PomodoroPhase.focus);
    expect(timer.totalSeconds, 15 * 60);
    expect(timer.remainingSeconds, 15 * 60);
    timer.stop();
  });

  test('смена настройки не трогает идущий отрезок, но берётся следующим',
      () async {
    final container = await makeContainer();
    addTearDown(container.dispose);
    final task = await container
        .read(taskRepositoryProvider)
        .createAndAdd(title: 'Разобрать почту', date: DateTime(2026, 8, 4));

    final timer = container.read(pomodoroProvider);
    timer.startFocus(task);
    expect(timer.totalSeconds, 25 * 60);

    // Посреди отсчёта. Идущий таймер обязан остаться прежним: иначе он либо
    // прыгнул бы, либо «досрочно закончился», записав в факт не то время.
    await container.read(pomodoroPrefsProvider).setFocusMinutes(45);
    expect(timer.totalSeconds, 25 * 60);
    expect(timer.phase, PomodoroPhase.focus);

    timer.anotherFocus();
    expect(timer.totalSeconds, 45 * 60);
    timer.stop();
  });
}
