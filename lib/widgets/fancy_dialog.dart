import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import 'esc_dismissible.dart';

/// Общий «движок» появления fancy-диалогов: пружинный scale+fade поверх
/// затемнения. Используется и удобной обёрткой [showFancyDialog], и напрямую
/// для stateful-диалогов (оценка качества, фактическое время).
Future<T?> showFancyRawDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool autofocusEsc = true,
  String barrierLabel = 'dialog',
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: barrierLabel,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    transitionDuration: const Duration(milliseconds: 280),
    pageBuilder: (ctx, _, __) =>
        EscDismissible(autofocus: autofocusEsc, child: builder(ctx)),
    transitionBuilder: (ctx, animation, _, child) {
      final curved = CurvedAnimation(parent: animation, curve: AppColors.spring);
      return Opacity(
        opacity: animation.value.clamp(0.0, 1.0),
        child: Transform.scale(
          scale: 0.82 + 0.18 * curved.value.clamp(0.0, 1.4),
          child: child,
        ),
      );
    },
  );
}

/// Диалог с иконкой-медальоном и пружинным появлением — замена голому
/// [AlertDialog]. Иконка выезжает с лёгким перелётом чуть позже самого
/// диалога, отчего попап ощущается «живым», а не просто фейдится.
///
/// [contentBuilder] получает контекст диалога — удобно для вложенных кнопок
/// выбора (например, выбор типа удаления повторяющейся задачи).
/// Для диалогов с полем ввода (TextField с `autofocus: true`) передавай
/// `autofocusEsc: false`, иначе обёртка-Esc перехватит фокус у поля.
Future<T?> showFancyDialog<T>({
  required BuildContext context,
  required IconData icon,
  required Color iconColor,
  required String title,
  String? content,
  Widget Function(BuildContext dialogContext)? contentBuilder,
  List<Widget> Function(BuildContext dialogContext)? actions,
  bool autofocusEsc = true,
}) {
  return showFancyRawDialog<T>(
    context: context,
    autofocusEsc: autofocusEsc,
    barrierLabel: title,
    builder: (ctx) {
      Widget? body;
      if (contentBuilder != null) {
        body = contentBuilder(ctx);
      } else if (content != null) {
        body = Text(
          content,
          style: Theme.of(ctx)
              .textTheme
              .bodyMedium
              ?.copyWith(color: AppColors.textSecondary),
          textAlign: TextAlign.center,
        );
      }
      // Промежутки между кнопками задаёт сам Wrap (spacing ниже), поэтому
      // распорки, которые call-site'ы вставляли во времена Row, отбрасываем.
      // Иначе на переносе строки такая распорка застревает в конце первой
      // строки и сдвигает её на 8px относительно второй — кнопки выглядят
      // невыровненными по правому краю.
      // Отбрасываем только ПУСТЫЕ SizedBox — если внутри что-то есть, это
      // не распорка, а кнопка в обёртке, и терять её нельзя.
      final acts = [
        for (final w in actions?.call(ctx) ?? const <Widget>[])
          if (w is! SizedBox || w.child != null) w,
      ];
      return FancyDialogCard(
        icon: icon,
        iconColor: iconColor,
        title: title,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (body != null) ...[
              const SizedBox(height: 10),
              body,
            ],
            if (acts.isNotEmpty) ...[
              const SizedBox(height: 18),
              // Wrap, а не Row: карточка жёстко ограничена 360px, а подписи
              // кнопок бывают длинными (особенно по-русски) — три кнопки в
              // строку уже не влезают. Тот же случай, что чинили в
              // transfer_catchup_sheet.
              Wrap(
                alignment: WrapAlignment.end,
                // По центру, а не по верху: Row выравнивал так же, и кнопки
                // разных типов (TextButton/FilledButton) не «прыгают».
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: acts,
              ),
            ] else
              const SizedBox(height: 4),
          ],
        ),
      );
    },
  );
}

/// Визуальная «коробка» fancy-диалога: карточка с тёплой тенью, скруглением 24
/// и выпрыгивающим медальоном-иконкой сверху. Под медальоном — заголовок,
/// затем произвольный [child] (контент + кнопки). Stateful — ради анимации
/// медальона; сам [child] может быть любым, в т.ч. со своим состоянием.
class FancyDialogCard extends StatefulWidget {
  const FancyDialogCard({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.child,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final Widget child;

  @override
  State<FancyDialogCard> createState() => _FancyDialogCardState();
}

class _FancyDialogCardState extends State<FancyDialogCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _iconController;

  @override
  void initState() {
    super.initState();
    _iconController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );
    // Маленькая задержка, чтобы медальон «выскакивал» после самого диалога.
    Future<void>.delayed(const Duration(milliseconds: 90), () {
      if (mounted) _iconController.forward();
    });
  }

  @override
  void dispose() {
    _iconController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 360),
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
        decoration: BoxDecoration(
          color: theme.cardTheme.color ?? theme.cardColor,
          borderRadius: BorderRadius.circular(24),
          boxShadow: AppColors.raisedShadow,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ScaleTransition(
              scale: TweenSequence<double>([
                TweenSequenceItem(
                    tween: Tween(begin: 0.4, end: 1.12)
                        .chain(CurveTween(curve: Curves.easeOutBack)),
                    weight: 70),
                TweenSequenceItem(
                    tween: Tween(begin: 1.12, end: 1.0)
                        .chain(CurveTween(curve: Curves.easeOut)),
                    weight: 30),
              ]).animate(_iconController),
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.iconColor.withValues(alpha: 0.14),
                ),
                child: Icon(widget.icon, color: widget.iconColor, size: 32),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              widget.title,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            widget.child,
          ],
        ),
      ),
    );
  }
}
