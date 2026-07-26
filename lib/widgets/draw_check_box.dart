import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';

/// Чекбокс редизайна «Живая бумага»: при выполнении галочка не появляется
/// мгновенно, а «прочерчивается» чернилами за 340 мс, и вокруг расходится
/// лёгкое всплеск-кольцо — маленький момент радости.
///
/// Поведение совместимо с [Checkbox]: [value] + [onChanged]. При сбросе
/// (true→false) анимация откатывается без всплеска.
class DrawCheckBox extends StatefulWidget {
  const DrawCheckBox({
    super.key,
    required this.value,
    required this.onChanged,
    this.size = 22,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final double size;

  @override
  State<DrawCheckBox> createState() => _DrawCheckBoxState();
}

class _DrawCheckBoxState extends State<DrawCheckBox>
    with TickerProviderStateMixin {
  // Прочерчивание галочки + заливка рамки (340 мс).
  late final AnimationController _draw = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 340),
    value: widget.value ? 1 : 0,
  );

  // Всплеск-кольцо: однократный «пинг» при выполнении.
  late final AnimationController _splash = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 460),
  );

  // Отображаемое состояние. По тапу меняется СРАЗУ (оптимистично) и тут же
  // запускает прочерчивание — модель обновится с задержкой, поэтому галочка
  // успевает дорисоваться до того, как плитка уедет в «Выполненные».
  late bool _checked = widget.value;

  @override
  void didUpdateWidget(DrawCheckBox old) {
    super.didUpdateWidget(old);
    // Внешняя смена value (напр. «отметить все», сброс, перерисовка списка),
    // которую мы ещё не отыграли локально.
    if (widget.value != _checked) {
      _checked = widget.value;
      _animateTo(_checked);
    }
  }

  void _animateTo(bool v) {
    if (v) {
      _draw.forward();
      _splash.forward(from: 0); // всплеск только при выполнении
    } else {
      _draw.reverse();
    }
  }

  @override
  void dispose() {
    _draw.dispose();
    _splash.dispose();
    super.dispose();
  }

  void _toggle() {
    if (widget.onChanged == null) return;
    setState(() => _checked = !_checked);
    _animateTo(_checked);
    widget.onChanged!(_checked);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final box = theme.colorScheme.onSurface.withValues(alpha: 0.32);
    // Зона тапа — как у штатного Checkbox (48dp), чтобы не сбить попадание.
    return InkResponse(
      onTap: widget.onChanged == null ? null : _toggle,
      radius: 24,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: SizedBox(
          width: widget.size,
          height: widget.size,
          child: AnimatedBuilder(
            animation: Listenable.merge([_draw, _splash]),
            builder: (context, _) {
              return CustomPaint(
                painter: _CheckPainter(
                  progress: AppColors.easeOut.transform(_draw.value),
                  splash: _splash.value,
                  accent: accent,
                  boxColor: box,
                  checkColor: theme.colorScheme.onPrimary,
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _CheckPainter extends CustomPainter {
  _CheckPainter({
    required this.progress,
    required this.splash,
    required this.accent,
    required this.boxColor,
    required this.checkColor,
  });

  /// 0 — пустая рамка, 1 — залито + галочка прочерчена.
  final double progress;

  /// 0..1 — фаза всплеск-кольца (0 — нет).
  final double splash;
  final Color accent;
  final Color boxColor;
  final Color checkColor;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final r = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(s * 0.3),
    );

    // ── Всплеск-кольцо: расходится и гаснет ──────────────────────────────
    if (splash > 0 && splash < 1) {
      final t = splash;
      final ringPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2 * (1 - t)
        ..color = accent.withValues(alpha: 0.35 * (1 - t));
      final radius = s * (0.55 + 0.6 * t);
      canvas.drawCircle(size.center(Offset.zero), radius, ringPaint);
    }

    // ── Рамка / заливка ──────────────────────────────────────────────────
    // Незаполненная рамка проявляется по мере прочерчивания (cross-fade
    // контура в залитый квадрат).
    final fill = Paint()
      ..style = PaintingStyle.fill
      ..color = Color.lerp(Colors.transparent, accent, progress)!;
    canvas.drawRRect(r, fill);

    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Color.lerp(boxColor, accent, progress)!;
    canvas.drawRRect(r.deflate(1), border);

    // ── Галочка: путь M3 9.5 L7.5 14 L15 4.5 (viewBox 18) ────────────────
    if (progress <= 0) return;
    final k = s / 18;
    final p0 = Offset(3 * k, 9.5 * k);
    final p1 = Offset(7.5 * k, 14 * k);
    final p2 = Offset(15 * k, 4.5 * k);

    // Длины двух сегментов — для равномерного «прочерчивания» по времени.
    final l1 = (p1 - p0).distance;
    final l2 = (p2 - p1).distance;
    final total = l1 + l2;
    final drawn = total * progress;

    final path = Path()..moveTo(p0.dx, p0.dy);
    if (drawn <= l1) {
      final f = drawn / l1;
      path.lineTo(p0.dx + (p1.dx - p0.dx) * f, p0.dy + (p1.dy - p0.dy) * f);
    } else {
      path.lineTo(p1.dx, p1.dy);
      final f = ((drawn - l1) / l2).clamp(0.0, 1.0);
      path.lineTo(p1.dx + (p2.dx - p1.dx) * f, p1.dy + (p2.dy - p1.dy) * f);
    }

    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4 * k
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = checkColor;
    canvas.drawPath(path, stroke);
  }

  @override
  bool shouldRepaint(_CheckPainter old) =>
      old.progress != progress ||
      old.splash != splash ||
      old.accent != accent;
}
