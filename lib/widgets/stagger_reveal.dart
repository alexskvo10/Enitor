import 'dart:async';

import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';

/// Каскадное появление элемента списка: fade + лёгкий сдвиг снизу, со сдвигом
/// старта по индексу (`index * 45мс`, до ~360мс). Играет один раз при
/// монтировании — при первой отрисовке списка и при смене дня/периода
/// (новые элементы монтируются заново). Ключ задавать по id элемента.
class StaggerReveal extends StatefulWidget {
  const StaggerReveal({
    super.key,
    required this.index,
    required this.child,
    this.active = true,
  });

  final int index;
  final Widget child;

  /// Пока false — элемент скрыт и каскад НЕ запускается. Когда станет true —
  /// каскад играет один раз и остаётся видимым (для вкладок, которые
  /// `TabBarView` строит за кадром: иначе анимация прошла бы не на виду).
  final bool active;

  @override
  State<StaggerReveal> createState() => _StaggerRevealState();
}

class _StaggerRevealState extends State<StaggerReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
  );
  late final Animation<double> _t =
      CurvedAnimation(parent: _c, curve: AppColors.easeOut);
  Timer? _timer;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    if (widget.active) _start();
  }

  @override
  void didUpdateWidget(StaggerReveal old) {
    super.didUpdateWidget(old);
    // Вкладка стала активной — запускаем каскад (один раз).
    if (widget.active && !_started) _start();
  }

  void _start() {
    _started = true;
    final delay = Duration(milliseconds: (widget.index * 45).clamp(0, 360));
    _timer = Timer(delay, () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _t,
      child: widget.child,
      builder: (context, child) => Opacity(
        opacity: _t.value,
        child: Transform.translate(
          offset: Offset(0, 10 * (1 - _t.value)),
          child: child,
        ),
      ),
    );
  }
}
