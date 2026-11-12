import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../l10n/l10n_extensions.dart';
import '../../../widgets/fancy_toast.dart';

// Те же «кирпичи», что у экрана Настроек (заголовок секции капсом цвета
// primary, карточка, приглушённая сноска): экран «Интеграции» продолжает
// Настройки и должен выглядеть их частью.

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
        child: Text(
          text.toUpperCase(),
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                letterSpacing: 0.8,
                fontWeight: FontWeight.w700,
              ),
        ),
      );
}

class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        clipBehavior: Clip.antiAlias,
        // stretch: подписи внутри карточки — слева, как текст строк, а не
        // по центру.
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      );
}

class SectionNote extends StatelessWidget {
  const SectionNote(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 2, 20, 8),
        child: Text(
          text,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                // 0.7, а не 0.5, как у сносок Настроек: при 0.5–0.6 мелкий
                // текст не дотягивает до контраста 4.5:1.
                color: Theme.of(context).colorScheme.onSurface.withValues(
                      alpha: 0.7,
                    ),
              ),
        ),
      );
}

class TileTitle extends StatelessWidget {
  const TileTitle(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: Theme.of(context)
            .textTheme
            .titleMedium
            ?.copyWith(fontWeight: FontWeight.w700),
      );
}

const tileDivider = Divider(height: 1, indent: 16, endIndent: 16);

/// Моноширинный блок с кнопкой «Скопировать»: пример команды, путь, JSON.
class CopyBlock extends StatelessWidget {
  const CopyBlock({super.key, required this.text, this.label});

  final String text;

  /// Подпись кнопки для экранного диктора: что именно копируется.
  final String? label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 8, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(10),
              ),
              // Обычный текст, не выделяемый: копирует кнопка рядом, а
              // выделяемое поле — лишняя мелкая цель касания.
              child: Text(
                text,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                  fontFamilyFallback: const ['Consolas', 'Courier New'],
                  height: 1.4,
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: label ?? l10n.copyAction,
            icon: const Icon(Icons.copy_rounded, size: 20),
            onPressed: () => copyWithToast(context, text),
          ),
        ],
      ),
    );
  }
}

Future<void> copyWithToast(BuildContext context, String text) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) {
    showFancyToast(context, message: context.l10n.copiedToClipboard);
  }
}
