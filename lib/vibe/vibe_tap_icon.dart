// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// How an icon reacts when tapped.
enum VibeTap {
  /// gear: turns a third of the way round
  spin,

  /// bell: swings like it's ringing
  ring,

  /// shield, pin, star: a springy pop
  pop,
}

/// The whole tappable area (a row, a big round button): any
/// [VibeTapIcon] inside plays when the finger lands anywhere in it.
class VibeTapArea extends StatefulWidget {
  final Widget child;
  const VibeTapArea({required this.child, super.key});

  @override
  State<VibeTapArea> createState() => _VibeTapAreaState();
}

class _VibeTapAreaState extends State<VibeTapArea> {
  final _taps = ValueNotifier<int>(0);

  @override
  void dispose() {
    _taps.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: (_) => _taps.value++,
    child: _TapScope(notifier: _taps, child: widget.child),
  );
}

class _TapScope extends InheritedNotifier<ValueNotifier<int>> {
  const _TapScope({required super.notifier, required super.child});
}

/// Gives an icon a little life when the finger lands on it (or on the
/// [VibeTapArea] around it). It never takes the tap, it only watches it.
class VibeTapIcon extends StatefulWidget {
  final VibeTap kind;
  final Widget child;
  const VibeTapIcon({required this.kind, required this.child, super.key});

  @override
  State<VibeTapIcon> createState() => _VibeTapIconState();
}

class _VibeTapIconState extends State<VibeTapIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: Duration(
      milliseconds: switch (widget.kind) {
        VibeTap.spin => 650,
        VibeTap.ring => 700,
        VibeTap.pop => 420,
      },
    ),
  );

  ValueNotifier<int>? _area;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final area = context
        .getInheritedWidgetOfExactType<_TapScope>()
        ?.notifier;
    if (area != _area) {
      _area?.removeListener(_play);
      _area = area?..addListener(_play);
    }
  }

  @override
  void dispose() {
    _area?.removeListener(_play);
    _c.dispose();
    super.dispose();
  }

  void _play() {
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return;
    _c.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: _area == null ? (_) => _play() : null,
    child: AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) {
        final t = _c.value;
        switch (widget.kind) {
          case VibeTap.spin:
            return Transform.rotate(
              angle: Curves.easeOutBack.transform(t) * 2 * math.pi / 3,
              child: child,
            );
          case VibeTap.ring:
            // swings that fade out, hinged at the top like a real bell
            final a = math.sin(t * math.pi * 6) * (1 - t) * 0.45;
            return Transform.rotate(
              angle: a,
              alignment: Alignment.topCenter,
              child: child,
            );
          case VibeTap.pop:
            final s = 1 + math.sin(t * math.pi) * 0.28 * (1 - t * 0.4);
            return Transform.scale(scale: s, child: child);
        }
      },
    ),
  );
}
