// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';

/// Google-Messages style entrance for a brand new message: the row grows from
/// the bottom (so the whole timeline glides up smoothly) while the bubble
/// slides up, scales from its corner and fades in.
class VibeEntrance extends StatefulWidget {
  final bool animate;
  final bool fromRight;
  final Widget child;

  const VibeEntrance({
    required this.animate,
    required this.fromRight,
    required this.child,
    super.key,
  });

  @override
  State<VibeEntrance> createState() => _VibeEntranceState();
}

class _VibeEntranceState extends State<VibeEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 460),
    value: widget.animate ? 0 : 1,
  );

  late final Animation<double> _size = CurvedAnimation(
    parent: _c,
    curve: const Interval(0.0, 0.8, curve: Curves.easeOutCubic),
  );
  late final Animation<double> _pop = CurvedAnimation(
    parent: _c,
    curve: Curves.easeOutBack,
  );
  late final Animation<double> _fade = CurvedAnimation(
    parent: _c,
    curve: const Interval(0.0, 0.55, curve: Curves.easeOut),
  );

  @override
  void initState() {
    super.initState();
    if (widget.animate) _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) {
        final p = _pop.value;
        return SizeTransition(
          sizeFactor: _size,
          axisAlignment: 1.0,
          child: Opacity(
            opacity: _fade.value.clamp(0.0, 1.0),
            child: Transform.translate(
              offset: Offset(0, (1 - p) * 38),
              child: Transform.scale(
                scale: 0.86 + 0.14 * p,
                alignment: widget.fromRight
                    ? Alignment.bottomRight
                    : Alignment.bottomLeft,
                child: child,
              ),
            ),
          ),
        );
      },
    );
  }
}
