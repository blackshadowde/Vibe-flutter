// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/vibe/vibe_haptics.dart';
import 'package:flutter/material.dart';

/// Shrinks slightly while a finger is down and springs back on release.
/// Uses a [Listener], so taps and long presses of the child keep working.
class VibePressable extends StatefulWidget {
  final Widget child;
  final double scale;
  const VibePressable({required this.child, this.scale = 0.95, super.key});

  @override
  State<VibePressable> createState() => _VibePressableState();
}

class _VibePressableState extends State<VibePressable> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v && mounted) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (_) {
      VibeHaptics.selection();
      _set(true);
    },
    onPointerUp: (_) => _set(false),
    onPointerCancel: (_) => _set(false),
    child: AnimatedScale(
      scale: _down ? widget.scale : 1,
      duration: Duration(milliseconds: _down ? 90 : 320),
      curve: _down ? Curves.easeOut : Curves.easeOutBack,
      child: widget.child,
    ),
  );
}

/// Fade + rise-in, once, with a small per-index delay. Items beyond
/// [maxIndex] (scrolled in later) appear without animation.
class VibeStagger extends StatefulWidget {
  final int index;
  final int maxIndex;
  final double dy;
  final Widget child;
  const VibeStagger({
    required this.index,
    required this.child,
    this.maxIndex = 12,
    this.dy = 18,
    super.key,
  });

  @override
  State<VibeStagger> createState() => _VibeStaggerState();
}

class _VibeStaggerState extends State<VibeStagger>
    with SingleTickerProviderStateMixin {
  late final bool _play = widget.index <= widget.maxIndex;
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 460),
    value: _play ? 0 : 1,
  );
  late final Animation<double> _curve = CurvedAnimation(
    parent: _c,
    curve: Curves.easeOutCubic,
  );

  @override
  void initState() {
    super.initState();
    if (_play) {
      Future<void>.delayed(Duration(milliseconds: 32 * widget.index), () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _curve,
    child: widget.child,
    builder: (context, child) => Opacity(
      opacity: _curve.value.clamp(0.0, 1.0),
      child: Transform.translate(
        offset: Offset(0, (1 - _curve.value) * widget.dy),
        child: child,
      ),
    ),
  );
}

/// The smooth, slow-out animation used by every sheet in the app.
const AnimationStyle vibeSheetStyle = AnimationStyle(
  duration: Duration(milliseconds: 460),
  reverseDuration: Duration(milliseconds: 260),
  curve: Curves.easeOutQuint,
  reverseCurve: Curves.easeInCubic,
);
