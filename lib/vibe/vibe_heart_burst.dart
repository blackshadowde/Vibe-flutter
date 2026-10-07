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
  Set<String> _seen = {};

  /// All reactions on this message as "sender<NUL>key".
  Set<String> _pairs() {
    final result = <String>{};
    for (final e in widget.event.aggregatedEvents(
      widget.timeline,
      RelationshipTypes.reaction,
    )) {
      if (e.type != 'm.reaction' || e.redacted) continue;
      final key = e.content
          .tryGetMap<String, Object?>('m.relates_to')
          ?.tryGet<String>('key');
      if (key == null || key.isEmpty) continue;
      result.add('${e.senderId}\u0000$key');
    }
    return result;
  }

  @override
  void initState() {
    super.initState();
    _seen = _pairs();
  }

  @override
  void didUpdateWidget(VibeHeartHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    final now = _pairs();
    final fresh = now.difference(_seen);
    _seen = now;
    if (fresh.isEmpty) return;
    final me = widget.event.room.client.userID;
    var heartFromOther = false;
    final emojis = <String, bool>{}; // emoji -> mine
    for (final p in fresh) {
      final i = p.indexOf('\u0000');
      final sender = p.substring(0, i);
      final key = p.substring(i + 1);
      if (key.contains('❤')) {
        if (sender != me) heartFromOther = true;
      } else {
        emojis[key] = (emojis[key] ?? false) || sender == me;
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (heartFromOther) _burst(fromOther: true);
      for (final entry in emojis.entries.take(2)) {
        _fall(entry.key, mine: entry.value);
      }
    });
  }

  void _fall(String emoji, {required bool mine}) {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return;
    final rect = box.localToGlobal(Offset.zero) & box.size;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    HapticFeedback.selectionClick();
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _EmojiFall(
        emoji: emoji,
        rect: rect,
        fromRight: mine,
        onDone: () => entry.remove(),
      ),
    );
    overlay.insert(entry);
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


// ---------------------------------------------------------------------------
// Non-heart reactions: the emoji fly up from below and fall onto the message.
// ---------------------------------------------------------------------------

class _Drop {
  final double delay; // seconds
  final double flight; // seconds
  final Offset from;
  final Offset to;
  final double spin;
  final double tilt;
  final TextPainter tp;
  final double size;
  const _Drop({
    required this.delay,
    required this.flight,
    required this.from,
    required this.to,
    required this.spin,
    required this.tilt,
    required this.tp,
    required this.size,
  });
}

class _EmojiFall extends StatefulWidget {
  final String emoji;
  final Rect rect;
  final bool fromRight;
  final VoidCallback onDone;
  const _EmojiFall({
    required this.emoji,
    required this.rect,
    required this.fromRight,
    required this.onDone,
  });

  @override
  State<_EmojiFall> createState() => _EmojiFallState();
}

class _EmojiFallState extends State<_EmojiFall>
    with SingleTickerProviderStateMixin {
  static const double _total = 2.3; // seconds
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: (_total * 1000).round()),
  );
  late final List<_Drop> _drops;

  @override
  void initState() {
    super.initState();
    final r = math.Random();
    final rect = widget.rect;
    _drops = List.generate(9, (i) {
      final size = 22.0 + r.nextDouble() * 14;
      final tp = TextPainter(
        text: TextSpan(text: widget.emoji, style: TextStyle(fontSize: size)),
        textDirection: TextDirection.ltr,
      )..layout();
      final ox = widget.fromRight
          ? rect.right - 40 - r.nextDouble() * 50
          : rect.left + 50 + r.nextDouble() * 60;
      final from = Offset(ox, rect.bottom + 30 + r.nextDouble() * 20);
      final to = Offset(
        rect.left + rect.width * (0.22 + 0.6 * r.nextDouble()),
        rect.top + rect.height * (0.3 + 0.5 * r.nextDouble()),
      );
      return _Drop(
        delay: r.nextDouble() * 0.35,
        flight: 0.7 + r.nextDouble() * 0.2,
        from: from,
        to: to,
        spin: (r.nextDouble() - 0.5) * 9,
        tilt: (r.nextDouble() - 0.5) * 0.7,
        tp: tp,
        size: size,
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
  Widget build(BuildContext context) => IgnorePointer(
    child: AnimatedBuilder(
      animation: _c,
      builder: (context, _) => CustomPaint(
        size: Size.infinite,
        painter: _FallPainter(_c.value * _total, _drops),
      ),
    ),
  );
}

class _FallPainter extends CustomPainter {
  final double sec;
  final List<_Drop> drops;
  _FallPainter(this.sec, this.drops);

  static const double _g = 2400;

  @override
  void paint(Canvas canvas, Size size) {
    final fade = sec > 1.8 ? (1 - (sec - 1.8) / 0.5).clamp(0.0, 1.0) : 1.0;
    for (final d in drops) {
      final t = sec - d.delay;
      if (t <= 0) continue;
      final T = d.flight;
      final Offset pos;
      double scale;
      double rot;
      if (t < T) {
        final dx = d.to.dx - d.from.dx;
        final dy = d.to.dy - d.from.dy;
        final vx = dx / T;
        final vy = (dy - 0.5 * _g * T * T) / T;
        pos = Offset(d.from.dx + vx * t, d.from.dy + vy * t + 0.5 * _g * t * t);
        scale = 0.55 + 0.45 * Curves.easeOut.transform((t / 0.25).clamp(0.0, 1.0));
        rot = d.spin * t;
      } else {
        final u = t - T;
        final bounce = 12 * math.exp(-7 * u) * math.sin(16 * u).abs();
        pos = d.to - Offset(0, bounce);
        // squash on impact
        scale = 1 - 0.18 * math.exp(-9 * u) * math.cos(18 * u).abs();
        rot = d.spin * T + (d.tilt - d.spin * T) * (1 - math.exp(-6 * u));
      }
      canvas.saveLayer(
        null,
        Paint()..color = Colors.white.withValues(alpha: fade),
      );
      canvas.translate(pos.dx, pos.dy);
      canvas.rotate(rot);
      canvas.scale(scale);
      d.tp.paint(canvas, Offset(-d.tp.width / 2, -d.tp.height / 2));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_FallPainter old) => old.sec != sec;
}
