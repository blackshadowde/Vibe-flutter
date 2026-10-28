// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:math' as math;

import 'package:matrix/matrix.dart';
import 'package:vibe/vibe/vibe_haptics.dart';
import 'package:flutter/material.dart';

/// Deleting a message: a small samurai (straw hat, red headband, big
/// katana) appears at the end of the message, crouches, and dashes through
/// it to the start, cutting it away behind him; there he drives his sword
/// into the ground and walks off, leaving it planted where the message was.
///
/// It all happens inside the message's own row, takes about 1.5 s, and is
/// skipped when the phone asks for reduced motion.
abstract class VibeSlash {
  static final active = ValueNotifier<Set<String>>({});
  static const duration = Duration(milliseconds: 1700);

  /// Plays the slash on [eventIds] and completes when the cut is done.
  static Future<void> play(BuildContext context, Iterable<String> eventIds) async {
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return;
    final ids = eventIds.toSet();
    if (ids.isEmpty) return;
    // let the message menu / confirm dialog finish sliding down first
    await Future<void>.delayed(const Duration(milliseconds: 420));
    active.value = {...active.value, ...ids};
    await Future<void>.delayed(duration);
  }

  /// The rows go back to normal (after the message was deleted or hidden).
  static void clear(Iterable<String> eventIds) {
    final ids = eventIds.toSet();
    active.value = {...active.value}..removeAll(ids);
  }

  // ---- the other side: someone else deleted a message for everyone

  /// Recently shown messages, as they were before any deletion (the SDK
  /// empties a message in place when it is deleted).
  static final _shown = <String, Map<String, Object?>>{};
  static final _played = <String>{};

  static void remember(Event e) {
    if (e.redacted || _shown.containsKey(e.eventId)) return;
    if (!{EventTypes.Message, EventTypes.Sticker}.contains(e.type)) return;
    try {
      _shown[e.eventId] = e.toJson();
    } catch (_) {
      return;
    }
    if (_shown.length > 300) _shown.remove(_shown.keys.first);
  }

  /// The message as it was, while the samurai cuts it.
  static Event original(Event e) {
    final json = _shown[e.eventId];
    if (json == null || !e.redacted) return e;
    try {
      return Event.fromJson(json, e.room);
    } catch (_) {
      return e;
    }
  }

  /// A message on screen was just deleted by someone else: play the cut.
  static void maybePlayRemote(Event e) {
    if (!e.redacted || _played.contains(e.eventId)) return;
    if (!_shown.containsKey(e.eventId)) return;
    final by = e.redactedBecause;
    if (by == null || by.senderId == e.room.client.userID) return;
    if (DateTime.now().difference(by.originServerTs).inSeconds.abs() > 20) {
      return;
    }
    _played.add(e.eventId);
    final id = e.eventId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      active.value = {...active.value, id};
      Future<void>.delayed(
        duration + const Duration(milliseconds: 250),
        () => clear([id]),
      );
    });
  }
}

/// Wraps one message row; plays the samurai when its id is slashed.
class VibeSlashRow extends StatefulWidget {
  final String eventId;
  final Widget child;
  const VibeSlashRow({required this.eventId, required this.child, super.key});

  @override
  State<VibeSlashRow> createState() => _VibeSlashRowState();
}

class _VibeSlashRowState extends State<VibeSlashRow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: VibeSlash.duration,
  );
  bool _slashBuzz = false;
  bool _plantBuzz = false;

  @override
  void initState() {
    super.initState();
    VibeSlash.active.addListener(_check);
    _c.addListener(() {
      if (!_slashBuzz && _c.value >= _S.crouchEnd) {
        _slashBuzz = true;
        VibeHaptics.light();
      }
      if (!_plantBuzz && _c.value >= _S.plantHit) {
        _plantBuzz = true;
        VibeHaptics.heavy();
      }
    });
    _check();
  }

  void _check() {
    final on = VibeSlash.active.value.contains(widget.eventId);
    if (on && !_c.isAnimating && _c.value == 0) {
      _slashBuzz = _plantBuzz = false;
      _c.forward();
    } else if (!on && _c.value != 0) {
      _c.value = 0;
    }
  }

  @override
  void dispose() {
    VibeSlash.active.removeListener(_check);
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) {
        final t = _c.value;
        if (t == 0) return child!;
        final ink = Theme.of(context).colorScheme.onSurface;
        return LayoutBuilder(
          builder: (context, box) {
            final g = _Geo(Size(box.maxWidth, 0), t);
            // what he has run past is cut away; the rest goes after the plant
            final fadeAll = 1 - _seg(t, _S.dashEnd, _S.plantHit);
            // the row shudders when the sword hits the ground
            final sp = _seg(t, _S.plantHit, _S.plantHit + 0.08);
            final shake = sp > 0 && sp < 1
                ? math.sin(sp * math.pi * 6) * 3 * (1 - sp)
                : 0.0;
            return Transform.translate(
              offset: Offset(shake, 0),
              child: Stack(
              clipBehavior: Clip.none,
              children: [
                Opacity(
                  opacity: fadeAll.clamp(0.0, 1.0),
                  child: ShaderMask(
                    blendMode: BlendMode.dstIn,
                    shaderCallback: (r) {
                      final f = (g.manX / r.width).clamp(0.0, 1.0);
                      return LinearGradient(
                        colors: const [
                          Colors.white,
                          Colors.white,
                          Colors.transparent,
                          Colors.transparent,
                        ],
                        stops: [
                          0,
                          (f - 0.01).clamp(0.0, 1.0),
                          (f + 0.03).clamp(0.0, 1.0),
                          1,
                        ],
                      ).createShader(r);
                    },
                    child: child,
                  ),
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(painter: _SlashPainter(t, ink)),
                  ),
                ),
              ],
              ),
            );
          },
        );
      },
    );
  }
}

double _seg(double t, double a, double b) => ((t - a) / (b - a)).clamp(0.0, 1.0);

/// Timeline of the move (0..1).
abstract class _S {
  static const crouchEnd = 0.14; // appears at the end, crouches, draws
  static const dashEnd = 0.44; // dashes through the message to its start
  static const raiseEnd = 0.55; // raises the sword high, point up
  static const slamStart = 0.60; // a beat with the blade glinting...
  static const plantHit = 0.65; // ...then slams it into the ground
  static const goneAt = 0.90; // he has walked off
}

/// Blade direction pointing left (as held in the dash), straight up, and
/// leaning into the ground like the planted sword.
const _aDash = 3.02;
const _aUp = 4.71;
const _aDown = 1.35;

/// Where things are along the row.
class _Geo {
  final Size size;
  final double t;
  _Geo(this.size, this.t);

  /// The message starts after the avatar; it ends near the right side.
  double get startX => math.min(58.0, size.width * 0.18);
  double get endX => size.width * 0.86;

  /// The samurai's x (his feet).
  double get manX {
    if (t < _S.crouchEnd) return endX;
    final d = Curves.easeInOutCubic.transform(_seg(t, _S.crouchEnd, _S.dashEnd));
    return endX + (startX - endX) * d;
  }
}

const _red = Color(0xFFE53935);
const _straw = Color(0xFFCDAA6D);
const _steel = Color(0xFFD9DEE4);

class _SlashPainter extends CustomPainter {
  final double t;
  final Color ink;
  _SlashPainter(this.t, this.ink);

  @override
  void paint(Canvas canvas, Size size) {
    final g = _Geo(size, t);
    // small, and always fully inside the row (head included)
    final ground = size.height - 2;
    final sword = (size.height - 5).clamp(24.0, 58.0);
    final h = sword / 1.35;
    final plantX = g.startX - h * 0.15;
    final cutY = ground - h * 0.42;

    // ---- the cut line he leaves behind while dashing
    final lineFade = 1 - _seg(t, _S.dashEnd, _S.plantHit + 0.04);
    if (t > _S.crouchEnd && lineFade > 0) {
      final from = Offset(g.endX + h * 0.4, cutY);
      final to = Offset(g.manX - h * 0.5, cutY);
      canvas.drawLine(
        from,
        to,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.3 * lineFade)
          ..strokeWidth = 6
          ..strokeCap = StrokeCap.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      );
      canvas.drawLine(
        from,
        to,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.9 * lineFade)
          ..strokeWidth = 1.6
          ..strokeCap = StrokeCap.round,
      );
      // sparks flying off the blade
      final r = math.Random(3);
      final sp = Paint()..color = const Color(0xFFFFB74D).withValues(alpha: lineFade);
      for (var i = 0; i < 8; i++) {
        final x = g.manX - h * 0.5 + r.nextDouble() * h * 1.4;
        if (x > g.endX) continue;
        final up = r.nextDouble() * h * 0.5 * (1 - lineFade * 0.3);
        canvas.drawCircle(Offset(x, cutY - up), 1.3, sp);
      }
    }

    // ---- after the dash: raise the sword high, a glint, then slam it down
    final d = const Offset(0.2182, 0.9759); // planted lean (sin/cos 0.22)
    final handsEnd = Offset(plantX, ground + 3) - d * (0.87 * sword);
    final handsUp = Offset(plantX + h * 0.12, ground - h * 1.05);
    final handsDash = Offset(g.startX - h * 0.38, ground - h * 0.45);
    Offset? hold; // where his hands are (world), while not dashing/walking
    if (t >= _S.dashEnd && t < _S.plantHit) {
      double angleAt(double tt) {
        if (tt < _S.raiseEnd) {
          final u = Curves.easeOutBack.transform(_seg(tt, _S.dashEnd, _S.raiseEnd));
          return _aDash + (_aUp - _aDash) * u;
        }
        if (tt < _S.slamStart) return _aUp;
        final u = Curves.easeInCubic.transform(_seg(tt, _S.slamStart, _S.plantHit));
        return _aUp + (_aDown - _aUp) * u;
      }

      Offset handsAt(double tt) {
        if (tt < _S.raiseEnd) {
          final u = Curves.easeOutCubic.transform(_seg(tt, _S.dashEnd, _S.raiseEnd));
          return Offset.lerp(handsDash, handsUp, u)!;
        }
        if (tt < _S.slamStart) {
          // a tiny tremble while he holds it up
          return handsUp + Offset(0, math.sin(tt * 900) * 0.6);
        }
        final u = Curves.easeInCubic.transform(_seg(tt, _S.slamStart, _S.plantHit));
        return Offset.lerp(handsUp, handsEnd, u)!;
      }

      hold = handsAt(t);
      final a = angleAt(t);
      final dir = Offset(math.cos(a), math.sin(a));
      // motion trails while slamming
      if (t > _S.slamStart) {
        for (var k = 3; k >= 1; k--) {
          final tt = t - k * 0.008;
          if (tt < _S.slamStart) continue;
          final ak = angleAt(tt);
          final hk = handsAt(tt);
          final dk = Offset(math.cos(ak), math.sin(ak));
          canvas.drawLine(
            hk + dk * (0.21 * sword),
            hk + dk * (0.87 * sword),
            Paint()
              ..color = Colors.white.withValues(alpha: 0.22 / k)
              ..strokeWidth = math.max(2.0, h * 0.09)
              ..strokeCap = StrokeCap.round,
          );
        }
      }
      _heldSword(canvas, hold, dir, sword, h);
      // the glint on the tip, held high
      final q = _seg(t, _S.raiseEnd - 0.03, _S.slamStart + 0.01);
      final glow = math.sin(math.pi * q);
      if (glow > 0) {
        final tip = hold + dir * (0.87 * sword);
        final r = h * 0.38 * glow;
        final star = Paint()
          ..color = Colors.white.withValues(alpha: glow)
          ..strokeWidth = 1.4
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(tip - Offset(r, 0), tip + Offset(r, 0), star);
        canvas.drawLine(tip - Offset(0, r), tip + Offset(0, r), star);
        canvas.drawCircle(
          tip,
          r * 0.35,
          Paint()
            ..color = Colors.white.withValues(alpha: 0.6 * glow)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
        );
      }
    }

    // ---- planted: the blade wobbles, dust and a shockwave fly out
    if (t >= _S.plantHit) {
      final w = _seg(t, _S.plantHit, _S.plantHit + 0.12);
      canvas.save();
      canvas.translate(plantX, ground);
      if (w < 1) canvas.rotate(0.09 * math.sin(w * math.pi * 5) * (1 - w));
      paintPlantedSword(canvas, sword, ink, grass: _seg(t, _S.goneAt - 0.08, 1.0));
      canvas.restore();
      if (t < _S.plantHit + 0.08) hold = handsEnd; // lets go, walks off

      if (w < 1) {
        final base = Offset(plantX, ground);
        canvas.drawCircle(
          base,
          h * (0.3 + 0.9 * w),
          Paint()
            ..color = Colors.white.withValues(alpha: 0.45 * (1 - w))
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
        );
        canvas.drawOval(
          Rect.fromCenter(
            center: base,
            width: h * (0.4 + 2.4 * w),
            height: h * (0.12 + 0.35 * w),
          ),
          Paint()
            ..color = Colors.white.withValues(alpha: 0.8 * (1 - w))
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.4,
        );
        final r = math.Random(11);
        final dust = Paint()..color = ink.withValues(alpha: 0.55 * (1 - w));
        for (var i = 0; i < 12; i++) {
          final ang = math.pi + r.nextDouble() * math.pi; // upward half
          final v = Offset(math.cos(ang), math.sin(ang)) * (0.6 + r.nextDouble());
          final pos = base + v * (w * h * 1.2) + Offset(0, w * w * h * 0.8);
          canvas.drawCircle(pos, 1.7 * (1 - w) + 0.5, dust);
        }
      }
    }

    // ---- the samurai (with a trail of afterimages while dashing)
    final gone = _seg(t, _S.plantHit + 0.08, _S.goneAt);
    if (gone < 1) {
      double x = g.manX;
      if (t >= _S.dashEnd) {
        final step = Curves.easeOutCubic.transform(_seg(t, _S.dashEnd, _S.raiseEnd));
        x = g.startX + (plantX + h * 0.5 - g.startX) * step - gone * h * 1.2;
      }
      final appear = _seg(t, 0, 0.06);
      final dashP = _seg(t, _S.crouchEnd, _S.dashEnd);
      if (dashP > 0.08 && dashP < 0.95) {
        for (var k = 3; k >= 1; k--) {
          canvas.save();
          canvas.translate(x + k * h * 0.45, ground);
          _samurai(canvas, h, sword, 0.2 / k, null);
          canvas.restore();
        }
      }
      canvas.save();
      canvas.translate(x, ground);
      _samurai(
        canvas,
        h,
        sword,
        (appear * (1 - gone)).clamp(0.0, 1.0),
        hold == null ? null : hold - Offset(x, ground),
      );
      canvas.restore();
    }
  }

  /// The katana in his hands, in the planted sword's proportions.
  static void _heldSword(Canvas canvas, Offset hands, Offset dir, double sword, double h) {
    final back = hands - dir * (0.13 * sword);
    final guard = hands + dir * (0.21 * sword);
    final tip = hands + dir * (0.87 * sword);
    canvas.drawLine(
      back,
      guard,
      Paint()
        ..color = const Color(0xFFF2F2F2)
        ..strokeWidth = math.max(3.0, sword * 0.085)
        ..strokeCap = StrokeCap.round,
    );
    final n = Offset(-dir.dy, dir.dx) * (sword * 0.035);
    final wrap = Paint()
      ..color = const Color(0xFF1E1E1E)
      ..strokeWidth = 1.1;
    for (var i = 0; i < 4; i++) {
      final c = Offset.lerp(back, guard, (i + 0.5) / 4)!;
      canvas.drawLine(c - n, c + n, wrap);
    }
    canvas.drawCircle(
      guard,
      math.max(2.4, sword * 0.06),
      Paint()..color = const Color(0xFF2B2B2B),
    );
    canvas.drawLine(
      guard,
      tip,
      Paint()
        ..color = _steel
        ..strokeWidth = math.max(1.8, sword * 0.05)
        ..strokeCap = StrokeCap.round,
    );
  }

  /// Stick figure, feet at (0,0), facing left. [hold] = where his hands are
  /// (relative to his feet) while he raises / drives the sword.
  void _samurai(Canvas canvas, double h, double sword, double o, Offset? hold) {
    final stroke = Paint()
      ..color = ink.withValues(alpha: o)
      ..strokeWidth = math.max(2.6, h * 0.12)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final headR = h * 0.13;

    final crouch = t < _S.crouchEnd
        ? Curves.easeOut.transform(_seg(t, 0.04, _S.crouchEnd))
        : t < _S.dashEnd
        ? 1.0
        : 1 - _seg(t, _S.dashEnd, _S.dashEnd + 0.06);
    final walking = t >= _S.plantHit + 0.08;

    // body: lower hips and a forward lean when crouched / dashing
    final hip = Offset(h * 0.04 * crouch, -h * (0.42 - 0.12 * crouch));
    final neck = hip + Offset(-h * (0.04 + 0.2 * crouch), -h * (0.3 - 0.06 * crouch));
    final head = neck + Offset(-headR * 0.25 * (1 + crouch), -headR * 1.15);

    // legs: wide lunge when dashing, a little stride when walking off
    Offset lf, rf;
    if (walking) {
      final s = math.sin(t * 70) * h * 0.14;
      lf = Offset(-s, 0);
      rf = Offset(s, 0);
    } else {
      lf = Offset(-h * (0.1 + 0.2 * crouch), 0);
      rf = Offset(h * (0.1 + 0.2 * crouch), 0);
    }
    final knee = Offset.lerp(hip, lf, 0.5)! + Offset(-h * 0.06 * crouch, -h * 0.04 * crouch);
    canvas.drawPath(
      Path()
        ..moveTo(hip.dx, hip.dy)
        ..lineTo(knee.dx, knee.dy)
        ..lineTo(lf.dx, lf.dy),
      stroke,
    );
    canvas.drawLine(hip, rf, stroke);
    canvas.drawLine(hip, neck, stroke);

    // head (filled) + red headband with tails flying back
    canvas.drawCircle(head, headR, Paint()..color = ink.withValues(alpha: o));
    final band = Paint()
      ..color = _red.withValues(alpha: o)
      ..strokeWidth = math.max(1.8, h * 0.06)
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
      head + Offset(-headR, -headR * 0.1),
      head + Offset(headR, -headR * 0.1),
      band,
    );
    final wave = math.sin(t * 45) * headR * 0.5;
    final trail = 1 + crouch; // longer tails when dashing
    canvas.drawPath(
      Path()
        ..moveTo(head.dx + headR, head.dy - headR * 0.1)
        ..quadraticBezierTo(
          head.dx + headR * 2 * trail,
          head.dy - headR * 0.5 + wave,
          head.dx + headR * 3 * trail,
          head.dy + headR * 0.2 + wave,
        ),
      band,
    );

    // straw hat (kasa)
    final hat = Path()
      ..moveTo(head.dx - headR * 1.9, head.dy - headR * 0.5)
      ..lineTo(head.dx, head.dy - headR * 1.6)
      ..lineTo(head.dx + headR * 1.9, head.dy - headR * 0.5)
      ..close();
    canvas.drawPath(hat, Paint()..color = _straw.withValues(alpha: o));
    canvas.drawPath(
      hat,
      Paint()
        ..color = ink.withValues(alpha: 0.7 * o)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );

    // arms + sword
    final shoulder = Offset.lerp(neck, hip, 0.15)!;
    if (t < _S.dashEnd && hold == null) {
      // drawn back while crouching, then held level and forward in the dash
      final level = _seg(t, _S.crouchEnd - 0.05, _S.crouchEnd + 0.04);
      final angle = -2.5 + (2.5 + 0.12) * Curves.easeOut.transform(level);
      final dir = Offset(-math.cos(angle), math.sin(angle));
      final hands = shoulder + dir * h * 0.3;
      canvas.drawLine(shoulder, hands, stroke);
      _katana(canvas, hands, dir, h, sword * 0.75, o);
    } else if (hold != null) {
      // both hands on the hilt
      canvas.drawLine(shoulder, hold, stroke);
      canvas.drawLine(shoulder + Offset(0, h * 0.04), hold, stroke);
    } else {
      // walking off, arms swinging
      final s = math.sin(t * 70) * h * 0.12;
      canvas.drawLine(shoulder, shoulder + Offset(s, h * 0.22), stroke);
    }
  }

  static void _katana(Canvas canvas, Offset hands, Offset dir, double h, double len, double o) {
    final back = hands - dir * h * 0.14;
    final guard = hands + dir * h * 0.12;
    canvas.drawLine(
      back,
      guard,
      Paint()
        ..color = const Color(0xFFF2F2F2).withValues(alpha: o)
        ..strokeWidth = math.max(3.0, h * 0.12)
        ..strokeCap = StrokeCap.round,
    );
    final n = Offset(-dir.dy, dir.dx) * h * 0.05;
    final wrap = Paint()
      ..color = const Color(0xFF1E1E1E).withValues(alpha: o)
      ..strokeWidth = 1.2;
    for (var i = 0; i < 3; i++) {
      final c = Offset.lerp(back, guard, (i + 0.5) / 3)!;
      canvas.drawLine(c - n, c + n, wrap);
    }
    canvas.drawCircle(
      guard,
      math.max(2.4, h * 0.07),
      Paint()..color = const Color(0xFF2B2B2B).withValues(alpha: o),
    );
    canvas.drawLine(
      guard,
      guard + dir * len,
      Paint()
        ..color = _steel.withValues(alpha: o)
        ..strokeWidth = math.max(2.0, h * 0.07)
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_SlashPainter old) => old.t != t || old.ink != ink;
}

/// The katana stuck in the grass. (0,0) = where the blade meets the ground.
void paintPlantedSword(
  Canvas canvas,
  double h,
  Color ink, {
  double opacity = 1,
  double grass = 1,
}) {
  final o = opacity.clamp(0.0, 1.0);
  // slightly leaning, like the reference picture
  canvas.save();
  canvas.rotate(-0.22);
  final blade = Paint()
    ..color = _steel.withValues(alpha: o)
    ..strokeWidth = math.max(1.6, h * 0.05)
    ..strokeCap = StrokeCap.butt;
  canvas.drawLine(const Offset(0, 4), Offset(0, -h * 0.62), blade);
  canvas.drawLine(
    Offset(h * 0.012, 2),
    Offset(h * 0.012, -h * 0.6),
    Paint()
      ..color = Colors.white.withValues(alpha: 0.7 * o)
      ..strokeWidth = 0.8,
  );
  final guardY = -h * 0.64;
  canvas.drawOval(
    Rect.fromCenter(center: Offset(0, guardY), width: h * 0.17, height: h * 0.05),
    Paint()..color = const Color(0xFF2B2B2B).withValues(alpha: o),
  );
  final top = -h * 0.98;
  canvas.drawLine(
    Offset(0, guardY - 1),
    Offset(0, top),
    Paint()
      ..color = const Color(0xFFF2F2F2).withValues(alpha: o)
      ..strokeWidth = math.max(2.6, h * 0.085)
      ..strokeCap = StrokeCap.round,
  );
  final wrap = Paint()
    ..color = const Color(0xFF1E1E1E).withValues(alpha: o)
    ..strokeWidth = 1.1;
  for (var i = 0; i < 4; i++) {
    final y = guardY - 3 + (top - guardY + 3) * (i + 0.5) / 4;
    canvas.drawLine(Offset(-h * 0.035, y - 2), Offset(h * 0.035, y + 2), wrap);
  }
  // a red cord tied below the guard, blowing in the wind
  final cord = Paint()
    ..color = _red.withValues(alpha: o)
    ..strokeWidth = math.max(1.4, h * 0.03)
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;
  canvas.drawPath(
    Path()
      ..moveTo(0, guardY - h * 0.06)
      ..quadraticBezierTo(h * 0.16, guardY - h * 0.02, h * 0.24, guardY + h * 0.1),
    cord,
  );
  canvas.restore();

  // silver pampas grass around the blade
  if (grass <= 0) return;
  final g = Paint()
    ..color = Color.lerp(ink, const Color(0xFFBFB7A6), 0.55)!
        .withValues(alpha: 0.85 * o * grass)
    ..strokeWidth = 1.3
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;
  const blades = [-0.5, -0.32, -0.16, 0.12, 0.26, 0.42, 0.56];
  for (var i = 0; i < blades.length; i++) {
    final bx = blades[i] * h;
    final len = h * (0.18 + 0.1 * ((i * 37) % 5) / 4) * grass;
    final lean = (i.isEven ? -1 : 1) * h * 0.08;
    final path = Path()
      ..moveTo(bx, 2)
      ..quadraticBezierTo(bx + lean * 0.3, -len * 0.6, bx + lean, -len);
    canvas.drawPath(path, g);
  }
  canvas.drawLine(
    Offset(-h * 0.6, 2),
    Offset(h * 0.65, 2),
    g..strokeWidth = 1,
  );
}

/// Shown where a deleted message was: the planted sword and "deleted".
class VibeSwordField extends StatelessWidget {
  final Color color;
  final double fontSize;
  final String label;
  final VoidCallback? onTap;
  const VibeSwordField({
    required this.color,
    required this.label,
    this.fontSize = 14,
    this.onTap,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final ink = Theme.of(context).colorScheme.onSurface;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 44,
              height: 38,
              child: CustomPaint(painter: _FieldPainter(ink)),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: fontSize * 0.9,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FieldPainter extends CustomPainter {
  final Color ink;
  _FieldPainter(this.ink);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(size.width * 0.5, size.height - 3);
    paintPlantedSword(canvas, size.height * 0.95, ink);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_FieldPainter old) => old.ink != ink;
}
