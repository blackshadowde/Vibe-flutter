// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';

/// Google-Messages style entrance for a brand new message: the row grows from
/// the bottom (so the whole timeline glides up smoothly) while the bubble
/// slides up, scales from its corner and fades in. Messages that do not
/// animate are returned untouched (zero overhead).
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
  AnimationController? _c;
  late final GlobalKey? _gk = widget.animate ? GlobalKey() : null;
  Animation<double>? _size;
  Animation<double>? _pop;
  Animation<double>? _fade;

  @override
  void initState() {
    super.initState();
    if (!widget.animate) return;
    final c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 460),
    );
    _c = c;
    _size = CurvedAnimation(
      parent: c,
      curve: const Interval(0.0, 0.8, curve: Curves.easeOutCubic),
    );
    _pop = CurvedAnimation(parent: c, curve: Curves.easeOutBack);
    _fade = CurvedAnimation(
      parent: c,
      curve: const Interval(0.0, 0.55, curve: Curves.easeOut),
    );
    c.addStatusListener((s) {
      if (s == AnimationStatus.completed && mounted) setState(() {});
    });
    c.forward();
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    if (c == null) return widget.child;
    final inner = KeyedSubtree(key: _gk, child: widget.child);
    if (c.isCompleted) return inner;
    return AnimatedBuilder(
      animation: c,
      child: inner,
      builder: (context, child) {
        final p = _pop!.value;
        return SizeTransition(
          sizeFactor: _size!,
          axisAlignment: 1.0,
          child: Opacity(
            opacity: _fade!.value.clamp(0.0, 1.0),
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
