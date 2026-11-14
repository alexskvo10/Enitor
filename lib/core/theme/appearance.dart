import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/sources/local/local_storage.dart';
import 'app_colors.dart';

const _kAppearanceKey = 'appearance';

/// Стиль фоновой текстуры. Применяется поверх однотонного фона темы.
///
/// Порядок значений менять нельзя: в SharedPreferences хранится индекс.
/// Подписи для UI берутся из локализации (bgPlain/bgPaper/bgDots), а не из
/// самого enum.
enum BackgroundStyle { plain, paper, dots }

/// Настройки оформления (фон + виньетка). Persist в SharedPreferences.
class AppearanceController extends ChangeNotifier {
  AppearanceController(this._storage) {
    final raw = _storage.readMap(_kAppearanceKey);
    if (raw != null) {
      final idx = (raw['style'] as int? ?? 1)
          .clamp(0, BackgroundStyle.values.length - 1);
      _style = BackgroundStyle.values[idx];
      _vignette = raw['vignette'] as bool? ?? false;
      final modeIdx =
          (raw['themeMode'] as int? ?? 0).clamp(0, ThemeMode.values.length - 1);
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

  /// Возвращает оформление к значениям по умолчанию («Настройки → Сбросить
  /// настройки»). Через контроллер, а не удалением ключа: иначе экран остался
  /// бы со старыми значениями в памяти и перезаписал бы их при первой правке.
  Future<void> resetToDefaults() async {
    _style = BackgroundStyle.paper;
    _vignette = false;
    _themeMode = ThemeMode.system;
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
///
/// Фон — свой слой за [RepaintBoundary]: анимации экранов (переход вкладок,
/// волна, прокрутка) его не перерисовывают. Текстура — одна плитка-картинка,
/// размноженная шейдером, а не тысячи точек на каждый кадр.
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
    final background = dark ? AppColors.backgroundDark : AppColors.background;
    final tile = switch (appearance.style) {
      BackgroundStyle.plain => null,
      BackgroundStyle.paper => _grainTile,
      BackgroundStyle.dots => _dotsTile,
    };
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1;

    return Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(
          child: CustomPaint(
            painter: _BackgroundPainter(
              background,
              tile,
              tile == null ? null : _tileImage(tile, ink, dark, dpr),
            ),
          ),
        ),
        child,
        if (appearance.vignette)
          // Виньетка под контентом невозможна извне, поэтому очень лёгкая
          // и не перехватывает указатель. Светлая тема — затемнение краёв,
          // тёмная — наоборот, высветление центра.
          IgnorePointer(
            child: RepaintBoundary(
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
          ),
      ],
    );
  }
}

/// Плитка текстуры: квадрат [size] логических пикселей, повторяется встык.
class _Tile {
  const _Tile(this.size, this.paint);
  final double size;
  final void Function(Canvas canvas, Color ink, bool dark) paint;
}

/// «Бумага»: двухслойная регулярная рябь мелких точек (шаги 7 и 11 —
/// плитка 77) — читается как зерно, ассетов не требует.
final _grainTile = _Tile(77, (canvas, ink, dark) {
  final p1 = Paint()..color = ink.withValues(alpha: dark ? 0.05 : 0.06);
  final p2 = Paint()..color = ink.withValues(alpha: dark ? 0.035 : 0.045);
  // До 77 включительно: точка на краю плитки — по половинке на соседних.
  for (var x = 0.0; x <= 77; x += 7) {
    for (var y = 0.0; y <= 77; y += 7) {
      canvas.drawCircle(Offset(x, y), 0.6, p1);
    }
  }
  for (var x = 4.0; x < 77; x += 11) {
    for (var y = 6.0; y < 77; y += 11) {
      canvas.drawCircle(Offset(x, y), 0.5, p2);
    }
  }
});

/// «Точки»: сетка 24px — Bullet Journal.
final _dotsTile = _Tile(24, (canvas, ink, dark) {
  canvas.drawCircle(
    const Offset(12, 12),
    1.1,
    Paint()..color = ink.withValues(alpha: dark ? 0.11 : 0.13),
  );
});

// ponytail: кэш не чистится — картинок от силы несколько (стиль × тема ×
// плотность экрана), каждая — десятки килобайт.
final _tileCache = <(_Tile, Color, bool, double), ui.Image>{};

ui.Image _tileImage(_Tile tile, Color ink, bool dark, double dpr) =>
    _tileCache.putIfAbsent((tile, ink, dark, dpr), () {
      final px = (tile.size * dpr).ceil();
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder)..scale(px / tile.size);
      tile.paint(canvas, ink, dark);
      final picture = recorder.endRecording();
      final image = picture.toImageSync(px, px);
      picture.dispose();
      return image;
    });

class _BackgroundPainter extends CustomPainter {
  _BackgroundPainter(this.background, this.tile, this.image);
  final Color background;
  final _Tile? tile;
  final ui.Image? image;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = background);
    final t = tile, img = image;
    if (t == null || img == null) return;
    final s = t.size / img.width;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ImageShader(
          img,
          TileMode.repeated,
          TileMode.repeated,
          Matrix4.diagonal3Values(s, s, 1).storage,
          filterQuality: FilterQuality.low,
        ),
    );
  }

  @override
  bool shouldRepaint(_BackgroundPainter old) =>
      old.background != background || old.image != image;
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
    // Не меньше 168, но растёт с текстом: при крупном шрифте в системе
    // фиксированная высота обрезала подпись.
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 168, minWidth: double.infinity),
      child: CustomPaint(
        painter: _NotebookPainter(theme.colorScheme.primary),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 30, color: AppColors.clay.withValues(alpha: 0.75)),
              const SizedBox(height: 12),
              Text(
                text,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  // 0.7, а не 0.6: при 0.6 подпись не дотягивала до
                  // контраста 4.5:1.
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
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
