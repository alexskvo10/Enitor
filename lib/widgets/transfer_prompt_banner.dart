import 'dart:async';

import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../l10n/l10n_extensions.dart';

/// Баннер-уведомление сверху экрана с вопросом «перенести или нет» — тот же
/// визуальный язык, что и плашка о достижении (achievement_popup.dart):
/// выезжает сверху, пружинное появление, тень, скругление. В отличие от
/// неё — не чисто информационная, а с двумя действиями.
///
/// Возвращает `true` (перенести), `false` (нет — больше не предлагать) или
/// `null`, если баннер исчез сам (таймаут/смахивание вверх) — в этом случае
/// решение не принято, элемент останется кандидатом на следующий раз.
///
/// Возвращённый Future завершается только когда баннер исчез — вызывающий
/// код может показывать несколько по очереди (см. app_router.dart), не
/// давая им наслаиваться друг на друга.
Future<bool?> showTransferPromptBanner(
  BuildContext context, {
  required String title,
  required IconData icon,
}) {
  final overlay = Overlay.of(context, rootOverlay: true);
  final completer = Completer<bool?>();
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (ctx) => _TransferPromptBanner(
      title: title,
      icon: icon,
      onResolved: (result) {
        entry.remove();
        if (!completer.isCompleted) completer.complete(result);
      },
    ),
  );
  overlay.insert(entry);
  return completer.future;
}

class _TransferPromptBanner extends StatefulWidget {
  const _TransferPromptBanner({
    required this.title,
    required this.icon,
    required this.onResolved,
  });

  final String title;
  final IconData icon;
  final ValueChanged<bool?> onResolved;

  @override
  State<_TransferPromptBanner> createState() => _TransferPromptBannerState();
}

class _TransferPromptBannerState extends State<_TransferPromptBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entrance;
  double _dragOffset = 0;
  bool _resolving = false;
  Timer? _timeout;

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    )..forward();
    // Без явного выбора — просто уходит, элемент остаётся кандидатом.
    _timeout = Timer(const Duration(seconds: 8), () => _resolve(null));
  }

  @override
  void dispose() {
    _timeout?.cancel();
    _entrance.dispose();
    super.dispose();
  }

  Future<void> _resolve(bool? result) async {
    if (_resolving) return;
    _resolving = true;
    _timeout?.cancel();
    await _entrance.reverse();
    widget.onResolved(result);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
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
              final slide =
                  (1 - entranceCurve).clamp(-0.4, 1.4) * -90 + _dragOffset;
              final opacity = _entrance.value.clamp(0.0, 1.0) *
                  (1 - (_dragOffset.abs() / 140).clamp(0.0, 1.0));
              return Transform.translate(
                offset: Offset(0, slide),
                child: Opacity(opacity: opacity, child: child),
              );
            },
            child: GestureDetector(
              onVerticalDragUpdate: (d) {
                if (d.delta.dy < 0) setState(() => _dragOffset += d.delta.dy);
              },
              onVerticalDragEnd: (_) {
                if (_dragOffset < -24) {
                  _resolve(null);
                } else {
                  setState(() => _dragOffset = 0);
                }
              },
              child: Container(
                margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                constraints: const BoxConstraints(maxWidth: 420),
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                decoration: BoxDecoration(
                  color: theme.cardTheme.color ?? theme.cardColor,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: AppColors.raisedShadow,
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.2),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.primary.withValues(alpha: 0.14),
                          ),
                          child: Icon(widget.icon,
                              color: AppColors.primary, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                l10n.transferPromptLabel,
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.3,
                                ),
                              ),
                              const SizedBox(height: 2),
                              // Обрезается многоточием на узких экранах —
                              // полный текст по наведению/долгому нажатию.
                              Tooltip(
                                message: widget.title,
                                child: Text(
                                  widget.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleSmall
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => _resolve(false),
                          child: Text(l10n.transferPromptDecline),
                        ),
                        const SizedBox(width: 4),
                        FilledButton(
                          onPressed: () => _resolve(true),
                          child: Text(l10n.transferPromptAccept),
                        ),
                      ],
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
