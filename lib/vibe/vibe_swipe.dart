// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:ui' show lerpDouble;

import 'package:flutter/gestures.dart';
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
    if (route.isFirst) return child;
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
        child: RepaintBoundary(child: child),
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
      final t = gesture ? v : Curves.easeOutCubic.transform(v);
      return FractionalTranslation(
        translation: Offset(1 - t, 0),
        child: DecoratedBox(
          decoration: BoxDecoration(
            boxShadow: t < 0.995
                ? [
                    BoxShadow(
                      color: Color.fromRGBO(0, 0, 0, 0.45 * t),
                      blurRadius: 24,
                      offset: const Offset(-8, 0),
                    ),
                  ]
                : const [],
          ),
          child: child,
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
        r.animation?.status == AnimationStatus.completed &&
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

  void _finish(double v) {
    final c = _ctl!;
    final nav = _nav!;
    final forward = v.abs() >= 1 ? v <= 0 : c.value > 0.5;
    if (forward) {
      c.animateTo(
        1.0,
        duration: Duration(
          milliseconds: lerpDouble(800, 0, c.value)!.floor().clamp(0, 800),
        ),
        curve: Curves.fastLinearToSlowEaseIn,
      );
    } else {
      nav.pop();
      if (c.isAnimating) {
        c.animateBack(
          0.0,
          duration: Duration(
            milliseconds: lerpDouble(0, 800, c.value)!.floor().clamp(0, 800),
          ),
          curve: Curves.fastLinearToSlowEaseIn,
        );
      }
    }
    if (c.isAnimating) {
      late AnimationStatusListener l;
      l = (status) {
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
