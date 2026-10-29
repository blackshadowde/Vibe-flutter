// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:vibe/vibe/vibe_palette.dart';
import 'package:vibe/vibe/vibe_haptics.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:vibe/widgets/matrix.dart';

/// Discord style swipe-to-reply: the message slides left, a blue circle with
/// a reply arrow grows in at the right edge and pops (with a strong, short
/// vibration) once the swipe is far enough. Release to reply.
///
/// Keep holding there and (for text, when [onQuote] is set) the arrow turns
/// into a quote mark with a second vibration: release to quote part of the
/// message instead.
class VibeSwipeReply extends StatefulWidget {
  final Widget child;
  final VoidCallback onReply;
  final VoidCallback? onQuote;
  const VibeSwipeReply({
    super.key,
    required this.child,
    required this.onReply,
    this.onQuote,
  });

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
  bool _quote = false;
  Timer? _hold;

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
    _hold?.cancel();
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
      if (widget.onQuote != null) {
        _hold?.cancel();
        _hold = Timer(const Duration(milliseconds: 600), () {
          if (!mounted || !_armed) return;
          VibeHaptics.heavy();
          setState(() => _quote = true);
        });
      }
    } else if (!armed && _armed) {
      _hold?.cancel();
      _quote = false;
    }
    setState(() {
      _dx = next;
      _armed = armed;
    });
  }

  void _end([DragEndDetails? d]) {
    final fire = _armed;
    final quote = _quote;
    _hold?.cancel();
    _armed = false;
    _quote = false;
    _from = _dx;
    _back.forward(from: 0);
    // Let the bubble spring back on its own frames first, then open the
    // reply bar (that rebuild + keyboard was causing the stutter).
    if (fire) {
      Future.delayed(const Duration(milliseconds: 140), () {
        if (!mounted) return;
        if (quote) {
          widget.onQuote?.call();
        } else {
          widget.onReply();
          _tip();
        }
      });
    }
  }

  /// The first few swipe-replies teach the hold (new feature hint).
  void _tip() {
    if (widget.onQuote == null) return;
    try {
      final store = Matrix.of(context).store;
      const key = 'vibe_hint_swipe_quote';
      final seen = store.getInt(key) ?? 0;
      if (seen >= 3) return;
      store.setInt(key, seen + 1);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text(
            'New: swipe and keep holding to quote just part of a message',
          ),
          duration: Duration(seconds: 4),
        ),
      );
    } catch (_) {}
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
                        color: VibePalette.accent,
                        shape: BoxShape.circle,
                        boxShadow: _armed
                            ? [
                                BoxShadow(
                                  color: VibePalette.accent.withAlpha(120),
                                  blurRadius: 10,
                                ),
                              ]
                            : null,
                      ),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 160),
                        transitionBuilder: (c, a) =>
                            ScaleTransition(scale: a, child: c),
                        child: Icon(
                          _quote ? Icons.format_quote_rounded : Icons.reply,
                          key: ValueKey(_quote),
                          color: Colors.white,
                          size: 22,
                        ),
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
