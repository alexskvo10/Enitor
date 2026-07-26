import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/l10n_extensions.dart';
import '../services/pomodoro_controller.dart';

/// Баннер активного Помодоро-таймера. Скрыт, когда таймер не запущен.
/// Живёт на экране Задач над кольцами; состояние — в [pomodoroProvider],
/// поэтому переключение вкладок таймер не сбрасывает.
class PomodoroBanner extends ConsumerWidget {
  const PomodoroBanner({super.key});

  static String _mmss(int s) =>
      '${(s ~/ 60).toString().padLeft(2, '0')}:'
      '${(s % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(pomodoroProvider);
    if (!p.isActive) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final l10n = context.l10n;

    final isBreak = p.phase == PomodoroPhase.breakTime;
    final isFinished = p.phase == PomodoroPhase.finished;
    final cardColor = isBreak
        ? theme.colorScheme.tertiaryContainer.withValues(alpha: 0.4)
        : theme.colorScheme.primaryContainer.withValues(alpha: 0.4);

    final phaseLine = switch (p.phase) {
      PomodoroPhase.focus => l10n.pomodoroFocusPhase,
      PomodoroPhase.paused => l10n.pomodoroPausedPhase,
      PomodoroPhase.breakTime => l10n.pomodoroBreakPhase,
      PomodoroPhase.finished => l10n.pomodoroFinishedPhase,
      PomodoroPhase.idle => '',
    };
    final recorded = p.sessionMinutes > 0
        ? l10n.pomodoroRecordedSuffix(p.sessionMinutes)
        : '';

    return Card(
      margin: const EdgeInsets.only(bottom: 4),
      color: cardColor,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 6, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(
                  isBreak ? Icons.coffee_outlined : Icons.timer_outlined,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p.taskTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        '$phaseLine$recorded',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ),
                if (!isFinished) ...[
                  Text(
                    _mmss(p.remainingSeconds),
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
                // ── Кнопки по фазе ──────────────────────────────────────
                if (p.phase == PomodoroPhase.focus)
                  IconButton(
                    tooltip: l10n.pauseTooltip,
                    icon: const Icon(Icons.pause),
                    onPressed: p.pause,
                  ),
                if (p.phase == PomodoroPhase.paused)
                  IconButton(
                    tooltip: l10n.resumeTooltip,
                    icon: const Icon(Icons.play_arrow),
                    onPressed: p.resume,
                  ),
                if (isBreak)
                  IconButton(
                    tooltip: l10n.skipBreakTooltip,
                    icon: const Icon(Icons.skip_next),
                    onPressed: p.skipBreak,
                  ),
                if (isFinished)
                  TextButton(
                    onPressed: p.anotherFocus,
                    child: Text(l10n.anotherFocusBtn(kPomodoroFocusMinutes)),
                  ),
                IconButton(
                  tooltip: isFinished ? l10n.closeTooltip : l10n.stopTooltip,
                  icon: Icon(isFinished ? Icons.close : Icons.stop),
                  onPressed: isFinished ? p.dismiss : p.stop,
                ),
              ],
            ),
            if (!isFinished) ...[
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: p.progress,
                    minHeight: 5,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
