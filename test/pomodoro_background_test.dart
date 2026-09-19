import 'package:enitor/data/models/task.dart';
import 'package:enitor/data/repositories/task_repository.dart';
import 'package:enitor/data/sources/local/local_storage.dart';
import 'package:enitor/services/pomodoro_controller.dart';
import 'package:enitor/services/pomodoro_prefs.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Таймер Помодоро обязан переживать уход приложения в фон. Android
// замораживает свёрнутый процесс: тики не приходят, а бывает, что процесс
// выгружают целиком. Раньше отсчёт шёл тиками — и вставал, а выгрузка
// убивала таймер вместе с отработанными минутами. Здесь время двигается
// подменой часов БЕЗ единого тика — ровно как у замороженного процесса.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final t0 = DateTime(2026, 9, 19, 10);
  late DateTime now;
  late ProviderContainer container;
  late LocalStorage storage;
  late Task task;

  setUp(() async {
    now = t0;
    SharedPreferences.setMockInitialValues({});
    storage = LocalStorage(await SharedPreferences.getInstance());
    container = ProviderContainer(
      overrides: [localStorageProvider.overrideWithValue(storage)],
    );
    task = await container
        .read(taskRepositoryProvider)
        .createAndAdd(title: 'Написать письмо', date: t0);
  });

  tearDown(() => container.dispose());

  /// Новый контроллер поверх того же хранилища — как запуск приложения.
  PomodoroController launch() {
    final c = PomodoroController(
      container.read(taskRepositoryProvider),
      container.read(pomodoroPrefsProvider),
      storage,
      clock: () => now,
    );
    addTearDown(c.dispose);
    return c;
  }

  int? actualMinutes() =>
      container.read(taskRepositoryProvider).taskById(task.id)?.actualMinutes;

  test('в фоне время идёт, даже если тиков не было', () {
    final timer = launch()..startFocus(task);
    now = t0.add(const Duration(minutes: 10));

    timer.pause();

    expect(timer.remainingSeconds, 15 * 60);
  });

  test('после выгрузки процесса идущий фокус продолжается', () {
    launch().startFocus(task);
    now = t0.add(const Duration(minutes: 7, seconds: 30));

    final timer = launch();

    expect(timer.phase, PomodoroPhase.focus);
    expect(timer.taskTitle, 'Написать письмо');
    expect(timer.remainingSeconds, 17 * 60 + 30);
  });

  test('фокус кончился, пока приложение спало: минуты записаны, перерыв '
      'идёт от конца фокуса', () async {
    launch().startFocus(task);
    now = t0.add(const Duration(minutes: 27));

    final timer = launch();
    await pumpEventQueue();

    expect(timer.phase, PomodoroPhase.breakTime);
    expect(timer.remainingSeconds, 3 * 60); // 5-минутный перерыв с 10:25
    expect(timer.sessionMinutes, 25);
    expect(actualMinutes(), 25);
  });

  test('проспали и фокус, и перерыв — «Готово», минуты записаны один раз',
      () async {
    launch().startFocus(task);
    now = t0.add(const Duration(hours: 2));

    final timer = launch();
    await pumpEventQueue();
    // Второй запуск не должен записать фокус повторно.
    launch();
    await pumpEventQueue();

    expect(timer.phase, PomodoroPhase.finished);
    expect(actualMinutes(), 25);
  });

  test('пауза переживает перезапуск и не тает', () {
    final first = launch()..startFocus(task);
    now = t0.add(const Duration(minutes: 5));
    first.pause();
    now = t0.add(const Duration(hours: 3));

    final timer = launch();

    expect(timer.phase, PomodoroPhase.paused);
    expect(timer.remainingSeconds, 20 * 60);
  });

  test('после стопа поднимать нечего', () {
    launch()
      ..startFocus(task)
      ..stop();

    expect(launch().phase, PomodoroPhase.idle);
  });

  test('битый ключ не роняет запуск', () async {
    await storage.writeMap('pomodoro_state', {'phase': 'focus'});

    expect(launch().phase, PomodoroPhase.idle);
    expect(storage.readMap('pomodoro_state'), isNull);
  });
}
