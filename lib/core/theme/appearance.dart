import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/sources/local/local_storage.dart';
import 'app_colors.dart';

const _kAppearanceKey = 'appearance';

/// Стиль фоновой текстуры. Применяется поверх однотонного фона темы.
enum BackgroundStyle {
  plain('Гладкий'),
  paper('Бумага'),
  dots('Точки');

  const BackgroundStyle(this.label);
  final String label;
}

/// Настройки оформления (фон + виньетка). Persist в SharedPreferences.
class AppearanceController extends ChangeNotifier {
  AppearanceController(this._storage) {
    final raw = _storage.readMap(_kAppearanceKey);
    if (raw != null) {
      final idx = (raw['style'] as int? ?? 1)
          .clamp(0, BackgroundStyle.values.length - 1);
      _style = BackgroundStyle.values[idx];
      _vignette = raw['vignette'] as bool? ?? false;
      final modeIdx = (raw['themeMode'] as int? ?? 0)
          .clamp(0, ThemeMode.values.length - 1);
      _themeMode = ThemeMode.values[modeIdx];
    }
  }

  final LocalStorage _storage;

  BackgroundStyle _style = BackgroundStyle.paper; // дефолт — «Бумага»
  bool _vignette = false;
  ThemeMode _themeMode = ThemeMode.system; // дефолт — как в системе

  BackgroundStyle get style => _style;
  bool get vignette => _vignette;
  ThemeMode get themeMode => _themeMode;

  Future<void> setThemeMode(ThemeMode v) async {
    if (v == _themeMode) return;
    _themeMode = v;
    notifyListeners();
    await _save();
  }

  Future<void> setStyle(BackgroundStyle v) async {
    if (v == _style) return;
    _style = v;
    notifyListeners();
    await _save();
  }

  Future<void> setVignette(bool v) async {
    if (v == _vignette) return;
    _vignette = v;
    notifyListeners();
    await _save();
  }

  Future<void> _save() => _storage.writeMap(_kAppearanceKey, {
        'style': _style.index,
        'vignette': _vignette,
        'themeMode': _themeMode.index,
      });
}

final appearanceProvider = ChangeNotifierProvider<AppearanceController>((ref) {
  return AppearanceController(ref.read(localStorageProvider));
});

// ─── Фоновая подложка ────────────────────────────────────────────────────────

/// Глобальная подложка: цвет фона темы + текстура + (опц.) виньетка.
/// Вешается через `MaterialApp.builder`; scaffold'ы при этом прозрачные,
/// чтобы текстура была сплошной под всеми экранами.
class AppBackground extends ConsumerWidget {
  const AppBackground({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appearance = ref.watch(appearanceProvider);
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final ink = theme.colorScheme.onSurface;
    // ⚠️ Не scaffoldBackgroundColor — он прозрачный (мы сами так задали в
    // AppTheme, чтобы текстура была сплошной). Реальный цвет — из палитры.
    final background =
        dark ? AppColors.backgroundDark : AppColors.background;

    Widget result = ColoredBox(
      color: background,
      child: child,
    );

    // Текстура — между цветом фона и контентом.
    final painter = switch (appearance.style) {
      BackgroundStyle.plain => null,
      BackgroundStyle.paper => _GrainPainter(ink, dark),
      BackgroundStyle.dots => _DotGridPainter(ink, dark),
    };
    if (painter != null) {
      result = CustomPaint(
        painter: _BackgroundPainter(background, painter),
        child: child,
      );
    }

    if (appearance.vignette) {
      result = Stack(
        fit: StackFit.expand,
        children: [
          result,
          // Виньетка под контентом невозможна извне, поэтому очень лёгкая
          // и не перехватывает указатель. Светлая тема — затемнение краёв,
          // тёмная — наоборот, высветление центра.
          IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  radius: 1.1,
                  colors: dark
                      ? [
                          Colors.white.withValues(alpha: 0.015),
                          Colors.transparent,
                        ]
                      : [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.035),
                        ],
                ),
              ),
            ),
          ),
        ],
      );
    }
    return result;
  }
}

/// Комбинирует заливку фоном и текстуру в один painter (без лишнего слоя).
class _BackgroundPainter extends CustomPainter {
  _BackgroundPainter(this.background, this.texture);
  final Color background;
  final CustomPainter texture;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = background);
    texture.paint(canvas, size);
  }

  @override
  bool shouldRepaint(_BackgroundPainter old) {
    if (old.background != background) return true;
    // Разные типы текстур — covariant-вызов был бы TypeError.
    if (old.texture.runtimeType != texture.runtimeType) return true;
    return old.texture.shouldRepaint(texture);
  }
}

/// «Бумага»: двухслойная регулярная рябь мелких точек — читается как зерно,
/// но дёшево рисуется и не требует ассетов.
class _GrainPainter extends CustomPainter {
  _GrainPainter(this.ink, this.dark);
  final Color ink;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final p1 = Paint()..color = ink.withValues(alpha: dark ? 0.05 : 0.06);
    final p2 = Paint()..color = ink.withValues(alpha: dark ? 0.035 : 0.045);
    for (var x = 0.0; x < size.width; x += 7) {
      for (var y = 0.0; y < size.height; y += 7) {
        canvas.drawCircle(Offset(x, y), 0.6, p1);
      }
    }
    for (var x = 4.0; x < size.width; x += 11) {
      for (var y = 6.0; y < size.height; y += 11) {
        canvas.drawCircle(Offset(x, y), 0.5, p2);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _GrainPainter old) =>
      old.ink != ink || old.dark != dark;
}

/// «Точки»: сетка 24px — Bullet Journal.
class _DotGridPainter extends CustomPainter {
  _DotGridPainter(this.ink, this.dark);
  final Color ink;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = ink.withValues(alpha: dark ? 0.11 : 0.13);
    for (var x = 12.0; x < size.width; x += 24) {
      for (var y = 12.0; y < size.height; y += 24) {
        canvas.drawCircle(Offset(x, y), 1.1, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DotGridPainter old) =>
      old.ink != ink || old.dark != dark;
}

/// Линованный фон для пустых состояний («ритм блокнота»). Не глобальный:
/// линии конфликтуют с карточками списка, но пустому листу — самое то.
class NotebookEmptyState extends StatelessWidget {
  const NotebookEmptyState({
    super.key,
    required this.text,
    this.icon = Icons.edit_outlined,
  });
  final String text;

  /// Дудл-иконка над текстом («живое» пустое состояние, не «ошибка»).
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 168,
      width: double.infinity,
      child: CustomPaint(
        painter: _NotebookPainter(theme.colorScheme.primary),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 30, color: AppColors.clay.withValues(alpha: 0.75)),
              const SizedBox(height: 12),
              Text(
                text,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NotebookPainter extends CustomPainter {
  _NotebookPainter(this.accent);
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = accent.withValues(alpha: 0.12)
      ..strokeWidth = 1;
    for (var y = 36.0; y < size.height; y += 37) {
      canvas.drawLine(Offset(24, y), Offset(size.width - 24, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _NotebookPainter old) => old.accent != accent;
}
