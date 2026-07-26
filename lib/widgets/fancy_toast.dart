import 'dart:async';

import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';

/// Тон тоста — задаёт акцентный цвет иконки/полоски.
enum ToastTone { success, info, error }

/// Показывает мягкий «тост» снизу экрана взамен голого [SnackBar]: карточка
/// с цветной иконкой выезжает снизу с пружинным перелётом, держится пару
/// секунд и плавно уходит. Совпадает с языком редизайна «Живая бумага»
/// (тёплая тень-наклейка, скруглённый медальон, акцентная полоска-корешок).
///
/// Тап по тосту закрывает его сразу. Длинный текст (например путь к файлу)
/// переносится и обрезается до трёх строк.
void showFancyToast(
  BuildContext context, {
  required String message,
  ToastTone tone = ToastTone.success,
  Duration duration = const Duration(milliseconds: 3200),
}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (ctx) => _FancyToast(
      message: message,
      tone: tone,
      duration: duration,
      onDismissed: () => entry.remove(),
    ),
  );
  overlay.insert(entry);
}

class _FancyToast extends StatefulWidget {
  const _FancyToast({
    required this.message,
    required this.tone,
    required this.duration,
    required this.onDismissed,
  });

  final String message;
  final ToastTone tone;
  final Duration duration;
  final VoidCallback onDismissed;

  @override
  State<_FancyToast> createState() => _FancyToastState();
}

class _FancyToastState extends State<_FancyToast>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _leaving = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 460),
      reverseDuration: const Duration(milliseconds: 260),
    )..forward();
    _timer = Timer(widget.duration, _dismiss);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _dismiss() async {
    if (_leaving) return;
    _leaving = true;
    _timer?.cancel();
    if (mounted) await _controller.reverse();
    widget.onDismissed();
  }

  (IconData, Color) get _toneStyle => switch (widget.tone) {
        ToastTone.success => (Icons.check_circle_rounded, AppColors.success),
        ToastTone.info => (Icons.info_rounded, AppColors.primary),
        ToastTone.error => (Icons.error_rounded, AppColors.danger),
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icon, accent) = _toneStyle;
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: SafeArea(
        child: Align(
          alignment: Alignment.bottomCenter,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              final t = CurvedAnimation(
                parent: _controller,
                curve: AppColors.spring,
                reverseCurve: Curves.easeIn,
              ).value;
              return Opacity(
                opacity: _controller.value.clamp(0.0, 1.0),
                child: Transform.translate(
                  offset: Offset(0, (1 - t) * 60),
                  child: child,
                ),
              );
            },
            child: GestureDetector(
              onTap: _dismiss,
              child: Container(
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 18),
                constraints: const BoxConstraints(maxWidth: 460),
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: theme.cardTheme.color ?? theme.cardColor,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: AppColors.raisedShadow,
                  border: Border.all(
                    color: accent.withValues(alpha: 0.22),
                  ),
                ),
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Цветной «корешок» слева — как у плиток задач.
                      Container(width: 4, color: accent),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
                        child: Icon(icon, color: accent, size: 22),
                      ),
                      Expanded(
                        child: Padding(
                          padding:
                              const EdgeInsets.fromLTRB(0, 12, 14, 12),
                          child: Text(
                            widget.message,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
