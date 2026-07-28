import 'package:flutter/material.dart';

/// Палитра «Бумажный журнал»: тёплая бумага + чернила.
/// Светлая — «Дневная страница», тёмная — «Ночной кабинет» (тёплый уголь,
/// не сине-чёрный). Семантика приглушена в тёплую сторону, чтобы не спорить
/// с бумажным фоном.
abstract final class AppColors {
  // Brand — чернильный синий (перьевая ручка).
  static const Color primary = Color(0xFF3B5BDB);
  static const Color primaryDark = Color(0xFF2F4BC4);

  /// Акцент для тёмной темы — высветлен, иначе на угле не хватает контраста.
  static const Color primarySoft = Color(0xFF93A7F5);

  // Surfaces (light) — тёплая бумага.
  static const Color background = Color(0xFFF7F4EE);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceMuted = Color(0xFFEFEAE0);

  // Surfaces (dark) — тёплый уголь.
  static const Color backgroundDark = Color(0xFF181613);
  static const Color surfaceDarkElevated = Color(0xFF211E19);
  static const Color surfaceDarkMuted = Color(0xFF2A261F);

  // Text — тёплые чернила (не чёрный) и крем (не белый).
  static const Color textPrimary = Color(0xFF2A2722);
  static const Color textSecondary = Color(0xFF7A7468);
  static const Color textPrimaryDark = Color(0xFFECE7DC);
  static const Color textSecondaryDark = Color(0xFF9B948A);

  /// «Глина» — тёплый терракотовый акцент редизайна «Живая бумага».
  /// Точечно: буквица цитаты, шапка дня (eyebrow), иконка серии.
  static const Color clay = Color(0xFFC26B45);

  /// «Глина» для тёмной темы — высветлена той же логикой, что и
  /// [primarySoft]: обычный `clay` на угольном фоне теряет контраст.
  static const Color claySoft = Color(0xFFD9825C);

  // Semantic
  static const Color success = Color(0xFF3FA66A);
  static const Color danger = Color(0xFFD65745);
  static const Color warning = Color(0xFFE8A23D);

  // ── Тёплые тени-«наклейки» (редизайн «Живая бумага») ─────────────────────
  // НЕ синеватый Material-elevation, а тёплые α от чернил. Карточка «наклеена»
  // на бумагу. Двухслойная: близкая контактная + мягкая рассеянная.
  static const Color _shadowInk = Color(0xFF2A2722); // тёплые чернила

  /// Тень обычной карточки.
  static List<BoxShadow> get stickerShadow => [
        BoxShadow(
          color: _shadowInk.withValues(alpha: 0.05),
          blurRadius: 2,
          offset: const Offset(0, 1),
        ),
        BoxShadow(
          color: _shadowInk.withValues(alpha: 0.055),
          blurRadius: 14,
          offset: const Offset(0, 5),
        ),
      ];

  /// Тень поднятых поверхностей (FAB, шиты, диалоги).
  static List<BoxShadow> get raisedShadow => [
        BoxShadow(
          color: _shadowInk.withValues(alpha: 0.07),
          blurRadius: 6,
          offset: const Offset(0, 2),
        ),
        BoxShadow(
          color: _shadowInk.withValues(alpha: 0.10),
          blurRadius: 34,
          offset: const Offset(0, 14),
        ),
      ];

  // ── Кривые анимаций ──────────────────────────────────────────────────────
  /// Базовая «выезжающая» кривая (easeOutCubic-подобная).
  static const Cubic easeOut = Cubic(0.22, 1, 0.36, 1);

  /// Пружина с лёгким перелётом — для «живых» элементов (кольца, галочка).
  static const Cubic spring = Cubic(0.34, 1.56, 0.64, 1);

  /// Тёплый янтарный градиент — для колец-счётчиков (вместо amber→orange).
  static const List<Color> warningGradient = [
    Color(0xFFE8A23D),
    Color(0xFFCF7F28),
  ];

  // Productivity ring gradient (фоновый трек и заполнение)
  static const Color ringTrack = Color(0xFFE8E2D6);
  static const Color ringTrackDark = Color(0xFF332E26);
  static const List<Color> ringGradient = [
    Color(0xFF3B5BDB),
    Color(0xFF6E86F0),
  ];
}
