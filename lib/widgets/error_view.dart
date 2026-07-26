import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../l10n/l10n_extensions.dart';

/// Дружелюбное состояние ошибки в стиле «Живой бумаги»: дудл-иконка «глиной»,
/// спокойный текст вместо голого «Ошибка: $e» и (опц.) кнопка «Повторить».
///
/// Технический текст ошибки пользователю не показываем — он ни о чём не говорит
/// и пугает. Если нужно — лог можно оставить в консоли на стороне вызова.
class ErrorView extends StatelessWidget {
  const ErrorView({
    super.key,
    this.onRetry,
    this.title,
    this.compact = false,
  });

  /// Колбэк «Повторить» (обычно `ref.invalidate(provider)`). null — без кнопки.
  final VoidCallback? onRetry;

  /// null — дефолтный локализованный текст.
  final String? title;

  /// Узкий вариант для инлайновых блоков (график, карточка) — мельче.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 24,
          vertical: compact ? 16 : 32,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_outlined,
              size: compact ? 26 : 34,
              color: AppColors.clay.withValues(alpha: 0.75),
            ),
            SizedBox(height: compact ? 8 : 12),
            Text(
              title ?? l10n.failedToLoad,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                height: 1.4,
              ),
            ),
            if (onRetry != null) ...[
              SizedBox(height: compact ? 8 : 14),
              TextButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, size: 18),
                label: Text(l10n.retryBtn),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
