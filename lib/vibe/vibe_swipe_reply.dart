// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/vibe/vibe_haptics.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Discord style swipe-to-reply: the message slides left, a blue circle with
/// a reply arrow grows in at the right edge and pops (with a strong, short
/// vibration) once the swipe is far enough. Release to reply.
class VibeSwipeReply extends StatefulWidget {
  final Widget child;
  final VoidCallback onReply;
  const VibeSwipeReply({super.key, required this.child, required this.onReply});

  @override
  State<VibeSwipeReply> createState() => _VibeSwipeReplyState();
}

class _VibeSwipeReplyState extends State<VibeSwipeReply>
    with SingleTickerProviderStateMixin {
  static const _threshold = 72.0;
  static const _maxDrag = 110.0;

  late final AnimationController _back = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
  );
  double _dx = 0; // always <= 0
  double _from = 0;
  bool _armed = false;

  @override
  void initState() {
    super.initState();
    _back.addListener(() {
      setState(() {
        _dx = _from * (1 - Curves.easeOutCubic.transform(_back.value));
      });
    });
  }

  @override
  void dispose() {
    _back.dispose();
    super.dispose();
  }

  void _update(DragUpdateDetails d) {
    if (_back.isAnimating) _back.stop();
    var next = _dx + d.delta.dx;
    if (next > 0) next = 0;
    // Rubber band past the threshold.
    if (next < -_threshold) {
      next = _dx + d.delta.dx * 0.45;
    }
    next = next.clamp(-_maxDrag, 0.0);
    final armed = next <= -_threshold;
    if (armed && !_armed) {
      VibeHaptics.heavy();
    }
    setState(() {
      _dx = next;
      _armed = armed;
    });
  }

  void _end([DragEndDetails? d]) {
    final fire = _armed;
    _armed = false;
    _from = _dx;
    _back.forward(from: 0);
    // Let the bubble spring back on its own frames first, then open the
    // reply bar (that rebuild + keyboard was causing the stutter).
    if (fire) {
      Future.delayed(const Duration(milliseconds: 140), () {
        if (mounted) widget.onReply();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final progress = (-_dx / _threshold).clamp(0.0, 1.0);
    return RepaintBoundary(
      child: GestureDetector(
      behavior: HitTestBehavior.translucent,
      dragStartBehavior: DragStartBehavior.down,
      onHorizontalDragUpdate: _update,
      onHorizontalDragEnd: _end,
      onHorizontalDragCancel: _end,
      child: ClipRect(
        child: Stack(
          alignment: Alignment.centerRight,
          children: [
            if (_dx < -1)
              Positioned(
                right: 16,
                child: Opacity(
                  opacity: progress,
                  child: AnimatedScale(
                    scale: _armed ? 1.15 : 0.55 + 0.45 * progress,
                    duration: const Duration(milliseconds: 140),
                    curve: Curves.easeOutBack,
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: const Color(0xFF5865F2),
                        shape: BoxShape.circle,
                        boxShadow: _armed
                            ? [
                                BoxShadow(
                                  color: const Color(0xFF5865F2).withAlpha(120),
                                  blurRadius: 10,
                                ),
                              ]
                            : null,
                      ),
                      child: const Icon(
                        Icons.reply,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                  ),
                ),
              ),
            Transform.translate(offset: Offset(_dx, 0), child: widget.child),
          ],
        ),
      ),
    ),
    );
  }
}
