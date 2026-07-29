import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_colors.dart';
import '../l10n/l10n_extensions.dart';
import '../services/pomodoro_controller.dart';

/// Баннер активного Помодоро-таймера. Скрыт, когда таймер не запущен.
/// Живёт на экране Задач над кольцами; состояние — в [pomodoroProvider],
/// поэтому переключение вкладок таймер не сбрасывает.
class PomodoroBanner extends ConsumerWidget {
  const PomodoroBanner({super.key});

  static String _mmss(int s) => '${(s ~/ 60).toString().padLeft(2, '0')}:'
      '${(s % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(pomodoroProvider);
    if (!p.isActive) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final l10n = context.l10n;

    final isBreak = p.phase == PomodoroPhase.breakTime;
    final isFinished = p.phase == PomodoroPhase.finished;
    final isDark = theme.brightness == Brightness.dark;
    // Фокус — фирменный синий, перерыв — тёплая «Глина»: акцент карточки,
    // медальона, времени и свечения меняется вместе с фазой. В тёмной теме
    // берём высветленные варианты (primarySoft/claySoft) — как и везде в
    // приложении, обычный оттенок на угольном фоне теряет контраст.
    final accent = isBreak
        ? (isDark ? AppColors.claySoft : AppColors.clay)
        : theme.colorScheme.primary;

    final phaseLine = switch (p.phase) {
      PomodoroPhase.focus => l10n.pomodoroFocusPhase,
      PomodoroPhase.paused => l10n.pomodoroPausedPhase,
      PomodoroPhase.breakTime => l10n.pomodoroBreakPhase,
      PomodoroPhase.finished => l10n.pomodoroFinishedPhase,
      PomodoroPhase.idle => '',
    };
    final sessionSuffix =
        p.sessionNumber > 0 ? l10n.pomodoroSessionSuffix(p.sessionNumber) : '';
    final recorded = p.sessionMinutes > 0
        ? l10n.pomodoroRecordedSuffix(p.sessionMinutes)
        : '';

    // Сплошная поверхность + тонкая рамка — тот же приём, что у SegChip
    // (неактивная пилюля на поверхности): полупрозрачная плашка на фоне
    // самой карточки (тоже полупрозрачной, тонированной акцентом) сливалась
    // и была почти не видна в обеих темах.
    Widget pillButton({
      required IconData icon,
      required String tooltip,
      required VoidCallback onPressed,
      bool danger = false,
    }) {
      final bg = danger
          ? AppColors.danger.withValues(alpha: 0.14)
          : theme.colorScheme.surface;
      final borderColor = danger
          ? AppColors.danger.withValues(alpha: 0.35)
          : theme.colorScheme.onSurface.withValues(alpha: 0.18);
      final fg = danger ? AppColors.danger : theme.colorScheme.onSurface;
      return Tooltip(
        message: tooltip,
        child: Material(
          color: bg,
          shape: CircleBorder(side: BorderSide(color: borderColor)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            child: Padding(
              padding: const EdgeInsets.all(7),
              child: Icon(icon, size: 18, color: fg),
            ),
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        // Цветное свечение вместо обычной тени (та же техника, что у
        // GlowFab): мягкий ореол акцентного цвета под карточкой, не резкая
        // серая тень. Меняет цвет вместе с фазой — карточка «дышит» вместе
        // с таймером, а не просто лежит поверх остального интерфейса.
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.35),
            blurRadius: 20,
            spreadRadius: -4,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Card(
        margin: EdgeInsets.zero,
        // alphaBlend поверх непрозрачной surface, а не голый
        // accent.withValues(alpha: 0.08) — иначе Card.color сам полупрозрачный,
        // и сквозь карточку просвечивает фон (баг: «таймер прозрачный»).
        color: Color.alphaBlend(
          accent.withValues(alpha: 0.08),
          theme.colorScheme.surface,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: accent.withValues(alpha: 0.16),
                    ),
                    child: Icon(
                      isBreak ? Icons.coffee_outlined : Icons.timer_outlined,
                      color: accent,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    // Заголовок задачи обрезается многоточием на узких
                    // экранах — полный текст доступен по наведению (десктоп)
                    // или долгому нажатию (телефон), как у кнопок-пилюль.
                    child: Tooltip(
                      message:
                          '${p.taskTitle}\n$phaseLine$sessionSuffix$recorded',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            p.taskTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          Text(
                            '$phaseLine$sessionSuffix$recorded',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (!isFinished) ...[
                    Text(
                      _mmss(p.remainingSeconds),
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: accent,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  // ── Кнопки по фазе ──────────────────────────────────────
                  if (p.phase == PomodoroPhase.focus)
                    pillButton(
                      icon: Icons.pause,
                      tooltip: l10n.pauseTooltip,
                      onPressed: p.pause,
                    ),
                  if (p.phase == PomodoroPhase.paused)
                    pillButton(
                      icon: Icons.play_arrow,
                      tooltip: l10n.resumeTooltip,
                      onPressed: p.resume,
                    ),
                  if (isBreak)
                    pillButton(
                      icon: Icons.skip_next,
                      tooltip: l10n.skipBreakTooltip,
                      onPressed: p.skipBreak,
                    ),
                  if (isFinished)
                    Flexible(
                      // Текст в две строки, а не в одну широкую: иначе пилюля
                      // растягивается вбок и отжимает заголовок/фазу слева
                      // (там и без того «Cycle done · Session N · +N min»).
                      child: Material(
                        color: accent.withValues(alpha: 0.14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: p.anotherFocus,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  l10n.anotherFocusBtnLine1,
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    color: accent,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  l10n.anotherFocusBtnLine2(
                                      kPomodoroFocusMinutes),
                                  style: theme.textTheme.labelSmall
                                      ?.copyWith(color: accent),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(width: 6),
                  // Стоп — акцентно красная (деструктивное действие: сбрасывает
                  // текущий цикл), «Готово → Закрыть» остаётся нейтральной.
                  pillButton(
                    icon: isFinished ? Icons.close : Icons.stop,
                    tooltip: isFinished ? l10n.closeTooltip : l10n.stopTooltip,
                    onPressed: isFinished ? p.dismiss : p.stop,
                    danger: !isFinished,
                  ),
                ],
              ),
              if (!isFinished) ...[
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: p.progress,
                      minHeight: 5,
                      color: accent,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
