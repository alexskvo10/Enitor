import 'package:flutter/material.dart';

import '../core/theme/app_fonts.dart';

/// Маленькая пилюля-тег («#labels») — общий стиль для тегов и у задач, и у
/// целей.
class TagMini extends StatelessWidget {
  const TagMini({super.key, required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '#$label',
        style: AppFonts.inter(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
        ).copyWith(color: c),
      ),
    );
  }
}
