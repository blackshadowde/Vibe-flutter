// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:matrix/matrix.dart';

/// Handle given to the message so it can trigger the heart animation.
class VibeHeartHandle {
  final void Function(Offset) noteTap;
  final VoidCallback burst;
  const VibeHeartHandle({required this.noteTap, required this.burst});
}

/// Wraps a message row. Plays the heart animation when [VibeHeartHandle.burst]
/// is called (double tap) and when somebody else adds a ❤ reaction to it.
class VibeHeartHost extends StatefulWidget {
  final Event event;
  final Timeline timeline;
  final Widget Function(BuildContext context, VibeHeartHandle heart) builder;

  const VibeHeartHost({
    required this.event,
    required this.timeline,
    required this.builder,
    super.key,
  });

  @override
  State<VibeHeartHost> createState() => _VibeHeartHostState();
}

class _VibeHeartHostState extends State<VibeHeartHost> {
  Offset? _lastTap;
  Set<String> _others = {};

  Set<String> _heartSenders() {
    final me = widget.event.room.client.userID;
    final result = <String>{};
    for (final e in widget.event.aggregatedEvents(
      widget.timeline,
      RelationshipTypes.reaction,
    )) {
      if (e.type != 'm.reaction' || e.redacted) continue;
      final key = e.content
          .tryGetMap<String, Object?>('m.relates_to')
          ?.tryGet<String>('key');
      if (key == null || !key.contains('❤')) continue;
      if (e.senderId != me) result.add(e.senderId);
    }
    return result;
  }

  @override
  void initState() {
    super.initState();
    _others = _heartSenders();
  }

  @override
  void didUpdateWidget(VibeHeartHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    final now = _heartSenders();
    final isNew = now.difference(_others).isNotEmpty;
    _others = now;
    if (isNew) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _burst(fromOther: true);
      });
    }
  }

  void _burst({bool fromOther = false}) {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return;
    final size = box.size;
    final topLeft = box.localToGlobal(Offset.zero);
    final tap = fromOther ? null : _lastTap;
    final origin = tap ?? topLeft + Offset(size.width * 0.5, size.height * 0.45);
    // Where the ❤ 1 chip shows up: under the message text.
    final target = topLeft + Offset(86, size.height - 20);
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    HapticFeedback.lightImpact();
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _HeartBurst(
        origin: origin,
        target: target,
        onDone: () => entry.remove(),
      ),
    );
    overlay.insert(entry);
  }

  @override
  Widget build(BuildContext context) => widget.builder(
    context,
    VibeHeartHandle(noteTap: (p) => _lastTap = p, burst: _burst),
  );
}

class _Tiny {
  final double angle;
  final double speed;
  final double size;
  final double delay;
  final Color color;
  const _Tiny(this.angle, this.speed, this.size, this.delay, this.color);
}

class _HeartBurst extends StatefulWidget {
  final Offset origin;
  final Offset target;
  final VoidCallback onDone;
  const _HeartBurst({
    required this.origin,
    required this.target,
    required this.onDone,
  });

  @override
  State<_HeartBurst> createState() => _HeartBurstState();
}

class _HeartBurstState extends State<_HeartBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1700),
  );
  late final List<_Tiny> _tiny;

  static const _colors = [
    Color(0xFFFF5A5F),
    Color(0xFFFF7A7A),
    Color(0xFFFFB3B3),
    Color(0xFFFF4D6D),
    Color(0xFFFFC2D1),
  ];

  @override
  void initState() {
    super.initState();
    final r = math.Random();
    _tiny = List.generate(16, (i) {
      return _Tiny(
        -math.pi / 2 + (r.nextDouble() - 0.5) * math.pi * 1.7,
        70 + r.nextDouble() * 110,
        8 + r.nextDouble() * 9,
        0.1 + r.nextDouble() * 0.12,
        _colors[r.nextInt(_colors.length)],
      );
    });
    _c.forward().whenComplete(widget.onDone);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => CustomPaint(
          size: Size.infinite,
          painter: _HeartPainter(
            t: _c.value,
            origin: widget.origin,
            target: widget.target,
            tiny: _tiny,
          ),
        ),
      ),
    );
  }
}

class _HeartPainter extends CustomPainter {
  final double t;
  final Offset origin;
  final Offset target;
  final List<_Tiny> tiny;
  _HeartPainter({
    required this.t,
    required this.origin,
    required this.target,
    required this.tiny,
  });

  static final List<Offset> _unit = [
    for (var i = 0; i <= 72; i++)
      () {
        final a = i / 72 * 2 * math.pi;
        final x = 16 * math.pow(math.sin(a), 3).toDouble();
        final y =
            13 * math.cos(a) -
            5 * math.cos(2 * a) -
            2 * math.cos(3 * a) -
            math.cos(4 * a);
        return Offset(x / 17, -y / 17);
      }(),
  ];

  Path _heart(Offset c, double size) {
    final p = Path();
    for (var i = 0; i < _unit.length; i++) {
      final o = c + _unit[i] * (size / 2);
      if (i == 0) {
        p.moveTo(o.dx, o.dy);
      } else {
        p.lineTo(o.dx, o.dy);
      }
    }
    return p..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    // ---- tiny hearts flying out and fading ----
    for (final h in tiny) {
      final u = ((t - h.delay) / 0.55).clamp(0.0, 1.0);
      if (u <= 0 || u >= 1) continue;
      final e = Curves.easeOut.transform(u);
      final pos =
          origin +
          Offset(math.cos(h.angle), math.sin(h.angle)) * (h.speed * e) +
          Offset(0, 40 * u * u); // soft gravity
      final alpha = (1 - Curves.easeIn.transform(u)).clamp(0.0, 1.0);
      canvas.drawPath(
        _heart(pos, h.size * (1 - 0.3 * u)),
        Paint()..color = h.color.withValues(alpha: alpha),
      );
    }

    // ---- big heart: pop, hold, then fly to the message and settle ----
    final Offset pos;
    final double scale;
    double alpha = 1;
    if (t < 0.15) {
      pos = origin;
      scale = Curves.easeOutBack.transform(t / 0.15) * 1.0;
    } else if (t < 0.42) {
      pos = origin;
      scale = 1.0;
    } else if (t < 0.78) {
      final u = Curves.easeInOutCubic.transform((t - 0.42) / 0.36);
      pos = Offset.lerp(origin, target, u)!;
      scale = 1.0 - 0.8 * u; // 1.0 -> 0.2
    } else {
      pos = target;
      final u = (t - 0.78) / 0.22;
      // tiny settle bounce then fade into the real reaction chip
      scale = 0.2 + 0.05 * math.sin(u * math.pi);
      alpha = (1 - Curves.easeIn.transform(u)).clamp(0.0, 1.0);
    }
    if (scale <= 0 || alpha <= 0) return;
    const base = 96.0;
    final s = base * scale;
    // soft glow
    canvas.drawPath(
      _heart(pos, s * 1.18),
      Paint()
        ..color = const Color(0xFFFF6B6B).withValues(alpha: 0.35 * alpha)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 8 * scale + 1),
    );
    canvas.drawPath(
      _heart(pos, s),
      Paint()..color = const Color(0xFFFF5A5F).withValues(alpha: alpha),
    );
    canvas.drawPath(
      _heart(pos, s * 0.62),
      Paint()..color = const Color(0xFFFFB3B8).withValues(alpha: alpha),
    );
  }

  @override
  bool shouldRepaint(_HeartPainter old) => old.t != t;
}
