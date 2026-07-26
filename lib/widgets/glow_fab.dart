import 'package:flutter/material.dart';

import '../core/theme/app_fonts.dart';

/// Плавающая pill-кнопка «+ Задача/Цель»: сплошная заливка primary, белый
/// текст Manrope 700/15, слева плюс тем же цветом (currentColor). Тень
/// двойная — приподнятая (Material elevation) плюс мягкое цветовое свечение
/// акцента снаружи контура.
class GlowFab extends StatelessWidget {
  const GlowFab({
    super.key,
    required this.onPressed,
    required this.icon,
    required this.label,
  });

  final VoidCallback onPressed;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final fabTheme = Theme.of(context).floatingActionButtonTheme;
    final bg = fabTheme.backgroundColor ?? Theme.of(context).colorScheme.primary;
    final fg = fabTheme.foregroundColor ?? Theme.of(context).colorScheme.onPrimary;
    const shape = StadiumBorder();
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: bg.withValues(alpha: 0.45),
            blurRadius: 18,
            spreadRadius: -2,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: bg,
        shape: shape,
        elevation: 2,
        shadowColor: Colors.black.withValues(alpha: 0.3),
        child: InkWell(
          customBorder: shape,
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 22),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 20, color: fg),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: AppFonts.manrope(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: fg,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
