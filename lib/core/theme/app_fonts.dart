import 'package:flutter/material.dart';

/// Точечные акцентные шрифты — забандлены в assets/fonts (см. pubspec.yaml),
/// без сетевого похода google_fonts. Сигнатура повторяет реально
/// используемые параметры `GoogleFonts.inter`/`GoogleFonts.sourceSerif4`.
abstract final class AppFonts {
  static TextStyle inter({
    TextStyle? textStyle,
    double? fontSize,
    FontWeight? fontWeight,
  }) =>
      (textStyle ?? const TextStyle()).copyWith(
        fontFamily: 'Inter',
        fontSize: fontSize,
        fontWeight: fontWeight,
      );

  static TextStyle manrope({
    TextStyle? textStyle,
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
  }) =>
      (textStyle ?? const TextStyle()).copyWith(
        fontFamily: 'Manrope',
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color,
      );

  static TextStyle sourceSerif4({
    TextStyle? textStyle,
    double? fontSize,
    FontWeight? fontWeight,
    FontStyle? fontStyle,
    double? height,
    Color? color,
  }) =>
      (textStyle ?? const TextStyle()).copyWith(
        fontFamily: 'SourceSerif4',
        fontSize: fontSize,
        fontWeight: fontWeight,
        fontStyle: fontStyle,
        height: height,
        color: color,
      );
}
