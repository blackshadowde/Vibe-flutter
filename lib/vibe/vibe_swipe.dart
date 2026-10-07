// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Shared state for the "drag the chat in with your finger" gesture.
///
/// While [active] is true the chat route being opened ([targetRoute]) and the
/// page underneath follow [anim] (driven by the finger) instead of their own
/// route animation.
abstract class VibeSwipe {
  static final ValueNotifier<bool> active = ValueNotifier<bool>(false);
  static Animation<double>? anim;
  static bool pending = false;
  static Route<dynamic>? targetRoute;

  static void reset() {
    active.value = false;
    pending = false;
    targetRoute = null;
  }
}

/// iOS style page transition that can be taken over by [VibeSwipe].
class VibePageTransitionsBuilder extends PageTransitionsBuilder {
  const VibePageTransitionsBuilder();

  static const _cupertino = CupertinoPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (VibeSwipe.pending &&
        VibeSwipe.targetRoute == null &&
        animation.status == AnimationStatus.forward &&
        animation.value < 0.5) {
      VibeSwipe.targetRoute = route;
      VibeSwipe.pending = false;
    }
    final isTarget = identical(route, VibeSwipe.targetRoute);
    return ValueListenableBuilder<bool>(
      valueListenable: VibeSwipe.active,
      builder: (ctx, on, _) {
        final drag = VibeSwipe.anim;
        if (!on || drag == null) {
          return _cupertino.buildTransitions<T>(
            route,
            ctx,
            animation,
            secondaryAnimation,
            child,
          );
        }
        return _cupertino.buildTransitions<T>(
          route,
          ctx,
          isTarget ? drag : animation,
          isTarget ? secondaryAnimation : drag,
          child,
        );
      },
    );
  }
}
