import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_fonts.dart';
import '../../l10n/l10n_extensions.dart';
import '../../services/pomodoro_controller.dart';
import '../../services/pomodoro_prefs.dart';

/// Открыт ли сейчас экран фокуса — чтобы не положить второй поверх первого.
bool _open = false;

/// Таймер фокуса на весь экран. Открывается сам при старте фокуса, из
/// свёрнутой карточки — по нажатию. «Свернуть», «назад» и Esc закрывают
/// только экран: таймер идёт дальше в карточке на «Задачах».
Future<void> showFocusScreen(BuildContext context) async {
  if (_open) return;
  _open = true;
  try {
    // В корневой навигатор, поверх вкладок с нижней панелью, и обычной
    // страницей, не fullscreenDialog: под «диалогом» Flutter не гасит
    // предыдущий экран, и «Задачи» просвечивали сквозь проявляющийся таймер.
    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        builder: (_) => const FocusScreen(),
      ),
    );
  } finally {
    _open = false;
  }
}

class FocusScreen extends ConsumerStatefulWidget {
  const FocusScreen({super.key});

  @override
  ConsumerState<FocusScreen> createState() => _FocusScreenState();
}

class _FocusScreenState extends ConsumerState<FocusScreen>
    with SingleTickerProviderStateMixin {
  // Едва заметное «дыхание» ореола за кольцом — экран живой, но не мельтешит.
  late final AnimationController _breath = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
  )..repeat(reverse: true);

  bool _closing = false;

  @override
  void initState() {
    super.initState();
    // Пока экран открыт, он не гаснет: телефон лежит рядом, человек работает.
    // В тестах и там, где плагина нет, — молча без этого.
    unawaited(WakelockPlus.enable().catchError((Object _) {}));
  }

  @override
  void dispose() {
    unawaited(WakelockPlus.disable().catchError((Object _) {}));
    _breath.dispose();
    super.dispose();
  }

  void _close() {
    if (_closing || !mounted) return;
    _closing = true;
    Navigator.of(context).maybePop();
  }

  static String _mmss(int s) => '${(s ~/ 60).toString().padLeft(2, '0')}:'
      '${(s % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final p = ref.watch(pomodoroProvider);
    // Таймер остановили (здесь или из карточки/уведомления) — экрану нечего
    // показывать.
    if (!p.isActive) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _close());
    }
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final isBreak = p.phase == PomodoroPhase.breakTime;
    final isFinished = p.phase == PomodoroPhase.finished;
    final isPaused = p.phase == PomodoroPhase.paused;
    final accent = isFinished
        ? AppColors.success
        : isBreak
            ? (dark ? AppColors.claySoft : AppColors.clay)
            : theme.colorScheme.primary;
    final muted = dark ? AppColors.textSecondaryDark : AppColors.textSecondary;
    final phaseLine = switch (p.phase) {
      PomodoroPhase.focus => l10n.pomodoroFocusPhase,
      PomodoroPhase.paused => l10n.pomodoroPausedPhase,
      PomodoroPhase.breakTime => l10n.pomodoroBreakPhase,
      PomodoroPhase.finished => l10n.pomodoroFinishedPhase,
      PomodoroPhase.idle => '',
    };
    final nextFocus = ref.watch(pomodoroPrefsProvider).focusMinutes;
    final progress = isFinished ? 1.0 : p.progress.clamp(0.0, 1.0);

    // Ореол дышит только в фокусе и на перерыве; на паузе и в конце
    // контроллер стоит, чтобы не гнать кадры впустую.
    final breathing = p.phase == PomodoroPhase.focus || isBreak;
    if (breathing && !_breath.isAnimating) {
      _breath.repeat(reverse: true);
    } else if (!breathing && _breath.isAnimating) {
      _breath.stop();
    }

    final ring = LayoutBuilder(
      builder: (context, c) {
        final size = math.min(300.0, math.min(c.maxWidth, c.maxHeight));
        final stroke = size * 0.04;
        // Размытый ореол рисуется один раз в своём слое, а «дыхание» — только
        // прозрачность этого слоя: без размытия на каждом кадре.
        // Ореол в своём слое: на каждом кадре дыхания перерисовывается только
        // он, а кольцо и цифры — раз в секунду.
        final halo = RepaintBoundary(
          child: CustomPaint(
            size: Size.square(size),
            painter: _HaloPainter(
              color: accent,
              stroke: stroke,
              alpha: breathing
                  ? _breath
                      .drive(CurveTween(curve: Curves.easeInOut))
                      .drive(Tween(begin: 0.05, end: 0.12))
                  : const AlwaysStoppedAnimation(0.04),
            ),
          ),
        );
        return Stack(
          alignment: Alignment.center,
          children: [
            halo,
            RepaintBoundary(
              child: CustomPaint(
                size: Size.square(size),
                painter: _FocusRingPainter(
                  progress: progress,
                  color: accent,
                  track: dark ? AppColors.ringTrackDark : AppColors.ringTrack,
                  stroke: stroke,
                ),
                child: SizedBox.square(
                  dimension: size,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (isFinished)
                        Icon(
                          Icons.check_rounded,
                          size: size * 0.26,
                          color: accent,
                        )
                      else
                        AnimatedOpacity(
                          opacity: isPaused ? 0.45 : 1,
                          duration: const Duration(milliseconds: 250),
                          child: Text(
                            _mmss(p.remainingSeconds),
                            style: AppFonts.manrope(
                              fontSize: size * 0.22,
                              fontWeight: FontWeight.w700,
                              color: theme.colorScheme.onSurface,
                            ).copyWith(
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                              height: 1,
                            ),
                          ),
                        ),
                      const SizedBox(height: 8),
                      Text(
                        isFinished
                            ? phaseLine
                            : l10n.focusOfMinutes(p.totalSeconds ~/ 60),
                        style:
                            theme.textTheme.bodyMedium?.copyWith(color: muted),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );

    Widget round({
      required IconData icon,
      required String tooltip,
      required VoidCallback onPressed,
      bool big = false,
      bool danger = false,
    }) {
      final d = big ? 76.0 : 56.0;
      final fg = big
          ? Colors.white
          : danger
              ? AppColors.danger
              : theme.colorScheme.onSurface;
      return Tooltip(
        message: tooltip,
        child: Material(
          color: big ? accent : theme.colorScheme.surface,
          shape: CircleBorder(
            side: big
                ? BorderSide.none
                : BorderSide(
                    color: danger
                        ? AppColors.danger.withValues(alpha: 0.4)
                        : theme.colorScheme.onSurface.withValues(alpha: 0.18),
                  ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            child: SizedBox.square(
              dimension: d,
              child: Icon(icon, color: fg, size: big ? 34 : 24),
            ),
          ),
        ),
      );
    }

    const placeholder = SizedBox.square(dimension: 56);
    final controls = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        isFinished
            ? round(
                icon: Icons.close_rounded,
                tooltip: l10n.closeTooltip,
                onPressed: p.dismiss,
              )
            : round(
                icon: Icons.stop_rounded,
                tooltip: l10n.stopTooltip,
                onPressed: p.stop,
                danger: true,
              ),
        SizedBox(width: isFinished ? 16 : 28),
        if (isFinished)
          // Flexible: на узком телефоне подпись сжимается, а не вылезает.
          Flexible(
            child: FilledButton.icon(
              onPressed: p.anotherFocus,
              icon: const Icon(Icons.replay_rounded),
              label: Text(
                l10n.focusAnother(nextFocus),
                overflow: TextOverflow.ellipsis,
              ),
              style: FilledButton.styleFrom(
                backgroundColor: theme.colorScheme.primary,
                minimumSize: const Size(0, 56),
                padding: const EdgeInsets.symmetric(horizontal: 20),
                shape: const StadiumBorder(),
              ),
            ),
          )
        else if (isBreak)
          // На перерыве ставить на паузу нечего — главная кнопка пропускает
          // перерыв.
          round(
            icon: Icons.skip_next_rounded,
            tooltip: l10n.skipBreakTooltip,
            onPressed: p.skipBreak,
            big: true,
          )
        else
          round(
            icon: isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
            tooltip: isPaused ? l10n.resumeTooltip : l10n.pauseTooltip,
            onPressed: isPaused ? p.resume : p.pause,
            big: true,
          ),
        // Пустое место справа держит главную кнопку по центру.
        if (!isFinished) ...[const SizedBox(width: 28), placeholder],
      ],
    );

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): _close,
        const SingleActivator(LogicalKeyboardKey.space): () {
          if (p.phase == PomodoroPhase.focus) p.pause();
          if (isPaused) p.resume();
        },
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
              child: Column(
                children: [
                  Row(
                    children: [
                      TextButton.icon(
                        onPressed: _close,
                        icon: const Icon(Icons.keyboard_arrow_down_rounded),
                        label: Text(l10n.focusMinimize),
                        style: TextButton.styleFrom(foregroundColor: muted),
                      ),
                      const Spacer(),
                      if (p.sessionNumber > 0)
                        Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: Text(
                            l10n.focusSession(p.sessionNumber),
                            style: theme.textTheme.labelLarge
                                ?.copyWith(color: muted),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      phaseLine,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: accent,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Expanded(child: Center(child: ring)),
                  const SizedBox(height: 16),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: Text(
                      p.taskTitle,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppFonts.sourceSerif4(
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                        height: 1.25,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    height: 20,
                    child: p.sessionMinutes > 0
                        ? Text(
                            l10n.focusRecorded(p.sessionMinutes),
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: muted),
                          )
                        : null,
                  ),
                  const SizedBox(height: 28),
                  controls,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Мягкий ореол за кольцом; яркость дышит вместе с [alpha].
class _HaloPainter extends CustomPainter {
  _HaloPainter({required this.color, required this.stroke, required this.alpha})
      : super(repaint: alpha);

  final Color color;
  final double stroke;
  final Animation<double> alpha;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawCircle(
      size.center(Offset.zero),
      size.width / 2 + stroke / 2,
      Paint()
        ..color = color.withValues(alpha: alpha.value)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, stroke * 2),
    );
  }

  @override
  bool shouldRepaint(_HaloPainter o) =>
      o.color != color || o.stroke != stroke || o.alpha != alpha;
}

/// Кольцо отсчёта: дорожка и дуга оставшегося времени с точкой на конце.
class _FocusRingPainter extends CustomPainter {
  _FocusRingPainter({
    required this.progress,
    required this.color,
    required this.track,
    required this.stroke,
  });

  /// Сколько прошло, 0..1. Дуга показывает остаток: 1 − progress.
  final double progress;
  final Color color;
  final Color track;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2 - stroke;
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..color = track
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke,
    );
    // Завершённый цикл — полное кольцо; идущий — убывающая дуга.
    final left = progress >= 1 ? 1.0 : 1 - progress;
    if (left <= 0) return;
    final sweep = 2 * math.pi * left;
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r),
      -math.pi / 2,
      sweep,
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = stroke,
    );
    if (progress < 1) {
      final a = -math.pi / 2 + sweep;
      canvas.drawCircle(
        c + Offset(math.cos(a), math.sin(a)) * r,
        stroke * 0.85,
        Paint()..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(_FocusRingPainter o) =>
      o.progress != progress ||
      o.color != color ||
      o.track != track ||
      o.stroke != stroke;
}
