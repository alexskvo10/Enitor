import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../core/theme/app_colors.dart';
import '../data/models/achievement.dart';
import '../l10n/l10n_extensions.dart';

/// Показывает праздничную плашку о новом достижении сверху экрана:
/// медальон с эмодзи выезжает с лёгким перелётом, искры разлетаются в
/// стороны и гаснут, фон мягко пульсирует. Автоматически прячется через
/// несколько секунд либо по тапу/свайпу вверх.
///
/// Возвращённый Future завершается, когда плашка исчезла — вызывающий код
/// может показывать достижения по очереди (см. app_router.dart).
Future<void> showAchievementPopup(
  BuildContext context,
  AchievementDef def,
) async {
  final overlay = Overlay.of(context, rootOverlay: true);
  final completer = Completer<void>();
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (ctx) => _AchievementBanner(
      def: def,
      onDismissed: () {
        entry.remove();
        if (!completer.isCompleted) completer.complete();
      },
    ),
  );
  overlay.insert(entry);
  return completer.future;
}

class _AchievementBanner extends StatefulWidget {
  const _AchievementBanner({required this.def, required this.onDismissed});

  final AchievementDef def;
  final VoidCallback onDismissed;

  @override
  State<_AchievementBanner> createState() => _AchievementBannerState();
}

class _AchievementBannerState extends State<_AchievementBanner>
    with TickerProviderStateMixin {
  late final AnimationController _entrance;
  late final AnimationController _pulse;
  double _dragOffset = 0;
  bool _dismissing = false;

  static const _sparkCount = 7;
  late final List<double> _sparkAngles;

  @override
  void initState() {
    super.initState();
    _sparkAngles = List.generate(
      _sparkCount,
      (i) => (i / _sparkCount) * 2 * math.pi + (i.isEven ? 0.18 : -0.12),
    );
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    )..forward();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);

    SchedulerBinding.instance.addPostFrameCallback((_) async {
      await Future<void>.delayed(const Duration(milliseconds: 3600));
      if (mounted) _dismiss();
    });
  }

  @override
  void dispose() {
    _entrance.dispose();
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _dismiss() async {
    if (_dismissing) return;
    _dismissing = true;
    await _entrance.reverse();
    widget.onDismissed();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: AnimatedBuilder(
            animation: _entrance,
            builder: (context, child) {
              final entranceCurve = CurvedAnimation(
                parent: _entrance,
                curve: AppColors.spring,
                reverseCurve: Curves.easeIn,
              ).value;
              final slide = (1 - entranceCurve).clamp(-0.4, 1.4) * -90 +
                  _dragOffset;
              final opacity = (_entrance.value).clamp(0.0, 1.0) *
                  (1 - (_dragOffset.abs() / 140).clamp(0.0, 1.0));
              return Transform.translate(
                offset: Offset(0, slide),
                child: Opacity(opacity: opacity, child: child),
              );
            },
            child: GestureDetector(
              onTap: _dismiss,
              onVerticalDragUpdate: (d) {
                if (d.delta.dy < 0) {
                  setState(() => _dragOffset += d.delta.dy);
                }
              },
              onVerticalDragEnd: (_) {
                if (_dragOffset < -24) {
                  _dismiss();
                } else {
                  setState(() => _dragOffset = 0);
                }
              },
              child: Container(
                margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                constraints: const BoxConstraints(maxWidth: 420),
                padding: const EdgeInsets.fromLTRB(14, 14, 18, 14),
                decoration: BoxDecoration(
                  color: theme.cardTheme.color ?? theme.cardColor,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: AppColors.raisedShadow,
                  border: Border.all(
                    color: AppColors.clay.withValues(alpha: 0.25),
                  ),
                ),
                child: Row(
                  children: [
                    _EmojiMedallion(
                      emoji: widget.def.emoji,
                      entrance: _entrance,
                      pulse: _pulse,
                      sparkAngles: _sparkAngles,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            context.l10n.newAchievementLabel,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: AppColors.clay,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.4,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.def.localizedTitle(
                                Localizations.localeOf(context).languageCode ==
                                    'ru'),
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          Text(
                            widget.def.localizedDescription(
                                Localizations.localeOf(context).languageCode ==
                                    'ru'),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmojiMedallion extends StatelessWidget {
  const _EmojiMedallion({
    required this.emoji,
    required this.entrance,
    required this.pulse,
    required this.sparkAngles,
  });

  final String emoji;
  final AnimationController entrance;
  final AnimationController pulse;
  final List<double> sparkAngles;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 60,
      height: 60,
      child: AnimatedBuilder(
        animation: Listenable.merge([entrance, pulse]),
        builder: (context, _) {
          final pop = TweenSequence<double>([
            TweenSequenceItem(
                tween: Tween(begin: 0.3, end: 1.18)
                    .chain(CurveTween(curve: Curves.easeOutBack)),
                weight: 65),
            TweenSequenceItem(
                tween: Tween(begin: 1.18, end: 1.0)
                    .chain(CurveTween(curve: Curves.easeOut)),
                weight: 35),
          ]).transform(entrance.value.clamp(0.0, 1.0));
          final glow = 0.18 + 0.1 * pulse.value;
          // Искры летят наружу и гаснут в первой половине появления.
          final sparkT = (entrance.value * 1.6).clamp(0.0, 1.0);
          return Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.clay.withValues(alpha: glow),
                ),
              ),
              for (final angle in sparkAngles)
                Transform.translate(
                  offset: Offset(
                    math.cos(angle) * 34 * sparkT,
                    math.sin(angle) * 34 * sparkT,
                  ),
                  child: Opacity(
                    opacity: (1 - sparkT).clamp(0.0, 1.0),
                    child: Transform.scale(
                      scale: 0.5 + 0.5 * (1 - sparkT),
                      child: const Icon(Icons.auto_awesome,
                          size: 10, color: AppColors.clay),
                    ),
                  ),
                ),
              Transform.scale(
                scale: pop,
                child: Text(emoji, style: const TextStyle(fontSize: 30)),
              ),
            ],
          );
        },
      ),
    );
  }
}
