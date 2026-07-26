import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Закрывает текущий диалог/шит по Esc — удобство на десктопе (на мобиле Esc
/// нет, поведение не меняется).
///
/// Esc-событие ловится, только если в поддереве есть сфокусированный элемент,
/// от которого оно всплывёт сюда. Когда форма автофокусит своё поле ввода —
/// этого достаточно. Если же фокусироваться нечему (диалог без полей, форма
/// редактирования без автофокуса) — выстави [autofocus] true, чтобы обёртка
/// сама взяла фокус.
class EscDismissible extends StatelessWidget {
  const EscDismissible({
    super.key,
    required this.child,
    this.autofocus = false,
    this.onDismiss,
  });

  final Widget child;
  final bool autofocus;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    Widget content = child;
    if (autofocus) {
      content = Focus(autofocus: true, child: content);
    }
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape):
            onDismiss ?? () => Navigator.of(context).maybePop(),
      },
      child: content,
    );
  }
}
