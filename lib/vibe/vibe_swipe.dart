// SPDX-License-Identifier: AGPL-3.0-or-later


import 'package:flutter/gestures.dart';
import 'package:fluffychat/vibe/vibe_motion.dart';
import 'package:fluffychat/vibe/vibe_sheet_drag.dart';
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
      // Finger: follow it 1:1. Otherwise: the spring.
      final t = gesture ? v : vibeSpring.transform(v);
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
  Widget buildContent(BuildContext context) => (settings as VibePage<T>).child;

  @override
  bool get maintainState => true;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 440);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 380);
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
  Duration get transitionDuration => const Duration(milliseconds: 620);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 320);

  static final _rise = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(begin: 1.0, end: 0.5).chain(CurveTween(curve: Curves.easeOutCubic)),
      weight: 42,
    ),
    TweenSequenceItem(
      tween: Tween(begin: 0.5, end: 0.0).chain(CurveTween(curve: Curves.easeInOutCubic)),
      weight: 58,
    ),
  ]);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    final cs = Theme.of(context).colorScheme;
    return VibeSheetDragClose(
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: Stack(
          children: [
            Positioned.fill(child: builder(context)),
            // the grab handle (it closes by sliding down, no back button)
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
    );
  }

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
      // following a finger: 1:1; opening: half way, then all the way;
      // closing: straight down
      final double y;
      if (navigator?.userGestureInProgress == true) {
        y = 1 - v;
      } else if (animation.status == AnimationStatus.reverse) {
        y = 1 - Curves.easeOutCubic.transform(v);
      } else {
        y = _rise.transform(v);
      }
      return FractionalTranslation(translation: Offset(0, y), child: child);
    },
  );
}
