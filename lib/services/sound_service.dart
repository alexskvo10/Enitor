import 'package:audioplayers/audioplayers.dart';

/// Звуковые эффекты приложения. Пока единственный — сигнал окончания
/// фазы таймера Помодоро (фокус/перерыв).
class SoundService {
  final _player = AudioPlayer();

  Future<void> playPomodoroDone() async {
    try {
      await _player.stop();
      await _player.play(AssetSource('sounds/pomodoro_done.wav'));
    } catch (_) {
      // Звук не критичен для работы таймера — не роняем приложение.
    }
  }

  void dispose() => _player.dispose();
}
