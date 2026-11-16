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
      var player = _player;
      if (player == null) {
        player = _player = AudioPlayer();
        // Сигнал — уведомление, а не музыка: громкость уведомлений, молчит в
        // беззвучном режиме, а играющую музыку на пару секунд приглушает, а
        // не останавливает насовсем (по умолчанию плеер забирал звук себе).
        await player.setAudioContext(
          AudioContext(
            android: const AudioContextAndroid(
              contentType: AndroidContentType.sonification,
              usageType: AndroidUsageType.notificationEvent,
              audioFocus: AndroidAudioFocus.gainTransientMayDuck,
            ),
          ),
        );
      }
      await player.stop();
      await player.play(AssetSource('sounds/pomodoro_done.wav'));
    } catch (_) {
      // Звук не критичен для работы таймера — не роняем приложение.
    }
  }

  void dispose() => _player?.dispose();
}
