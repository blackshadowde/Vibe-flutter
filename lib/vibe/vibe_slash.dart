// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:math' as math;

import 'package:fluffychat/vibe/vibe_haptics.dart';
import 'package:flutter/material.dart';

/// Deleting a message: a little samurai (straw hat, red headband, katana)
/// dashes into that message's row, draws, leaps and slashes it in two, and
/// leaves his sword planted in the grass where the message was.
///
/// It all happens inside the message's own row (he grows a bit for the
/// slash), takes about a second, and is skipped when the phone asks for
/// reduced motion.
abstract class VibeSlash {
  static final active = ValueNotifier<Set<String>>({});
  static const duration = Duration(milliseconds: 1250);

  /// Plays the slash on [eventIds] and completes when the cut is done.
  static Future<void> play(BuildContext context, Iterable<String> eventIds) async {
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return;
    final ids = eventIds.toSet();
    if (ids.isEmpty) return;
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
  bool _buzzed = false;

  @override
  void initState() {
    super.initState();
    VibeSlash.active.addListener(_check);
    _c.addListener(() {
      if (!_buzzed && _c.value >= _S.cut) {
        _buzzed = true;
        VibeHaptics.heavy();
      }
    });
    _check();
  }

  void _check() {
    final on = VibeSlash.active.value.contains(widget.eventId);
    if (on && !_c.isAnimating && _c.value == 0) {
      _buzzed = false;
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
        // after the cut the message drops a little, tilts and fades away
        final after = ((t - _S.cut) / 0.22).clamp(0.0, 1.0);
        final fall = Curves.easeIn.transform(after);
        final ink = Theme.of(context).colorScheme.onSurface;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Opacity(
              opacity: 1 - fall,
              child: Transform.translate(
                offset: Offset(4 * fall, 8 * fall),
                child: Transform.rotate(angle: 0.035 * fall, child: child),
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
  }
}

/// Timeline of the move (0..1).
abstract class _S {
  static const dashEnd = 0.24; // runs in from the right
  static const drawEnd = 0.42; // draws the sword overhead
  static const cut = 0.52; // the slash lands
  static const exitStart = 0.72; // vanishes, sword stays planted
}

const _red = Color(0xFFE53935);
const _straw = Color(0xFFCDAA6D);
const _steel = Color(0xFFD9DEE4);

class _SlashPainter extends CustomPainter {
  final double t;
  final Color ink;
  _SlashPainter(this.t, this.ink);

  double _seg(double a, double b) => ((t - a) / (b - a)).clamp(0.0, 1.0);

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height.clamp(34.0, 64.0);
    final ground = size.height - 4;
    final standX = size.width * 0.66;

    // ---- the slash streak across the message
    final streak = _seg(_S.drawEnd + 0.04, _S.cut + 0.06);
    final fade = 1 - _seg(_S.cut + 0.06, _S.exitStart);
    if (streak > 0 && fade > 0) {
      final a = Offset(standX - 6, size.height * 0.05);
      final b = Offset(size.width * 0.08, size.height * 0.95);
      final end = Offset.lerp(a, b, Curves.easeOutCubic.transform(streak))!;
      final glow = Paint()
        ..color = Colors.white.withValues(alpha: 0.35 * fade)
        ..strokeWidth = 7
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
      final line = Paint()
        ..color = Colors.white.withValues(alpha: 0.95 * fade)
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(a, end, glow);
      canvas.drawLine(a, end, line);
      // sparks where the blade cut
      if (t > _S.cut) {
        final sp = _seg(_S.cut, _S.exitStart);
        final r = math.Random(7);
        final p = Paint()..color = const Color(0xFFFFB74D).withValues(alpha: fade);
        for (var i = 0; i < 9; i++) {
          final base = Offset.lerp(a, b, r.nextDouble())!;
          final dir = Offset(r.nextDouble() * 2 - 1, -r.nextDouble());
          canvas.drawCircle(base + dir * 22 * sp, 1.4 * (1 - sp) + 0.4, p);
        }
      }
    }

    // ---- the samurai
    if (t < _S.exitStart + 0.06) {
      final dash = Curves.easeOutCubic.transform(_seg(0, _S.dashEnd));
      final x = size.width + h - (size.width + h - standX) * dash;
      // leap and grow for the slash, settle back after
      final leap = math.sin(math.pi * _seg(_S.drawEnd - 0.04, _S.cut + 0.08));
      final scale = 1 + 0.4 * leap;
      final vanish = 1 - _seg(_S.exitStart - 0.02, _S.exitStart + 0.06);
      canvas.save();
      canvas.translate(x, ground - leap * h * 0.25);
      canvas.scale(scale);
      _samurai(canvas, h, vanish);
      canvas.restore();
    }

    // ---- the sword left in the ground
    final plant = _seg(_S.exitStart - 0.04, 0.9);
    if (plant > 0) {
      final drop = Curves.easeOutBack.transform(plant);
      canvas.save();
      canvas.translate(size.width * 0.12 + h * 0.4, ground);
      final sh = h * 0.95;
      // falls in from above and sticks
      canvas.translate(0, -(1 - drop) * h * 0.8);
      paintPlantedSword(
        canvas,
        sh,
        ink,
        opacity: plant.clamp(0.0, 1.0),
        grass: _seg(0.82, 1.0),
      );
      canvas.restore();
    }
  }

  /// Stick figure standing at (0,0) = feet, facing left.
  void _samurai(Canvas canvas, double h, double alpha) {
    final o = alpha.clamp(0.0, 1.0);
    final stroke = Paint()
      ..color = ink.withValues(alpha: o)
      ..strokeWidth = math.max(2.0, h * 0.055)
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final headR = h * 0.1;
    final hip = Offset(0, -h * 0.42);
    final neck = Offset(-h * 0.02, -h * 0.72);
    final head = Offset(-h * 0.04, -h * 0.72 - headR * 1.05);

    // running legs while dashing, wide stance when cutting
    final run = t < _S.dashEnd;
    final phase = math.sin(t * 60);
    final lFoot = run
        ? Offset(-h * 0.16 * phase, 0)
        : Offset(-h * 0.2, 0);
    final rFoot = run
        ? Offset(h * 0.16 * phase, 0)
        : Offset(h * 0.18, 0);
    canvas.drawLine(hip, lFoot, stroke);
    canvas.drawLine(hip, rFoot, stroke);
    canvas.drawLine(hip, neck, stroke);
    canvas.drawCircle(head, headR, stroke..style = PaintingStyle.fill);
    stroke.style = PaintingStyle.stroke;

    // red headband with tails flying behind
    final band = Paint()
      ..color = _red.withValues(alpha: o)
      ..strokeWidth = math.max(1.6, h * 0.035)
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
      head + Offset(-headR, -headR * 0.15),
      head + Offset(headR, -headR * 0.15),
      band,
    );
    final wave = math.sin(t * 40) * headR * 0.5;
    final tail = Path()
      ..moveTo(head.dx + headR, head.dy - headR * 0.15)
      ..quadraticBezierTo(
        head.dx + headR * 2.2,
        head.dy - headR * 0.6 + wave,
        head.dx + headR * 3.4,
        head.dy + wave,
      );
    canvas.drawPath(tail, band);

    // straw hat (kasa)
    final hat = Path()
      ..moveTo(head.dx - headR * 2.0, head.dy - headR * 0.45)
      ..lineTo(head.dx, head.dy - headR * 1.75)
      ..lineTo(head.dx + headR * 2.0, head.dy - headR * 0.45)
      ..close();
    canvas.drawPath(hat, Paint()..color = _straw.withValues(alpha: o));
    canvas.drawPath(
      hat,
      Paint()
        ..color = ink.withValues(alpha: 0.6 * o)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    // arms + katana: sheathed while running, raised overhead, then the cut
    final shoulder = neck + Offset(0, h * 0.05);
    double angle; // blade direction, 0 = pointing left
    if (t < _S.dashEnd) {
      angle = -2.6; // held low, behind
    } else if (t < _S.drawEnd) {
      angle = _lerp(-2.6, -4.4, Curves.easeOut.transform(_seg(_S.dashEnd, _S.drawEnd)));
    } else if (t < _S.cut) {
      angle = _lerp(-4.4, -5.9, Curves.easeInCubic.transform(_seg(_S.drawEnd, _S.cut)));
    } else {
      angle = -5.9;
    }
    final dir = Offset(-math.cos(angle), math.sin(angle));
    final hands = shoulder + dir * h * 0.26;
    canvas.drawLine(shoulder, hands, stroke);
    canvas.drawLine(shoulder + Offset(0, h * 0.02), hands, stroke);
    _katana(canvas, hands, dir, h, o);
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;

  static void _katana(Canvas canvas, Offset hands, Offset dir, double h, double o) {
    final grip = Paint()
      ..color = const Color(0xFFF2F2F2).withValues(alpha: o)
      ..strokeWidth = math.max(2.6, h * 0.07)
      ..strokeCap = StrokeCap.round;
    final wrap = Paint()
      ..color = const Color(0xFF1E1E1E).withValues(alpha: o)
      ..strokeWidth = 1.2;
    final back = hands - dir * h * 0.08;
    final guard = hands + dir * h * 0.08;
    canvas.drawLine(back, guard, grip);
    // diamond wrap on the handle, like the reference
    final n = Offset(-dir.dy, dir.dx) * h * 0.035;
    for (var i = 0; i < 3; i++) {
      final c = Offset.lerp(back, guard, (i + 0.5) / 3)!;
      canvas.drawLine(c - n, c + n, wrap);
    }
    canvas.drawCircle(guard, math.max(2.2, h * 0.045), Paint()..color = const Color(0xFF2B2B2B).withValues(alpha: o));
    final blade = Paint()
      ..color = _steel.withValues(alpha: o)
      ..strokeWidth = math.max(1.6, h * 0.04)
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(guard, guard + dir * h * 0.62, blade);
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
