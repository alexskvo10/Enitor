import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';

/// Кольцо продуктивности: визуализация процента выполненных задач.
///
/// Параметры:
///   [value]      — 0..1 (доля). null → пустое кольцо с тире в центре.
///   [size]       — внешний диаметр.
///   [strokeWidth]— толщина кольца.
///   [done], [total] — для подписи в центре.
///   [ringColors] — цвета градиента дуги (2+). null → стандартный градиент приложения.
class ProductivityRing extends StatelessWidget {
  const ProductivityRing({
    super.key,
    required this.value,
    this.size = 200,
    this.strokeWidth = 14,
    this.done,
    this.total,
    this.duration = const Duration(milliseconds: 1100),
    this.ringColors,
    this.subtitle,
  });

  final double? value;
  final double size;
  final double strokeWidth;
  final int? done;
  final int? total;
  final Duration duration;

  /// Переопределяет подпись «done / total» под процентом (напр. для дробного «3.6 / 5»).
  final String? subtitle;

  /// Если задан — переопределяет стандартный градиент кольца.
  final List<Color>? ringColors;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final trackColor = isDark ? AppColors.ringTrackDark : AppColors.ringTrack;
    final target = (value ?? 0).clamp(0.0, 1.0);

    return SizedBox(
      width: size,
      height: size,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: target),
        duration: duration,
        // Пружинный довод дуги («живая бумага»). Дуга может слегка перелетать
        // цель и возвращаться; число при этом клампим к цели — count-up без
        // дёрганья назад.
        curve: AppColors.spring,
        builder: (context, animated, _) {
          return Stack(
            alignment: Alignment.center,
            children: [
              CustomPaint(
                size: Size.square(size),
                painter: _RingPainter(
                  progress: animated,
                  strokeWidth: strokeWidth,
                  trackColor: trackColor,
                  gradient: ringColors ?? AppColors.ringGradient,
                ),
              ),
              _RingLabel(
                value: value,
                done: done,
                total: total,
                animated: animated.clamp(0.0, target),
                subtitle: subtitle,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _RingLabel extends StatelessWidget {
  const _RingLabel({
    required this.value,
    required this.done,
    required this.total,
    required this.animated,
    this.subtitle,
  });

  final double? value;
  final int? done;
  final int? total;
  final double animated;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (value == null) {
      return Text(
        '—',
        style: theme.textTheme.headlineMedium?.copyWith(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
        ),
      );
    }

    final percent = (animated * 100).round();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$percent%',
          style: theme.textTheme.headlineLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        if (subtitle != null || (done != null && total != null)) ...[
          const SizedBox(height: 4),
          Text(
            subtitle ?? '$done / $total',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ],
      ],
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.progress,
    required this.strokeWidth,
    required this.trackColor,
    required this.gradient,
  });

  final double progress;
  final double strokeWidth;
  final Color trackColor;
  final List<Color> gradient;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (math.min(size.width, size.height) - strokeWidth) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = trackColor;
    canvas.drawCircle(center, radius, trackPaint);

    if (progress <= 0) return;

    const start = -math.pi / 2;
    // Не даём дуге «перелетать» полный круг (пружинный перелёт > 100%): иначе
    // круглый колпачок конца наезжает на начало — видна «заплатка».
    final p = progress.clamp(0.0, 1.0);
    final sweep = 2 * math.pi * p;
    // СИММЕТРИЧНЫЙ градиент по всему кругу (тёмный → светлый → тёмный): оба
    // конца одного цвета → нет «шва» на полном кольце; на частичной дуге —
    // плавный односторонний переход без резкой границы.
    final colors = gradient.length >= 2
        ? [gradient.first, gradient.last, gradient.first]
        : gradient;
    final shader = SweepGradient(
      startAngle: start,
      endAngle: start + 2 * math.pi,
      colors: colors,
    ).createShader(rect);

    // Мягкое свечение ПОД заполненной дугой (тем же градиентом, размытое) —
    // только на заполнении, трек не светится.
    final glowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..shader = shader
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawArc(rect, start, sweep, false, glowPaint);

    final progressPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..shader = shader;
    canvas.drawArc(rect, start, sweep, false, progressPaint);
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress ||
      old.strokeWidth != strokeWidth ||
      old.trackColor != trackColor;
}
