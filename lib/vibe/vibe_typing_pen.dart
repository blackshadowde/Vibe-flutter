// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

/// Puts a tiny "pen writing" badge on the bottom-left of [child] (an avatar)
/// while someone in [room] is typing.
class VibeTypingOverlay extends StatefulWidget {
  final Room room;
  final Widget child;
  final double badgeSize;
  final Color? ringColor;

  const VibeTypingOverlay({
    required this.room,
    required this.child,
    this.badgeSize = 22,
    this.ringColor,
    super.key,
  });

  @override
  State<VibeTypingOverlay> createState() => _VibeTypingOverlayState();
}

class _VibeTypingOverlayState extends State<VibeTypingOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  StreamSubscription<SyncUpdate>? _sub;
  bool _typing = false;

  bool _compute() {
    final me = widget.room.client.userID;
    return widget.room.typingUsers.any((u) => u.id != me);
  }

  void _listen() {
    _sub?.cancel();
    _typing = _compute();
    _sync();
    final id = widget.room.id;
    _sub = widget.room.client.onSync.stream
        .where(
          (u) =>
              u.rooms?.join?[id]?.ephemeral?.any(
                (e) => e.type == 'm.typing',
              ) ??
              false,
        )
        .listen((_) {
          final now = _compute();
          if (now != _typing && mounted) {
            setState(() => _typing = now);
            _sync();
          }
        });
  }

  void _sync() {
    if (_typing) {
      if (!_ctrl.isAnimating) _ctrl.repeat();
    } else {
      _ctrl.stop();
    }
  }

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1700),
    );
    _listen();
  }

  @override
  void didUpdateWidget(covariant VibeTypingOverlay old) {
    super.didUpdateWidget(old);
    if (old.room.id != widget.room.id) _listen();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = widget.badgeSize;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        widget.child,
        Positioned(
          left: -4,
          bottom: -4,
          child: IgnorePointer(
            child: AnimatedScale(
              scale: _typing ? 1 : 0,
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutBack,
              child: Container(
                width: s,
                height: s,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: cs.surfaceContainerHighest,
                  border: Border.all(
                    width: 2,
                    color: widget.ringColor ?? cs.surface,
                  ),
                ),
                child: AnimatedBuilder(
                  animation: _ctrl,
                  builder: (context, _) => CustomPaint(
                    painter: _PenPainter(
                      t: _ctrl.value,
                      line: cs.onSurfaceVariant,
                      pen: cs.onSurface,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PenPainter extends CustomPainter {
  final double t;
  final Color line;
  final Color pen;
  _PenPainter({required this.t, required this.line, required this.pen});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    // Squiggle across the lower part of the badge.
    final path = Path()..moveTo(w * 0.18, h * 0.66);
    path.cubicTo(w * 0.28, h * 0.40, w * 0.36, h * 0.40, w * 0.44, h * 0.62);
    path.cubicTo(w * 0.52, h * 0.82, w * 0.60, h * 0.82, w * 0.68, h * 0.58);
    final metric = path.computeMetrics().first;

    final p = (t / 0.78).clamp(0.0, 1.0);
    final fade = t > 0.88 ? (1 - (t - 0.88) / 0.12) : 1.0;
    final len = metric.length * Curves.easeInOut.transform(p);
    final drawn = metric.extractPath(0, len);

    canvas.drawPath(
      drawn,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 1.4
        ..color = line.withValues(alpha: fade),
    );

    final tan = metric.getTangentForOffset(len);
    if (tan == null) return;
    final tip = tan.position;
    final penPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 1.7
      ..color = pen.withValues(alpha: fade);
    // Minimal pen: a diagonal stroke from the nib up and to the right.
    final end = tip + Offset(w * 0.22, -h * 0.30);
    canvas.drawLine(tip, end, penPaint);
    canvas.drawCircle(
      tip,
      0.9,
      Paint()..color = pen.withValues(alpha: fade),
    );
  }

  @override
  bool shouldRepaint(covariant _PenPainter old) =>
      old.t != t || old.line != line || old.pen != pen;
}
