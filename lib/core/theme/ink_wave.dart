import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Волна нажатия Enitor — одна на Android, Windows и в тестах.
///
/// Чем не устроили штатные (M3 по умолчанию):
/// * Android брал [InkSparkle]: центр уезжает от пальца к середине плитки,
///   зерно шейдера мерцает, нет cancel/confirm — при прокрутке волна
///   доигрывает целиком, при удержании гаснет через 0,6 с под пальцем,
///   а первое касание после запуска пустое, пока шейдер компилируется.
/// * Windows брал [InkRipple]: стартует сразу с 30 % радиуса и тоже едет
///   к центру — другая волна, чем на телефоне.
///
/// Здесь: центр стоит в точке касания, радиус — до дальнего угла плитки
/// (закрывает её целиком при любой точке), обрезка по `customBorder` /
/// `borderRadius` — как у штатных через [paintInkCircle]. Пока палец
/// держит — волна дорастает и стоит; после отпускания плавно гаснет;
/// отмена (прокрутка, увёл палец) — быстро тает на месте.
class InkWave extends InteractiveInkFeature {
  InkWave({
    required MaterialInkController controller,
    required super.referenceBox,
    required Offset position,
    required super.color,
    required TextDirection textDirection,
    bool containedInkWell = false,
    RectCallback? rectCallback,
    BorderRadius? borderRadius,
    super.customBorder,
    double? radius,
    super.onRemoved,
  })  : _position = position,
        _textDirection = textDirection,
        _borderRadius = borderRadius ?? BorderRadius.zero,
        _clipCallback = containedInkWell
            ? (rectCallback ?? () => Offset.zero & referenceBox.size)
            : null,
        super(controller: controller) {
    _targetRadius = radius ??
        (_clipCallback != null
            ? coverRadius(_clipCallback(), position)
            : Material.defaultSplashRadius);
    _grow = AnimationController(duration: holdGrow, vsync: controller.vsync)
      ..addListener(controller.markNeedsPaint)
      ..addStatusListener(_onGrowStatus)
      ..forward();
    _fadeIn = AnimationController(duration: fadeIn, vsync: controller.vsync)
      ..addListener(controller.markNeedsPaint)
      ..forward();
    _fadeOut = AnimationController(vsync: controller.vsync)
      ..addListener(controller.markNeedsPaint)
      ..addStatusListener(_onFadeOutStatus);
    controller.addInkFeature(this);
  }

  /// Рост, пока палец держит (без отпускания волна дорастает за это время).
  static const holdGrow = Duration(milliseconds: 550);

  /// Рост после отпускания — короткий тап не ждёт медленную волну.
  static const tapGrow = Duration(milliseconds: 240);
  static const fadeIn = Duration(milliseconds: 60);
  static const fadeOut = Duration(milliseconds: 280);
  static const cancelFade = Duration(milliseconds: 120);

  static const InteractiveInkFeatureFactory splashFactory = _InkWaveFactory();

  /// Радиус круга с центром [p], закрывающего [rect] целиком: расстояние
  /// до самого дальнего угла (+1 пиксель на сглаживание края).
  static double coverRadius(Rect rect, Offset p) {
    final dx = math.max((p.dx - rect.left).abs(), (rect.right - p.dx).abs());
    final dy = math.max((p.dy - rect.top).abs(), (rect.bottom - p.dy).abs());
    return math.sqrt(dx * dx + dy * dy) + 1;
  }

  final Offset _position;
  final TextDirection _textDirection;
  final BorderRadius _borderRadius;
  final RectCallback? _clipCallback;
  late final double _targetRadius;

  late final AnimationController _grow;
  late final AnimationController _fadeIn;
  late final AnimationController _fadeOut;
  bool _confirmed = false;

  static const Curve _growCurve = Curves.easeOutCubic;

  @override
  void confirm() {
    _confirmed = true;
    _fadeIn.forward(); // после cancel → confirm волна снова видна
    if (_grow.isCompleted) {
      _startFadeOut(fadeOut);
    } else {
      // Ускоряем остаток роста; значение непрерывно — без рывка.
      final left = (tapGrow.inMicroseconds * (1 - _grow.value)).round();
      _grow.animateTo(1, duration: Duration(microseconds: math.max(left, 1)));
    }
  }

  @override
  void cancel() {
    _fadeIn.stop();
    _startFadeOut(cancelFade);
  }

  void _onGrowStatus(AnimationStatus s) {
    if (s.isCompleted && _confirmed) _startFadeOut(fadeOut);
  }

  void _startFadeOut(Duration d) {
    if (_fadeOut.isAnimating || _fadeOut.isCompleted) return;
    _fadeOut.animateTo(1, duration: d, curve: Curves.easeOut);
  }

  void _onFadeOutStatus(AnimationStatus s) {
    if (s.isCompleted) dispose();
  }

  @override
  void dispose() {
    _grow.dispose();
    _fadeIn.dispose();
    _fadeOut.dispose();
    super.dispose();
  }

  @override
  void paintFeature(Canvas canvas, Matrix4 transform) {
    final opacity = _fadeIn.value * (1 - _fadeOut.value);
    if (opacity <= 0) return;
    paintInkCircle(
      canvas: canvas,
      transform: transform,
      paint: Paint()..color = color.withValues(alpha: color.a * opacity),
      center: _position,
      radius: _targetRadius * _growCurve.transform(_grow.value),
      textDirection: _textDirection,
      customBorder: customBorder,
      borderRadius: _borderRadius,
      clipCallback: _clipCallback,
    );
  }
}

class _InkWaveFactory extends InteractiveInkFeatureFactory {
  const _InkWaveFactory();

  @override
  InteractiveInkFeature create({
    required MaterialInkController controller,
    required RenderBox referenceBox,
    required Offset position,
    required Color color,
    required TextDirection textDirection,
    bool containedInkWell = false,
    RectCallback? rectCallback,
    BorderRadius? borderRadius,
    ShapeBorder? customBorder,
    double? radius,
    VoidCallback? onRemoved,
  }) =>
      InkWave(
        controller: controller,
        referenceBox: referenceBox,
        position: position,
        color: color,
        textDirection: textDirection,
        containedInkWell: containedInkWell,
        rectCallback: rectCallback,
        borderRadius: borderRadius,
        customBorder: customBorder,
        radius: radius,
        onRemoved: onRemoved,
      );
}
