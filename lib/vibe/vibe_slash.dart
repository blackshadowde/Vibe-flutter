// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:math' as math;

import 'package:fluffychat/vibe/vibe_haptics.dart';
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
  static const duration = Duration(milliseconds: 1500);

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
            return Stack(
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
  static const crouchEnd = 0.16; // appears at the end, crouches, draws
  static const dashEnd = 0.52; // dashes through the message to its start
  static const plantHit = 0.64; // sword driven into the ground
  static const goneAt = 0.86; // he has walked off
}

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

    // ---- the sword: in his hands, then driven into the ground
    if (t >= _S.dashEnd) {
      final drive = Curves.easeInCubic.transform(_seg(t, _S.dashEnd + 0.04, _S.plantHit));
      final lift = math.sin(math.pi * _seg(t, _S.dashEnd, _S.dashEnd + 0.08)) * h * 0.25;
      final sink = (1 - drive) * h * 0.55 + lift;
      canvas.save();
      canvas.translate(plantX, ground - sink);
      paintPlantedSword(canvas, sword, ink, grass: _seg(t, _S.goneAt - 0.06, 1.0));
      canvas.restore();
    }

    // ---- the samurai
    final gone = _seg(t, _S.plantHit + 0.06, _S.goneAt);
    if (gone < 1) {
      double x = g.manX;
      if (t >= _S.dashEnd) {
        // stands beside his sword, then walks off to the left
        x = plantX + h * 0.32 - gone * h * 1.1;
      }
      final appear = _seg(t, 0, 0.06);
      canvas.save();
      canvas.translate(x, ground);
      _samurai(canvas, h, sword, (appear * (1 - gone)).clamp(0.0, 1.0), plantX - x);
      canvas.restore();
    }
  }

  /// Stick figure, feet at (0,0), facing left. [swordDx] = where the planted
  /// sword is, relative to him (for the drive-down pose).
  void _samurai(Canvas canvas, double h, double sword, double o, double swordDx) {
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
    final walking = t >= _S.plantHit + 0.06;

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
    if (t < _S.dashEnd) {
      // drawn back while crouching, then held level and forward in the dash
      final level = _seg(t, _S.crouchEnd - 0.05, _S.crouchEnd + 0.04);
      final angle = -2.5 + (2.5 + 0.12) * Curves.easeOut.transform(level);
      final dir = Offset(-math.cos(angle), math.sin(angle));
      final hands = shoulder + dir * h * 0.3;
      canvas.drawLine(shoulder, hands, stroke);
      _katana(canvas, hands, dir, h, sword * 0.75, o);
    } else if (!walking) {
      // both hands on the hilt of the sword going into the ground
      final drive = Curves.easeInCubic.transform(_seg(t, _S.dashEnd + 0.04, _S.plantHit));
      final lift = math.sin(math.pi * _seg(t, _S.dashEnd, _S.dashEnd + 0.08)) * h * 0.25;
      final sink = (1 - drive) * h * 0.55 + lift;
      // the hilt of the leaning planted sword (see paintPlantedSword)
      final hilt = Offset(
        swordDx - sword * 0.85 * math.sin(0.22),
        -sink - sword * 0.85 * math.cos(0.22),
      );
      canvas.drawLine(shoulder, hilt, stroke);
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
