// SPDX-License-Identifier: AGPL-3.0-or-later


import 'package:fluffychat/vibe/vibe_glass.dart';
import 'package:flutter/gestures.dart';
import 'package:fluffychat/vibe/vibe_motion.dart';
import 'package:flutter/material.dart';

/// State for the "drag the chat in with your finger" gesture on the home
/// screen. While [active] the chat route [targetRoute] follows [anim].
abstract class VibeSwipe {
  /// Set right before navigating to the chat; the first route that starts its
  /// forward transition while this is true is handed to [onRoute].
  static bool pending = false;
  static void Function(PageRoute<dynamic> route)? onRoute;

  static void reset() {
    pending = false;
    onRoute = null;
  }
}

/// Discord style page transition: the new page slides OVER the old one (the
/// page below stays put) and can be dragged back from anywhere on screen.
class VibePageTransitionsBuilder extends PageTransitionsBuilder {
  const VibePageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    // The page underneath drifts left and dims a little while a new page
    // slides over it (like Telegram). Paint-only, so it costs almost nothing.
    // Its own layer: moving / dimming the covered page each frame must not
    // repaint everything on it (that was the stutter when closing a chat).
    final under = _Underneath(
      animation: secondaryAnimation,
      child: RepaintBoundary(child: child),
    );
    if (route.isFirst) return under;
    if (VibeSwipe.pending && animation.status == AnimationStatus.forward) {
      VibeSwipe.pending = false;
      final cb = VibeSwipe.onRoute;
      VibeSwipe.onRoute = null;
      if (cb != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => cb(route));
      }
    }
    return _VibeBackSwipe<T>(
      route: route,
      child: _SlideOver(
        route: route,
        animation: animation,
        child: under,
      ),
    );
  }
}

class _SlideOver extends StatelessWidget {
  final PageRoute<dynamic> route;
  final Animation<double> animation;
  final Widget child;
  const _SlideOver({
    required this.route,
    required this.animation,
    required this.child,
  });

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: animation,
    child: child,
    builder: (context, child) {
      final gesture = route.navigator?.userGestureInProgress == true;
      final v = animation.value.clamp(0.0, 1.0);
      // Finger: follow it 1:1. Opening: the spring. Closing: the same
      // spring mirrored, so the page moves at once (played backwards, the
      // spring's slow settle made the page sit still before sliding out).
      final t = gesture
          ? v
          : animation.status == AnimationStatus.reverse
          ? 1 - vibePageSpring.transform(1 - v)
          : vibePageSpring.transform(v);
      // A soft gradient edge instead of a blurred shadow: a full-screen
      // blur had to be redrawn on every frame of the slide.
      return FractionalTranslation(
        translation: Offset(1 - t, 0),
        child: Stack(
          clipBehavior: Clip.none,
          // Same children every frame, so the page's state is never lost.
          children: [
            child!,
            Positioned(
              left: -18,
              top: 0,
              bottom: 0,
              width: 18,
              child: IgnorePointer(
                child: Opacity(
                  opacity: t < 0.995 ? t : 0,
                  child: const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerRight,
                        end: Alignment.centerLeft,
                        colors: [Color(0x55000000), Color(0x00000000)],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

/// Moves the covered page a little to the left and dims it.
class _Underneath extends StatelessWidget {
  final Animation<double> animation;
  final Widget child;
  const _Underneath({required this.animation, required this.child});

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: animation,
    child: child,
    builder: (context, child) {
      final v = animation.value.clamp(0.0, 1.0);
      // Always the same widgets (only values change), so the page keeps
      // its state when something opens on top of it.
      return FractionalTranslation(
        translation: Offset(-0.22 * v, 0),
        child: Stack(
          fit: StackFit.passthrough,
          children: [
            child!,
            Positioned.fill(
              child: IgnorePointer(
                child: ColoredBox(color: Color.fromRGBO(0, 0, 0, 0.28 * v)),
              ),
            ),
          ],
        ),
      );
    },
  );
}

/// Drag the page back (left to right) from ANYWHERE on the screen.
/// Uses raw pointer events so it never fights with taps, lists or
/// swipe-to-reply.
class _VibeBackSwipe<T> extends StatefulWidget {
  final PageRoute<T> route;
  final Widget child;
  const _VibeBackSwipe({required this.route, required this.child});

  @override
  State<_VibeBackSwipe<T>> createState() => _VibeBackSwipeState<T>();
}

class _VibeBackSwipeState<T> extends State<_VibeBackSwipe<T>> {
  int? _pointer;
  Offset _start = Offset.zero;
  bool _decided = false;
  bool _dragging = false;
  VelocityTracker? _tracker;
  NavigatorState? _nav;
  AnimationController? _ctl;
  double _width = 400;

  bool get _enabled {
    final r = widget.route;
    return r.isActive &&
        r.isCurrent &&
        !r.isFirst &&
        r.controller != null &&
        // Can be grabbed while it's still sliding in (interruptible).
        (r.animation?.status == AnimationStatus.completed ||
            r.animation?.status == AnimationStatus.forward) &&
        r.navigator?.userGestureInProgress != true &&
        r.popDisposition == RoutePopDisposition.pop &&
        !r.willHandlePopInternally;
  }

  void _down(PointerDownEvent e) {
    if (_pointer != null || e.kind == PointerDeviceKind.mouse) return;
    if (!_enabled) return;
    _pointer = e.pointer;
    _start = e.position;
    _decided = false;
    _dragging = false;
    _tracker = VelocityTracker.withKind(e.kind)
      ..addPosition(e.timeStamp, e.position);
  }

  void _move(PointerMoveEvent e) {
    if (e.pointer != _pointer) return;
    _tracker?.addPosition(e.timeStamp, e.position);
    if (!_decided) {
      final d = e.position - _start;
      if (d.distance < 14) return;
      _decided = true;
      if (d.dx > 0 && d.dx.abs() > d.dy.abs() * 1.6) {
        _begin();
      } else {
        _pointer = null;
        return;
      }
    }
    if (_dragging) {
      _ctl!.value = (_ctl!.value - e.delta.dx / _width).clamp(0.0, 1.0);
    }
  }

  void _begin() {
    final box = context.findRenderObject();
    _width = box is RenderBox && box.hasSize ? box.size.width : 400;
    _nav = widget.route.navigator;
    _ctl = widget.route.controller;
    if (_nav == null || _ctl == null) {
      _pointer = null;
      return;
    }
    _dragging = true;
    _nav!.didStartUserGesture();
  }

  void _up(PointerEvent e) {
    if (e.pointer != _pointer) return;
    _pointer = null;
    if (!_dragging) return;
    _dragging = false;
    final vx = _tracker?.getVelocity().pixelsPerSecond.dx ?? 0;
    _finish(vx / _width);
  }

  /// Release: the page keeps the finger's speed (velocity handoff) and
  /// settles on a spring, open or closed, from exactly where it was.
  void _finish(double v) {
    final c = _ctl!;
    final nav = _nav!;
    final forward = v.abs() >= 1 ? v <= 0 : c.value > 0.5;
    // Controller value goes down as the finger moves right.
    final velocity = -v;
    if (forward) {
      c.animateWith(vibeSpringFrom(c.value, 1.0, velocity));
    } else {
      nav.pop();
      c.animateBackWith(vibeSpringFrom(c.value, 0.0, velocity));
    }
    if (c.isAnimating) {
      late AnimationStatusListener l;
      l = (status) {
        if (status == AnimationStatus.forward ||
            status == AnimationStatus.reverse) {
          return;
        }
        c.removeStatusListener(l);
        nav.didStopUserGesture();
      };
      c.addStatusListener(l);
    } else {
      nav.didStopUserGesture();
    }
  }

  @override
  void dispose() {
    if (_dragging) {
      _dragging = false;
      _nav?.didStopUserGesture();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: _down,
    onPointerMove: _move,
    onPointerUp: _up,
    onPointerCancel: _up,
    child: widget.child,
  );
}


/// The app's pages. Normal pages slide over from the right (a little slower
/// than Android's default, so it feels smooth); [sheet] pages (settings)
/// slide up from the bottom and close with a swipe down.
class VibePage<T> extends Page<T> {
  final Widget child;
  final bool sheet;
  const VibePage({
    required this.child,
    this.sheet = false,
    super.key,
    super.restorationId,
  });

  @override
  Route<T> createRoute(BuildContext context) => sheet
      ? _VibeSheetPageRoute<T>(settings: this, builder: (_) => child)
      : _VibePageRoute<T>(this);
}

class _VibePageRoute<T> extends PageRoute<T>
    with MaterialRouteTransitionMixin<T> {
  _VibePageRoute(VibePage<T> page) : super(settings: page);

  @override
  Widget buildContent(BuildContext context) =>
      VibeGlassBackdrop(child: (settings as VibePage<T>).child);

  @override
  bool get maintainState => true;

  @override
  Duration get transitionDuration => vibePageSpring.duration;

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 300);
}

/// A settings page as a pane: it rises to half the screen, then on up to
/// the full page; no back button, a swipe down (following the finger)
/// closes it. The page underneath stays still.
class VibeSheetPageRoute<T> extends _VibeSheetPageRoute<T> {
  VibeSheetPageRoute({required super.builder, super.settings});
}

class _VibeSheetPageRoute<T> extends PageRoute<T> {
  final WidgetBuilder builder;
  _VibeSheetPageRoute({required this.builder, super.settings});

  @override
  bool get opaque => false;

  @override
  Color? get barrierColor => const Color(0x66000000);

  @override
  String? get barrierLabel => null;

  @override
  bool get maintainState => true;

  @override
  bool get impliesAppBarDismissal => false;

  // the page underneath doesn't move (it used to wiggle)
  @override
  bool canTransitionFrom(TransitionRoute<dynamic> previousRoute) => false;

  @override
  Duration get transitionDuration => vibeSheetSpring.duration;

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 260);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => _SheetPage(route: this, child: builder(context));

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => AnimatedBuilder(
    animation: animation,
    child: child,
    builder: (context, child) {
      final v = animation.value.clamp(0.0, 1.0);
      // following a finger: 1:1; otherwise eased
      final y = navigator?.userGestureInProgress == true
          ? 1 - v
          : 1 - (animation.status == AnimationStatus.reverse
                ? Curves.easeInCubic.transform(v)
                : vibeSheetSpring.transform(v));
      return FractionalTranslation(translation: Offset(0, y), child: child);
    },
  );
}

/// A settings page as a pane: it opens half way up; drag it up (it follows
/// the finger) for the full page. Drag down to bring it back to half and on
/// down to close; on the full page that starts once the list is at its top.
///
/// It listens to the raw finger (not a gesture that competes with the
/// page's list), so the drag works anywhere on the page.
class _SheetPage extends StatefulWidget {
  final PageRoute<dynamic> route;
  final Widget child;
  const _SheetPage({required this.route, required this.child});

  @override
  State<_SheetPage> createState() => _SheetPageState();
}

class _SheetPageState extends State<_SheetPage>
    with SingleTickerProviderStateMixin {
  // 0 = half open, 1 = full page
  late final AnimationController _full = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );
  bool _scrollLocked = true; // the page's list doesn't scroll while half open
  bool _atTop = true;
  bool _closing = false;
  bool _closingDrag = false;
  bool _paneDrag = false; // this touch moves the pane
  Offset _down = Offset.zero;
  VelocityTracker? _vt;
  int? _pointer;
  double _h = 1;

  // ignore: invalid_use_of_protected_member
  AnimationController? get _route => (widget.route as TransitionRoute).controller;

  @override
  void initState() {
    super.initState();
    _full.addListener(_syncLock);
  }

  void _syncLock() {
    final locked = _full.value < 1;
    if (locked != _scrollLocked && mounted) setState(() => _scrollLocked = locked);
  }

  @override
  void dispose() {
    _full.dispose();
    super.dispose();
  }

  void _onDown(PointerDownEvent e) {
    if (_pointer != null || _closing) return;
    _pointer = e.pointer;
    _down = e.position;
    _paneDrag = false;
    _vt = VelocityTracker.withKind(e.kind)..addPosition(e.timeStamp, e.position);
    if (_full.isAnimating) _full.stop();
  }

  void _onMove(PointerMoveEvent e) {
    if (e.pointer != _pointer || _closing) return;
    _vt?.addPosition(e.timeStamp, e.position);
    final dy = e.delta.dy;
    if (!_paneDrag) {
      final total = e.position - _down;
      if (total.distance < 10 || total.dy.abs() < total.dx.abs()) return;
      // half open: any vertical drag moves the pane; full page: only a
      // pull down with the list at its top
      if (_full.value < 1 || (total.dy > 0 && _atTop)) {
        _paneDrag = true;
      } else {
        return;
      }
    }
    _moveBy(dy);
  }

  void _moveBy(double dy) {
    if (_closingDrag) {
      final c = _route;
      if (c == null) return;
      c.value = (c.value - dy / _h).clamp(0.0, 1.0);
      return;
    }
    if (dy > 0 && _full.value <= 0) {
      _closingDrag = true;
      widget.route.navigator?.didStartUserGesture();
      _moveBy(dy);
      return;
    }
    _full.value = (_full.value - dy / (_h / 2)).clamp(0.0, 1.0);
  }

  void _onUp(PointerEvent e) {
    if (e.pointer != _pointer) return;
    _pointer = null;
    final v = e is PointerUpEvent
        ? (_vt?.getVelocity().pixelsPerSecond.dy ?? 0)
        : 0.0;
    _vt = null;
    if (!_paneDrag) return;
    _paneDrag = false;
    if (_closingDrag) {
      _closingDrag = false;
      final c = _route;
      final nav = widget.route.navigator;
      if (c == null) return;
      if (v > 700 || c.value < 0.75) {
        _closing = true;
        Navigator.of(context).pop();
        if (c.isAnimating) {
          late AnimationStatusListener l;
          l = (s) {
            if (!c.isAnimating) {
              c.removeStatusListener(l);
              nav?.didStopUserGesture();
            }
          };
          c.addStatusListener(l);
        } else {
          nav?.didStopUserGesture();
        }
      } else {
        c
            .animateTo(1, duration: const Duration(milliseconds: 240), curve: Curves.easeOutCubic)
            .whenComplete(() => nav?.didStopUserGesture());
      }
      return;
    }
    final open = v < -400 || (v.abs() <= 400 && _full.value > 0.5);
    _full.animateTo(open ? 1 : 0, curve: Curves.easeOutCubic);
  }

  bool _onScroll(ScrollNotification n) {
    if (n.metrics.axis == Axis.vertical) {
      _atTop = n.metrics.extentBefore <= 0.5;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, box) {
        _h = box.maxHeight;
        return AnimatedBuilder(
          animation: _full,
          child: Listener(
            onPointerDown: _onDown,
            onPointerMove: _onMove,
            onPointerUp: _onUp,
            onPointerCancel: _onUp,
            child: NotificationListener<ScrollNotification>(
              onNotification: _onScroll,
              child: RepaintBoundary(
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(24),
                  ),
                  child: Stack(
                    children: [
                      // Glass look: the wallpaper behind the pane
                      const Positioned.fill(child: VibeGlassLayer()),
                      Positioned.fill(
                        child: ScrollConfiguration(
                          // half open (or moving): the list stays put
                          behavior: ScrollConfiguration.of(context).copyWith(
                            physics: _scrollLocked
                                ? const NeverScrollableScrollPhysics()
                                : const ClampingScrollPhysics(),
                          ),
                          child: widget.child,
                        ),
                      ),
                      Positioned(
                        top: MediaQuery.paddingOf(context).top + 6,
                        left: 0,
                        right: 0,
                        child: IgnorePointer(
                          child: Center(
                            child: Container(
                              width: 40,
                              height: 5,
                              decoration: BoxDecoration(
                                color: cs.onSurfaceVariant.withValues(alpha: 0.45),
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          builder: (context, child) => Transform.translate(
            offset: Offset(0, _h / 2 * (1 - _full.value)),
            child: child,
          ),
        );
      },
    );
  }
}
