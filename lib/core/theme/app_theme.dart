import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_fonts.dart';

/// Темы «Бумажный журнал»: Manrope — заголовки/числа, Inter — текст.
/// Scaffold и AppBar ПРОЗРАЧНЫ: фон (цвет + текстура) рисует [AppBackground]
/// через MaterialApp.builder — так текстура сплошная под всеми экранами.
abstract final class AppTheme {
  /// Inter для текста + Manrope для заголовков и крупных чисел. Оба
  /// забандлены в assets (см. pubspec.yaml) — apply() лишь подставляет
  /// fontFamily, веса каждого слота остаются материаловскими дефолтами.
  static TextTheme _textTheme(TextTheme base, Color color) {
    final body = base.apply(fontFamily: 'Inter');
    final head = base.apply(fontFamily: 'Manrope');
    return body
        .copyWith(
          displayLarge: head.displayLarge,
          displayMedium: head.displayMedium,
          displaySmall: head.displaySmall,
          headlineLarge:
              head.headlineLarge?.copyWith(fontWeight: FontWeight.w800),
          headlineMedium:
              head.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
          headlineSmall:
              head.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          titleLarge: head.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          titleMedium: head.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          titleSmall: head.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        )
        .apply(bodyColor: color, displayColor: color);
  }

  static ThemeData light() {
    final base = ThemeData.light(useMaterial3: true);
    return base.copyWith(
      colorScheme: const ColorScheme.light(
        primary: AppColors.primary,
        surface: AppColors.surface,
        onPrimary: Colors.white,
        onSurface: AppColors.textPrimary,
      ),
      // Прозрачный — фон рисует AppBackground (см. app.dart builder).
      scaffoldBackgroundColor: Colors.transparent,
      textTheme: _textTheme(base.textTheme, AppColors.textPrimary),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        centerTitle: false,
        scrolledUnderElevation: 0,
        // Акцент-сериф «бумажного журнала» — масthead экрана.
        titleTextStyle: AppFonts.sourceSerif4(
          fontSize: 23,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        // «Наклейка»: тёплая мягкая тень вместо синеватого Material-elevation.
        // surfaceTint прозрачный — убираем тональную подкраску M3.
        elevation: 3,
        shadowColor: const Color(0x332A2722),
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        // По умолчанию Card ничего не обрезает — без этого InkWell-подсветка
        // любой нажимаемой карточки (ListTile.onTap и т.п.) рисуется прямым
        // прямоугольником поверх скруглённых углов. Отдельные карточки могут
        // переопределить на Clip.none, если внутри есть намеренный overflow.
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.ringTrack),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.surface,
        indicatorColor: AppColors.primary.withValues(alpha: 0.12),
        labelTextStyle: WidgetStateProperty.all(
          AppFonts.inter(fontSize: 12, fontWeight: FontWeight.w500),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 2,
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.ringTrack,
        thickness: 1,
        space: 1,
      ),
      // Бегунок и трек свича: фиксируем во ВСЕХ состояниях (иначе M3 на ховере
      // подменяет выбранный бегунок на бледный primaryContainer → «пропадает»).
      // Трек тоже свой — иначе OFF остаётся холодным M3-серым с рамкой и
      // спорит с тёплым бегунком (см. AppColors.textSecondary).
      switchTheme: SwitchThemeData(
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
        trackColor: WidgetStateProperty.resolveWith((states) {
          final on = states.contains(WidgetState.selected);
          if (states.contains(WidgetState.disabled)) {
            return (on ? AppColors.primary : AppColors.ringTrack)
                .withValues(alpha: 0.5);
          }
          return on ? AppColors.primary : AppColors.ringTrack;
        }),
        thumbColor: WidgetStateProperty.resolveWith((states) {
          final on = states.contains(WidgetState.selected);
          if (states.contains(WidgetState.disabled)) {
            return (on ? Colors.white : AppColors.textSecondary)
                .withValues(alpha: 0.5);
          }
          return on ? Colors.white : AppColors.textSecondary;
        }),
      ),
    );
  }

  static ThemeData dark() {
    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      colorScheme: const ColorScheme.dark(
        // Высветленный акцент: чернильный #3B5BDB на угле теряет контраст.
        primary: AppColors.primarySoft,
        surface: AppColors.surfaceDarkElevated,
        onPrimary: Color(0xFF101C4A),
        onSurface: AppColors.textPrimaryDark,
      ),
      scaffoldBackgroundColor: Colors.transparent,
      textTheme: _textTheme(base.textTheme, AppColors.textPrimaryDark),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: AppColors.textPrimaryDark,
        elevation: 0,
        centerTitle: false,
        scrolledUnderElevation: 0,
        // Акцент-сериф «бумажного журнала» — масthead экрана.
        titleTextStyle: AppFonts.sourceSerif4(
          fontSize: 23,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimaryDark,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surfaceDarkElevated,
        // На угле тень почти не видна — лёгкий подъём + прозрачный surfaceTint.
        elevation: 2,
        shadowColor: Colors.black,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.surfaceDarkMuted),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.surfaceDarkElevated,
        indicatorColor: AppColors.primarySoft.withValues(alpha: 0.18),
        labelTextStyle: WidgetStateProperty.all(
          AppFonts.inter(fontSize: 12, fontWeight: FontWeight.w500),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.primarySoft,
        foregroundColor: Color(0xFF101C4A),
        elevation: 2,
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.surfaceDarkMuted,
        thickness: 1,
        space: 1,
      ),
      // Бегунок и трек свича: см. коммент в light(). Тёмно-синий бегунок на
      // светло-голубом треке в ON — высокий контраст, не теряется.
      switchTheme: SwitchThemeData(
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
        trackColor: WidgetStateProperty.resolveWith((states) {
          final on = states.contains(WidgetState.selected);
          if (states.contains(WidgetState.disabled)) {
            return (on ? AppColors.primarySoft : AppColors.surfaceDarkMuted)
                .withValues(alpha: 0.5);
          }
          return on ? AppColors.primarySoft : AppColors.surfaceDarkMuted;
        }),
        thumbColor: WidgetStateProperty.resolveWith((states) {
          final on = states.contains(WidgetState.selected);
          const onColor = Color(0xFF101C4A);
          if (states.contains(WidgetState.disabled)) {
            return (on ? onColor : AppColors.textSecondaryDark)
                .withValues(alpha: 0.5);
          }
          return on ? onColor : AppColors.textSecondaryDark;
        }),
      ),
    );
  }
}
