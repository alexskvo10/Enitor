import 'package:audioplayers/audioplayers.dart';

/// Звуковые эффекты приложения. Пока единственный — сигнал окончания
/// фазы таймера Помодоро (фокус/перерыв).
class SoundService {
  /// Плеер создаётся при первом звуке, а не в конструкторе: сам факт создания
  /// дёргает плагин через канал платформы, а живёт этот сервис внутри
  /// Помодоро-контроллера, который поднимается при старте приложения. Заодно
  /// контроллер становится проверяемым в тестах, где плагина нет вовсе.
  AudioPlayer? _player;

  Future<void> playPomodoroDone() async {
    try {
      final player = _player ??= AudioPlayer();
      await player.stop();
      await player.play(AssetSource('sounds/pomodoro_done.wav'));
    } catch (_) {
      // Звук не критичен для работы таймера — не роняем приложение.
    }
  }

  void dispose() => _player?.dispose();
}
