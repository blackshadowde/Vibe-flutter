// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/vibe/vibe_haptics.dart';
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
  DateTime _lastBurst = DateTime(2000);
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
        // Mine from the reaction menu too, unless a double-tap already
        // played it a moment ago.
        if (sender != me ||
            DateTime.now().difference(_lastBurst).inSeconds >= 3) {
          heartFromOther = true;
        }
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
    final topLeft = box.localToGlobal(Offset.zero);
    final rect = topLeft & box.size;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    VibeHaptics.light();
    final origin =
        topLeft + Offset(box.size.width * 0.5, box.size.height * 0.4);
    final target = topLeft + Offset(86, box.size.height - 20);
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _ReactionBurst(
        emoji: emoji,
        rect: rect,
        origin: origin,
        target: target,
        onDone: () => entry.remove(),
      ),
    );
    overlay.insert(entry);
  }

  void _burst({bool fromOther = false}) {
    _lastBurst = DateTime.now();
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
    VibeHaptics.light();
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
// Non-heart reactions: the emoji pops up big over the message, the bubble
// flashes in a matching colour, themed particles burst out (confetti,
// sparkles, tears, flames…), then the emoji flies into its reaction chip.
// ---------------------------------------------------------------------------

enum _PKind { dot, star, drop, confetti, glyph, ember }

class _ReactionTheme {
  final List<Color> colors; // bubble tint + particle colours
  final List<_PKind> kinds;
  final List<String> glyphs; // small text particles (besides the emoji)
  final bool rise; // particles float up (fire) instead of falling
  const _ReactionTheme(
    this.colors,
    this.kinds, {
    this.glyphs = const [],
    this.rise = false,
  });
}

_ReactionTheme _themeFor(String e) {
  bool any(String chars) => chars.split(' ').any(e.contains);
  if (any('😂 🤣 😆 😹')) {
    return const _ReactionTheme(
      [Color(0xFFFFC83D), Color(0xFF4FC3F7), Color(0xFF29B6F6)],
      [_PKind.drop, _PKind.drop, _PKind.glyph],
    );
  }
  if (any('😢 😭 🥲 😿 💔')) {
    return const _ReactionTheme(
      [Color(0xFF64B5F6), Color(0xFF90CAF9), Color(0xFF1E88E5)],
      [_PKind.drop, _PKind.drop, _PKind.dot],
    );
  }
  if (any('😮 😲 😯 🤯 😱 🙀')) {
    return const _ReactionTheme(
      [Color(0xFFB9F6CA), Color(0xFFFFF59D), Color(0xFF80DEEA)],
      [_PKind.star, _PKind.star, _PKind.glyph],
      glyphs: ['❗', '❕'],
    );
  }
  if (any('🔥 💥 🌶')) {
    return const _ReactionTheme(
      [Color(0xFFFF7043), Color(0xFFFFB300), Color(0xFFFF3D00)],
      [_PKind.ember, _PKind.ember, _PKind.glyph],
      rise: true,
    );
  }
  if (any('🎉 🥳 🎊 🎂 🍾')) {
    return const _ReactionTheme(
      [
        Color(0xFFFF5252),
        Color(0xFFFFD740),
        Color(0xFF69F0AE),
        Color(0xFF40C4FF),
        Color(0xFFE040FB),
      ],
      [_PKind.confetti, _PKind.confetti, _PKind.confetti, _PKind.glyph],
    );
  }
  if (any('😡 🤬 😠 👿 💢')) {
    return const _ReactionTheme(
      [Color(0xFFFF5252), Color(0xFFFF8A65), Color(0xFFD50000)],
      [_PKind.dot, _PKind.glyph],
      glyphs: ['💢'],
    );
  }
  if (any('👍 👏 🙏 💪 ✅ 👌 🤝')) {
    return const _ReactionTheme(
      [Color(0xFFFFB74D), Color(0xFFF48FB1), Color(0xFFFFD54F)],
      [_PKind.glyph, _PKind.glyph, _PKind.star],
    );
  }
  if (any('👎')) {
    return const _ReactionTheme(
      [Color(0xFF90A4AE), Color(0xFFB0BEC5), Color(0xFF78909C)],
      [_PKind.glyph, _PKind.dot],
    );
  }
  if (any('😍 🥰 😘 💕 💖 💗 💘 💞 🧡 💛 💚 💙 💜 🤍 🖤')) {
    return const _ReactionTheme(
      [Color(0xFFFF80AB), Color(0xFFFF4081), Color(0xFFFFC1E3)],
      [_PKind.glyph, _PKind.glyph, _PKind.dot],
      glyphs: ['💕', '💖', '💗'],
    );
  }
  // Anything else: copies of the emoji + golden sparkles.
  return const _ReactionTheme(
    [Color(0xFF8C96F6), Color(0xFFFFD54F), Color(0xFF80DEEA)],
    [_PKind.glyph, _PKind.star, _PKind.dot],
  );
}

class _P {
  final _PKind kind;
  final double angle;
  final double speed;
  final double size;
  final double delay; // 0..1 of timeline
  final double spin;
  final Color color;
  final TextPainter? tp;
  const _P({
    required this.kind,
    required this.angle,
    required this.speed,
    required this.size,
    required this.delay,
    required this.spin,
    required this.color,
    this.tp,
  });
}

class _ReactionBurst extends StatefulWidget {
  final String emoji;
  final Rect rect;
  final Offset origin;
  final Offset target;
  final VoidCallback onDone;
  const _ReactionBurst({
    required this.emoji,
    required this.rect,
    required this.origin,
    required this.target,
    required this.onDone,
  });

  @override
  State<_ReactionBurst> createState() => _ReactionBurstState();
}

class _ReactionBurstState extends State<_ReactionBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1900),
  );
  late final _ReactionTheme _theme = _themeFor(widget.emoji);
  late final TextPainter _big = TextPainter(
    text: TextSpan(text: widget.emoji, style: const TextStyle(fontSize: 84)),
    textDirection: TextDirection.ltr,
  )..layout();
  late final List<_P> _ps;

  @override
  void initState() {
    super.initState();
    final r = math.Random();
    final glyphs = _theme.glyphs.isEmpty ? [widget.emoji] : _theme.glyphs;
    final tps = <String, TextPainter>{};
    _ps = List.generate(22, (i) {
      final kind = _theme.kinds[r.nextInt(_theme.kinds.length)];
      TextPainter? tp;
      var size = 6.0 + r.nextDouble() * 8;
      if (kind == _PKind.glyph) {
        size = 18 + r.nextDouble() * 14;
        final g = glyphs[r.nextInt(glyphs.length)];
        tp = tps.putIfAbsent(
          '$g$size',
          () => TextPainter(
            text: TextSpan(text: g, style: TextStyle(fontSize: size)),
            textDirection: TextDirection.ltr,
          )..layout(),
        );
      }
      final spread = _theme.rise ? math.pi * 0.9 : math.pi * 2;
      final base = _theme.rise ? -math.pi / 2 : 0.0;
      return _P(
        kind: kind,
        angle: base + (r.nextDouble() - 0.5) * spread,
        speed: 90 + r.nextDouble() * 120,
        size: size,
        delay: 0.08 + r.nextDouble() * 0.14,
        spin: (r.nextDouble() - 0.5) * 10,
        color: _theme.colors[r.nextInt(_theme.colors.length)],
        tp: tp,
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
        painter: _BurstPainter(
          t: _c.value,
          rect: widget.rect,
          origin: widget.origin,
          target: widget.target,
          theme: _theme,
          big: _big,
          ps: _ps,
        ),
      ),
    ),
  );
}

class _BurstPainter extends CustomPainter {
  final double t;
  final Rect rect;
  final Offset origin;
  final Offset target;
  final _ReactionTheme theme;
  final TextPainter big;
  final List<_P> ps;
  _BurstPainter({
    required this.t,
    required this.rect,
    required this.origin,
    required this.target,
    required this.theme,
    required this.big,
    required this.ps,
  });

  Path _star(Offset c, double r) {
    // 4-point sparkle
    final p = Path()..moveTo(c.dx, c.dy - r);
    p.quadraticBezierTo(c.dx, c.dy, c.dx + r, c.dy);
    p.quadraticBezierTo(c.dx, c.dy, c.dx, c.dy + r);
    p.quadraticBezierTo(c.dx, c.dy, c.dx - r, c.dy);
    p.quadraticBezierTo(c.dx, c.dy, c.dx, c.dy - r);
    return p..close();
  }

  Path _drop(Offset c, double r) {
    final p = Path()..moveTo(c.dx, c.dy - r * 1.6);
    p.quadraticBezierTo(c.dx + r * 1.1, c.dy - r * 0.2, c.dx + r, c.dy + r * 0.3);
    p.arcToPoint(
      Offset(c.dx - r, c.dy + r * 0.3),
      radius: Radius.circular(r),
    );
    p.quadraticBezierTo(c.dx - r * 1.1, c.dy - r * 0.2, c.dx, c.dy - r * 1.6);
    return p..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    // ---- 1. bubble flash (Google Messages style) ----
    final flash = t < 0.12
        ? t / 0.12
        : t < 0.5
        ? 1.0
        : (1 - (t - 0.5) / 0.3).clamp(0.0, 1.0);
    if (flash > 0) {
      final r = RRect.fromRectAndRadius(
        rect.deflate(4),
        const Radius.circular(14),
      );
      canvas.drawRRect(
        r,
        Paint()
          ..shader = LinearGradient(
            colors: [
              theme.colors.first.withValues(alpha: 0.30 * flash),
              theme.colors[1 % theme.colors.length].withValues(
                alpha: 0.22 * flash,
              ),
            ],
          ).createShader(rect),
      );
    }

    // ---- 2. shockwave ring ----
    final ringT = ((t - 0.08) / 0.35).clamp(0.0, 1.0);
    if (ringT > 0 && ringT < 1) {
      final e = Curves.easeOutCubic.transform(ringT);
      canvas.drawCircle(
        origin,
        30 + 90 * e,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4 * (1 - e) + 0.5
          ..color = theme.colors.first.withValues(alpha: 0.7 * (1 - e)),
      );
    }

    // ---- 3. themed particles ----
    for (final p in ps) {
      final u = ((t - p.delay) / 0.6).clamp(0.0, 1.0);
      if (u <= 0 || u >= 1) continue;
      final e = Curves.easeOutCubic.transform(u);
      final gravity = theme.rise ? -50.0 * u * u : 70.0 * u * u;
      final pos =
          origin +
          Offset(math.cos(p.angle), math.sin(p.angle)) * (p.speed * e) +
          Offset(0, gravity);
      final alpha = (1 - Curves.easeIn.transform(u)).clamp(0.0, 1.0);
      final paint = Paint()..color = p.color.withValues(alpha: alpha);
      switch (p.kind) {
        case _PKind.dot:
          canvas.drawCircle(pos, p.size * 0.45 * (1 - 0.4 * u), paint);
        case _PKind.star:
          canvas.drawPath(_star(pos, p.size * (1 - 0.3 * u) + 2), paint);
        case _PKind.drop:
          canvas.drawPath(_drop(pos, p.size * 0.5), paint);
        case _PKind.ember:
          final flicker = 0.7 + 0.3 * math.sin((t * 40) + p.spin);
          canvas.drawCircle(
            pos,
            p.size * 0.5 * (1 - 0.5 * u),
            Paint()
              ..color = p.color.withValues(alpha: alpha * flicker)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
          );
        case _PKind.confetti:
          canvas.save();
          canvas.translate(pos.dx, pos.dy);
          canvas.rotate(p.spin * u);
          canvas.drawRect(
            Rect.fromCenter(
              center: Offset.zero,
              width: p.size,
              height: p.size * 0.45,
            ),
            paint,
          );
          canvas.restore();
        case _PKind.glyph:
          final tp = p.tp;
          if (tp == null) break;
          canvas.saveLayer(
            null,
            Paint()..color = Colors.white.withValues(alpha: alpha),
          );
          canvas.translate(pos.dx, pos.dy);
          canvas.rotate(p.spin * 0.08 * u);
          canvas.scale(0.6 + 0.4 * Curves.easeOutBack.transform(e));
          tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
          canvas.restore();
      }
    }

    // ---- 4. the big emoji: pop, wobble, fly into the chip ----
    Offset pos;
    double scale;
    double alpha = 1;
    double rot = 0;
    if (t < 0.16) {
      pos = origin;
      scale = Curves.easeOutBack.transform(t / 0.16);
    } else if (t < 0.46) {
      final u = (t - 0.16) / 0.30;
      pos = origin - Offset(0, 6 * math.sin(u * math.pi));
      scale = 1.0 + 0.06 * math.sin(u * math.pi * 3);
      rot = 0.12 * math.sin(u * math.pi * 4) * (1 - u);
    } else if (t < 0.8) {
      final u = Curves.easeInOutCubic.transform((t - 0.46) / 0.34);
      // gentle arc on the way down to the chip
      pos =
          Offset.lerp(origin, target, u)! -
          Offset(0, 40 * math.sin(u * math.pi));
      scale = 1.0 - 0.78 * u;
    } else {
      pos = target;
      final u = (t - 0.8) / 0.2;
      scale = 0.22 + 0.06 * math.sin(u * math.pi);
      alpha = (1 - Curves.easeIn.transform(u)).clamp(0.0, 1.0);
    }
    if (scale <= 0 || alpha <= 0) return;
    // glow
    canvas.drawCircle(
      pos,
      big.width * 0.55 * scale,
      Paint()
        ..color = theme.colors.first.withValues(alpha: 0.35 * alpha)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 18 * scale + 1),
    );
    canvas.saveLayer(
      null,
      Paint()..color = Colors.white.withValues(alpha: alpha),
    );
    canvas.translate(pos.dx, pos.dy);
    canvas.rotate(rot);
    canvas.scale(scale);
    big.paint(canvas, Offset(-big.width / 2, -big.height / 2));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BurstPainter old) => old.t != t;
}
