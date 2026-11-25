import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_fonts.dart';
import '../../data/sources/local/local_storage.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/l10n_extensions.dart';
import '../today/today_screen.dart';

// ─── Что и когда предлагать ──────────────────────────────────────────────────

/// Состояние экскурсии на этом устройстве (`device.` — не синхронизируется:
/// на каждом устройстве свой «первый раз»).
const kTourKey = 'device.tour';

enum TourOffer { first, update }

class TourPrefs extends ChangeNotifier {
  TourPrefs(this._storage) {
    final raw = _storage.readMap(kTourKey);
    _seenVersion = raw?['seenVersion'] as String?;
    _onUpdate = raw?['onUpdate'] as bool? ?? true;
  }

  final LocalStorage _storage;
  String? _seenVersion;
  bool _onUpdate = true;

  /// Предлагать карточку при первом запуске новой версии.
  bool get onUpdate => _onUpdate;

  /// Что предложить сейчас. [firstDay] — профиль создан сегодня (чистая
  /// установка); иначе отсутствие отметки значит «обновился с версии, где
  /// экскурсии ещё не было».
  TourOffer? offer(String version, {required bool firstDay}) {
    if (_seenVersion == version) return null;
    if (_seenVersion == null && firstDay) return TourOffer.first;
    return _onUpdate ? TourOffer.update : null;
  }

  /// Карточку этой версии больше не показывать (прошёл или закрыл).
  Future<void> markSeen(String version) async {
    _seenVersion = version;
    await _save();
  }

  Future<void> setOnUpdate(bool v) async {
    if (v == _onUpdate) return;
    _onUpdate = v;
    notifyListeners();
    await _save();
  }

  Future<void> _save() => _storage.writeMap(kTourKey, {
        if (_seenVersion != null) 'seenVersion': _seenVersion,
        'onUpdate': _onUpdate,
      });
}

final tourPrefsProvider = ChangeNotifierProvider<TourPrefs>(
  (ref) => TourPrefs(ref.read(localStorageProvider)),
);

// ─── Метки элементов, которые подсвечивает экскурсия ─────────────────────────

/// Ключи вешаются на сами элементы (KeyedSubtree) — экскурсия меряет их
/// положение на экране. Элемента нет (не построен) — шаг без подсветки.
abstract final class TourKeys {
  static final calendar = GlobalKey(debugLabel: 'tour.calendar');
  static final addTask = GlobalKey(debugLabel: 'tour.addTask');
  static final tasks = GlobalKey(debugLabel: 'tour.tasks');
  static final summary = GlobalKey(debugLabel: 'tour.summary');
  static final templates = GlobalKey(debugLabel: 'tour.templates');
  static final dayToggle = GlobalKey(debugLabel: 'tour.dayToggle');
  static final goalPeriods = GlobalKey(debugLabel: 'tour.goalPeriods');
  static final navBar = GlobalKey(debugLabel: 'tour.navBar');
  static final connections = GlobalKey(debugLabel: 'tour.connections');
  static final tourRow = GlobalKey(debugLabel: 'tour.tourRow');
}

/// Количество вкладок внизу — для подсветки одной из них.
const _kTabs = 4;

class _Step {
  const _Step({
    required this.title,
    required this.body,
    this.route,
    this.push = false,
    this.target,
    this.tab,
    this.icon,
  });

  final String Function(AppLocalizations) title;
  final String Function(AppLocalizations) body;

  /// Куда перейти перед шагом (go, или push для экранов поверх вкладок).
  final String? route;
  final bool push;
  final GlobalKey? target;

  /// Подсветить вкладку с этим номером в нижней панели.
  final int? tab;

  /// Шаг без подсветки — крупная иконка в карточке.
  final IconData? icon;
}

final _steps = <_Step>[
  _Step(
    route: '/today',
    icon: Icons.waving_hand_outlined,
    title: (l) => l.tour1Title,
    body: (l) => l.tour1Body,
  ),
  _Step(
    target: TourKeys.calendar,
    title: (l) => l.tour2Title,
    body: (l) => l.tour2Body,
  ),
  _Step(
    target: TourKeys.addTask,
    title: (l) => l.tour3Title,
    body: (l) => l.tour3Body,
  ),
  _Step(
    target: TourKeys.tasks,
    title: (l) => l.tour4Title,
    body: (l) => l.tour4Body,
  ),
  _Step(
    target: TourKeys.summary,
    title: (l) => l.tour5Title,
    body: (l) => l.tour5Body,
  ),
  _Step(
    target: TourKeys.templates,
    title: (l) => l.tour6Title,
    body: (l) => l.tour6Body,
  ),
  _Step(
    target: TourKeys.dayToggle,
    title: (l) => l.tour7Title,
    body: (l) => l.tour7Body,
  ),
  _Step(
    route: '/goals',
    target: TourKeys.goalPeriods,
    title: (l) => l.tour8Title,
    body: (l) => l.tour8Body,
  ),
  _Step(
    route: '/stats',
    tab: 2,
    title: (l) => l.tour9Title,
    body: (l) => l.tour9Body,
  ),
  _Step(
    route: '/profile',
    tab: 3,
    title: (l) => l.tour10Title,
    body: (l) => l.tour10Body,
  ),
  _Step(
    route: '/settings',
    push: true,
    target: TourKeys.connections,
    title: (l) => l.tour11Title,
    body: (l) => l.tour11Body,
  ),
  _Step(
    target: TourKeys.tourRow,
    title: (l) => l.tour12Title,
    body: (l) => l.tour12Body,
  ),
];

// ─── Карточка-предложение ────────────────────────────────────────────────────

/// Карточка «В первый раз?» / «Что нового» сверху экрана. Завершается, когда
/// карточка ушла: true — пройти, false — закрыл (эту версию больше не
/// предлагать), null — «Позже» или сама ушла (предложим при следующем запуске).
Future<bool?> showTourOffer(BuildContext context, TourOffer kind) {
  final overlay = Overlay.of(context, rootOverlay: true);
  final done = Completer<bool?>();
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _OfferCard(
      kind: kind,
      onResolved: (r) {
        entry.remove();
        if (!done.isCompleted) done.complete(r);
      },
    ),
  );
  overlay.insert(entry);
  return done.future;
}

class _OfferCard extends StatefulWidget {
  const _OfferCard({required this.kind, required this.onResolved});
  final TourOffer kind;
  final ValueChanged<bool?> onResolved;

  @override
  State<_OfferCard> createState() => _OfferCardState();
}

class _OfferCardState extends State<_OfferCard>
    with SingleTickerProviderStateMixin {
  late final _in = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
  )..forward();
  double _drag = 0;
  bool _resolving = false;
  // Не висит вечно поверх шапки: без ответа уходит, как «Позже».
  late final Timer _timeout;

  @override
  void initState() {
    super.initState();
    _timeout = Timer(const Duration(seconds: 25), () => _resolve(null));
  }

  @override
  void dispose() {
    _timeout.cancel();
    _in.dispose();
    super.dispose();
  }

  Future<void> _resolve(bool? r) async {
    if (_resolving) return;
    _resolving = true;
    _timeout.cancel();
    await _in.reverse();
    widget.onResolved(r);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final first = widget.kind == TourOffer.first;
    final accent = theme.colorScheme.primary;
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: AnimatedBuilder(
            animation: _in,
            builder: (context, child) {
              final t = CurvedAnimation(
                parent: _in,
                curve: AppColors.spring,
                reverseCurve: Curves.easeIn,
              ).value;
              return Transform.translate(
                offset: Offset(0, (1 - t).clamp(-0.4, 1.4) * -110 + _drag),
                child: Opacity(
                  opacity: _in.value.clamp(0.0, 1.0) *
                      (1 - (_drag.abs() / 140).clamp(0.0, 1.0)),
                  child: child,
                ),
              );
            },
            child: GestureDetector(
              onVerticalDragUpdate: (d) {
                if (d.delta.dy < 0) setState(() => _drag += d.delta.dy);
              },
              onVerticalDragEnd: (_) {
                // Смахнул вверх — как крестик: убрал карточку этой версии.
                if (_drag < -24) {
                  _resolve(false);
                } else {
                  setState(() => _drag = 0);
                }
              },
              child: Material(
                type: MaterialType.transparency,
                child: Container(
                  margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  constraints: const BoxConstraints(maxWidth: 440),
                  padding: const EdgeInsets.fromLTRB(14, 14, 8, 12),
                  decoration: BoxDecoration(
                    color: theme.cardTheme.color ?? theme.cardColor,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: AppColors.raisedShadow,
                    border: Border.all(color: accent.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: accent.withValues(alpha: 0.14),
                        ),
                        child: Icon(
                          first ? Icons.explore_outlined : Icons.auto_awesome,
                          color: accent,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              first
                                  ? l10n.tourOfferFirstTitle
                                  : l10n.tourOfferUpdateTitle,
                              style: theme.textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              first
                                  ? l10n.tourOfferFirstBody
                                  : l10n.tourOfferUpdateBody,
                              style: theme.textTheme.bodySmall,
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                FilledButton(
                                  onPressed: () => _resolve(true),
                                  child: Text(l10n.tourOfferStart),
                                ),
                                const SizedBox(width: 6),
                                TextButton(
                                  onPressed: () => _resolve(null),
                                  child: Text(l10n.tourOfferLater),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: l10n.closeTooltip,
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.close, size: 20),
                        onPressed: () => _resolve(false),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Сама экскурсия ──────────────────────────────────────────────────────────

/// Идущая экскурсия: роутер, которым она переключает экраны; null — нет.
/// Слой экскурсии живёт в `MaterialApp.builder` над навигатором (см.
/// [TourLayer]) — поверх любых открытых экранов, и переходы его не задевают.
final tourRunning = ValueNotifier<GoRouter?>(null);

/// Запускает экскурсию. Вкладки и экраны переключает сама; в данные ничего
/// не пишет.
void startTour(GoRouter router) => tourRunning.value = router;

/// Слой над приложением, в котором идёт экскурсия.
class TourLayer extends StatelessWidget {
  const TourLayer({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<GoRouter?>(
        valueListenable: tourRunning,
        builder: (context, router, _) => router == null
            ? const SizedBox.shrink()
            : _TourOverlay(
                router: router,
                onClose: () => tourRunning.value = null,
              ),
      );
}

class _TourOverlay extends StatefulWidget {
  const _TourOverlay({required this.router, required this.onClose});
  final GoRouter router;
  final VoidCallback onClose;

  @override
  State<_TourOverlay> createState() => _TourOverlayState();
}

class _TourOverlayState extends State<_TourOverlay>
    with TickerProviderStateMixin {
  int _index = 0;
  Rect? _from;
  Rect? _to;
  bool _busy = false;
  bool _closing = false;

  /// Перелёт подсветки между элементами.
  late final _move = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  );

  /// Появление и уход затемнения.
  late final _fade = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  )..forward();

  /// Мягкая пульсация рамки вокруг подсвеченного.
  late final _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat(reverse: true);

  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    // «Назад» системы — шаг назад, а не уход с экрана под экскурсией. Роутер
    // спрашивают первым (наблюдатели идут по порядку добавления), поэтому
    // перехватываем у него самого: дочерний диспетчер с приоритетом.
    _backDispatcher = widget.router.backButtonDispatcher
        .createChildBackButtonDispatcher()
      ..addCallback(_onSystemBack)
      ..takePriority();
    // После кадра: первый шаг трогает провайдеры, а слой строится в build.
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_goTo(0)));
  }

  late final ChildBackButtonDispatcher _backDispatcher;

  Future<bool> _onSystemBack() async {
    _back();
    return true;
  }

  @override
  void dispose() {
    _backDispatcher.removeCallback(_onSystemBack);
    widget.router.backButtonDispatcher.forget(_backDispatcher);
    _move.dispose();
    _fade.dispose();
    _pulse.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _goTo(int i) async {
    if (_busy || i < 0 || i >= _steps.length) return;
    _busy = true;
    final step = _steps[i];
    // Шаги «Задач» показывают вкладку задач, а не расписания.
    if (i <= 6) {
      ProviderScope.containerOf(context, listen: false)
          .read(todayTabRequestProvider.notifier)
          .state = 0;
    }
    // Последнее совпадение: у экрана, открытого push (настройки), это его
    // адрес, а uri всей конфигурации остаётся адресом вкладки под ним.
    final cfg = widget.router.routerDelegate.currentConfiguration;
    final loc = cfg.isEmpty ? '' : cfg.last.matchedLocation;
    if (step.route != null && loc != step.route) {
      if (step.push) {
        unawaited(widget.router.push(step.route!));
      } else {
        widget.router.go(step.route!);
      }
      // Переход экрана — 300 мс; ждём, пока элементы встанут на места.
      await Future<void>.delayed(const Duration(milliseconds: 420));
    } else if (step.route == null && i < _index) {
      // Назад с настроек на вкладки: экран поверх надо закрыть.
      final prevRoute = _routeFor(i);
      if (prevRoute != null && loc != prevRoute) {
        widget.router.go(prevRoute);
        await Future<void>.delayed(const Duration(milliseconds: 420));
      }
    }
    if (!mounted) return;
    final target = step.target;
    final ctx = target == null ? null : await revealTarget(target);
    if (!mounted) return;
    if (ctx != null && ctx.mounted) {
      // Элемент может быть ниже края (строка в настройках) — докручиваем.
      await Scrollable.ensureVisible(
        ctx,
        alignment: 0.4,
        duration: const Duration(milliseconds: 300),
      );
      if (!mounted) return;
    }
    final rect = _measure(step);
    setState(() {
      _from = _current;
      _to = rect;
      _index = i;
    });
    unawaited(_move.forward(from: 0));
    _busy = false;
    _focus.requestFocus();
    // Прокрутка и переход могут ещё доезжать после замера — перемеряем,
    // когда всё встало, и доводим подсветку, если элемент сдвинулся.
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (!mounted || _busy || _index != i) return;
    final settled = _measure(step);
    final now = _to;
    if (settled != null &&
        now != null &&
        (settled.topLeft - now.topLeft).distance > 1) {
      setState(() {
        _from = _current;
        _to = settled;
      });
      unawaited(_move.forward(from: 0));
    }
  }

  /// Маршрут, на котором стоит шаг (последний заданный до него включительно).
  String? _routeFor(int i) {
    for (var k = i; k >= 0; k--) {
      if (_steps[k].route != null) return _steps[k].route;
    }
    return null;
  }

  Rect? get _current {
    final a = _from, b = _to;
    if (b == null) return a;
    final t = Curves.easeInOutCubic.transform(_move.value);
    return a == null ? b : Rect.lerp(a, b, t);
  }

  Rect? _measure(_Step step) {
    final overlayBox = context.findRenderObject() as RenderBox?;
    final key = step.tab != null ? TourKeys.navBar : step.target;
    final box = key?.currentContext?.findRenderObject() as RenderBox?;
    if (overlayBox == null || box == null || !box.attached) return null;
    // Слой экскурсии — сосед навигатора, не предок: через глобальные
    // координаты.
    final origin = overlayBox.globalToLocal(box.localToGlobal(Offset.zero));
    var r = origin & box.size;
    if (step.tab != null) {
      final w = r.width / _kTabs;
      r = Rect.fromLTWH(r.left + w * step.tab!, r.top, w, r.height);
    }
    // Окошко с пульсирующей рамкой (до +7 px) не должно уходить за края
    // экрана: карточки шириной во весь экран иначе обрезаются по бокам.
    final bounds = (Offset.zero & overlayBox.size).deflate(8);
    final hole = r.inflate(6).intersect(bounds);
    return hole.isEmpty ? r : hole;
  }

  Future<void> _close() async {
    if (_closing) return;
    _closing = true;
    await _fade.reverse();
    widget.onClose();
  }

  void _next() =>
      _index == _steps.length - 1 ? unawaited(_close()) : _goTo(_index + 1);
  void _back() => _index == 0 ? unawaited(_close()) : _goTo(_index - 1);

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final step = _steps[_index];
    final last = _index == _steps.length - 1;

    return Material(
      type: MaterialType.transparency,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): _close,
          const SingleActivator(LogicalKeyboardKey.arrowRight): _next,
          const SingleActivator(LogicalKeyboardKey.enter): _next,
          const SingleActivator(LogicalKeyboardKey.arrowLeft): _back,
        },
        child: Focus(
          focusNode: _focus,
          autofocus: true,
          child: FadeTransition(
            opacity: _fade,
            child: AnimatedBuilder(
              animation: Listenable.merge([_move, _pulse]),
              builder: (context, _) {
                final hole = _current;
                return LayoutBuilder(
                  builder: (context, c) {
                    final size = c.biggest;
                    final card = _Card(
                      key: ValueKey(_index),
                      index: _index,
                      total: _steps.length,
                      icon: hole == null ? step.icon : null,
                      title: step.title(l10n),
                      body: step.body(l10n),
                      last: last,
                      onNext: _next,
                      onBack: _index == 0 ? null : _back,
                      onSkip: _close,
                    );
                    return Stack(
                      children: [
                        // Затемнение с «окном»; касания под ним не проходят.
                        Positioned.fill(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () {},
                            child: CustomPaint(
                              painter: _DimPainter(
                                hole: hole,
                                ring: theme.colorScheme.primary,
                                pulse: _pulse.value,
                              ),
                            ),
                          ),
                        ),
                        _placeCard(size, hole, card),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  /// Карточка — над подсвеченным, если оно в нижней половине, иначе под ним;
  /// без подсветки — по центру.
  Widget _placeCard(Size size, Rect? hole, Widget card) {
    final width = math.min(size.width - 32, 420.0);
    final left = (size.width - width) / 2;
    final pad = MediaQuery.paddingOf(context);
    Widget wrap(Widget w) => AnimatedSwitcher(
          duration: const Duration(milliseconds: 260),
          switchInCurve: AppColors.easeOut,
          transitionBuilder: (child, a) => FadeTransition(
            opacity: a,
            child: SlideTransition(
              position: Tween(begin: const Offset(0, 0.06), end: Offset.zero)
                  .animate(a),
              child: child,
            ),
          ),
          child: w,
        );
    if (hole == null) {
      return Positioned(
        left: left,
        width: width,
        top: 0,
        bottom: 0,
        child: Center(child: wrap(card)),
      );
    }
    final below = hole.center.dy < size.height / 2;
    return below
        ? Positioned(
            left: left,
            width: width,
            top: math.min(hole.bottom + 14, size.height - pad.bottom - 220),
            child: wrap(card),
          )
        : Positioned(
            left: left,
            width: width,
            bottom: math.max(size.height - hole.top + 14, pad.bottom + 16),
            child: wrap(card),
          );
  }
}

class _Card extends StatelessWidget {
  const _Card({
    super.key,
    required this.index,
    required this.total,
    required this.icon,
    required this.title,
    required this.body,
    required this.last,
    required this.onNext,
    required this.onBack,
    required this.onSkip,
  });

  final int index;
  final int total;
  final IconData? icon;
  final String title;
  final String body;
  final bool last;
  final VoidCallback onNext;
  final VoidCallback? onBack;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final accent = theme.colorScheme.primary;
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.6);
    return Material(
      color: theme.cardTheme.color ?? theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(22),
      elevation: 0,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          boxShadow: AppColors.raisedShadow,
        ),
        padding: const EdgeInsets.fromLTRB(18, 16, 14, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (icon != null) ...[
              Center(
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: accent.withValues(alpha: 0.12),
                  ),
                  child: Icon(icon, size: 32, color: accent),
                ),
              ),
              const SizedBox(height: 12),
            ],
            Text(
              l10n.tourStepOf(index + 1, total),
              style: theme.textTheme.labelMedium?.copyWith(
                color: accent,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: AppFonts.manrope(
                fontSize: 19,
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              body,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
            ),
            const SizedBox(height: 14),
            // Точки шагов: пройденные и текущий — цветом, текущий длиннее.
            Row(
              children: [
                for (var i = 0; i < total; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 260),
                    margin: const EdgeInsets.only(right: 4),
                    width: i == index ? 16 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(3),
                      color: i <= index
                          ? accent
                          : theme.colorScheme.onSurface.withValues(alpha: 0.15),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                // «Пропустить» уступает место, если кнопки не влезают.
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: last
                        ? null
                        : TextButton(
                            onPressed: onSkip,
                            style: TextButton.styleFrom(
                              foregroundColor: muted,
                              visualDensity: VisualDensity.compact,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 8),
                            ),
                            child: Text(
                              l10n.tourSkip,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                  ),
                ),
                if (onBack != null)
                  TextButton(
                    onPressed: onBack,
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                    ),
                    child: Text(l10n.tourBack),
                  ),
                const SizedBox(width: 4),
                FilledButton(
                  onPressed: onNext,
                  child: Text(last ? l10n.tourDone : l10n.tourNext),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Затемнение экрана с вырезанным скруглённым окном и пульсирующей рамкой.
class _DimPainter extends CustomPainter {
  _DimPainter({required this.hole, required this.ring, required this.pulse});
  final Rect? hole;
  final Color ring;
  final double pulse;

  @override
  void paint(Canvas canvas, Size size) {
    final dim = Paint()..color = Colors.black.withValues(alpha: 0.58);
    final h = hole;
    if (h == null) {
      canvas.drawRect(Offset.zero & size, dim);
      return;
    }
    final r = RRect.fromRectAndRadius(h, const Radius.circular(18));
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(Offset.zero & size),
        Path()..addRRect(r),
      ),
      dim,
    );
    final grow = 2 + 4 * pulse;
    canvas.drawRRect(
      r.inflate(grow),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = ring.withValues(alpha: 0.85 - 0.5 * pulse),
    );
  }

  @override
  bool shouldRepaint(_DimPainter o) =>
      o.hole != hole || o.pulse != pulse || o.ring != ring;
}

/// Контекст [key], даже если элемент ещё не построен.
///
/// Длинные экраны (задачи, настройки) строят только видимое и небольшой
/// запас. Если элемент далеко за краем — например, список задач длинный и
/// прошлый шаг увёл экран вниз, — контекста у него нет, и ensureVisible
/// докрутить не может: подсветка оставалась на прошлом шаге. Тогда листаем
/// видимые вертикальные списки сверху вниз, пока элемент не появится; не
/// нашёлся — возвращаем прокрутку на место.
@visibleForTesting
Future<BuildContext?> revealTarget(GlobalKey key) async {
  BuildContext? found() {
    final c = key.currentContext;
    return c != null && c.mounted ? c : null;
  }

  if (found() case final c?) return c;
  for (final s in _visibleVerticalScrollables()) {
    final p = s.position;
    final start = p.pixels;
    final step = math.max(p.viewportDimension * 0.8, 100.0);
    var at = p.minScrollExtent;
    // ponytail: до 60 экранов — длиннее экранов с подсветкой в приложении нет.
    for (var i = 0; i < 60; i++) {
      p.jumpTo(math.min(at, p.maxScrollExtent));
      await WidgetsBinding.instance.endOfFrame;
      if (found() case final c?) return c;
      if (at >= p.maxScrollExtent) break;
      at += step;
    }
    p.jumpTo(math.min(start, p.maxScrollExtent));
  }
  return null;
}

/// Вертикальные списки, которые сейчас на экране: у экранов под верхним
/// и у неактивных вкладок тикеры выключены — их не трогаем.
List<ScrollableState> _visibleVerticalScrollables() {
  final out = <ScrollableState>[];
  void visit(Element e) {
    if (e is StatefulElement) {
      final s = e.state;
      if (s is ScrollableState &&
          axisDirectionToAxis(s.axisDirection) == Axis.vertical &&
          s.position.hasContentDimensions &&
          s.position.maxScrollExtent > s.position.minScrollExtent &&
          TickerMode.getValuesNotifier(e).value.enabled) {
        out.add(s);
      }
    }
    e.visitChildren(visit);
  }

  WidgetsBinding.instance.rootElement?.visitChildren(visit);
  // Главный список экрана — самый высокий.
  out.sort(
    (a, b) =>
        b.position.viewportDimension.compareTo(a.position.viewportDimension),
  );
  return out;
}
