// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:math' as math;

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/vibe/vibe_palette.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// The Parrot look's "network": faint dots slowly drifting across the whole
/// app, linked by thin lines when they come close (hacker aesthetic).
///
/// One layer above everything, never touchable, so screens, sheets and
/// dialogs slide under it like under glass and it never jumps between
/// pages. Kept faint (it reads as texture on dark backgrounds and vanishes
/// over text), redrawn ~30 times a second in its own layer, frozen when the
/// phone asks for reduced motion. Where you touch, nearby dots link to your
/// finger for a moment.
abstract class VibePlexus {
  static final lines = ValueNotifier<bool>(AppSettings.vibeParrotLines.value);

  static Future<void> setLines(bool on) async {
    lines.value = on;
    await AppSettings.vibeParrotLines.setItem(on);
  }
}

class VibePlexusLayer extends StatefulWidget {
  final Widget child;
  const VibePlexusLayer({required this.child, super.key});

  @override
  State<VibePlexusLayer> createState() => _VibePlexusLayerState();
}

class _VibePlexusLayerState extends State<VibePlexusLayer>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  final _time = ValueNotifier<double>(0);
  final _touch = ValueNotifier<_Touch?>(null);
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    VibePlexus.lines.addListener(_changed);
  }

  void _changed() => setState(() {});

  void _tick(Duration elapsed) {
    // ~30 fps is plenty for something this slow
    if (elapsed - _last < const Duration(milliseconds: 33)) return;
    _last = elapsed;
    _time.value = elapsed.inMicroseconds / 1e6;
  }

  @override
  void dispose() {
    VibePlexus.lines.removeListener(_changed);
    _ticker.dispose();
    _time.dispose();
    _touch.dispose();
    super.dispose();
  }

  void _onPointer(PointerEvent e) {
    _touch.value = _Touch(e.position, _time.value);
  }

  @override
  Widget build(BuildContext context) {
    final on = VibePalette.effective == VibeLook.parrot && VibePlexus.lines.value;
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final run = on && !still;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (run && !_ticker.isActive) {
        _last = Duration.zero;
        _ticker.start();
      } else if (!run && _ticker.isActive) {
        _ticker.stop();
      }
    });
    if (!on) return widget.child;
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onPointer,
      onPointerMove: _onPointer,
      child: Stack(
        children: [
          widget.child,
          Positioned.fill(
            child: IgnorePointer(
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: _PlexusPainter(
                    time: _time,
                    touch: _touch,
                    line: cs.primary,
                    spark: cs.tertiary,
                    strength: dark ? 1.0 : 1.25,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Touch {
  final Offset at;
  final double time;
  const _Touch(this.at, this.time);
}

class _PlexusPainter extends CustomPainter {
  final ValueNotifier<double> time;
  final ValueNotifier<_Touch?> touch;
  final Color line;
  final Color spark;
  final double strength;

  _PlexusPainter({
    required this.time,
    required this.touch,
    required this.line,
    required this.spark,
    required this.strength,
  }) : super(repaint: Listenable.merge([time, touch]));

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final t = time.value;
    final w = size.width, h = size.height;
    final n = (w * h / 16000).clamp(24, 70).round();
    final reach = (math.min(w, h) * 0.24).clamp(90.0, 150.0);
    const margin = 40.0;
    final r = math.Random(42);

    // the same dots every frame: positions are a function of time
    final pts = List<Offset>.generate(n, (i) {
      final bx = r.nextDouble(), by = r.nextDouble();
      final sp = 4 + r.nextDouble() * 8; // px per second
      final ang = r.nextDouble() * math.pi * 2;
      final x = (bx * (w + 2 * margin) + math.cos(ang) * sp * t) % (w + 2 * margin) - margin;
      final y = (by * (h + 2 * margin) + math.sin(ang) * sp * t) % (h + 2 * margin) - margin;
      return Offset(x, y);
    });

    final paint = Paint()
      ..strokeWidth = 0.7
      ..isAntiAlias = true;
    for (var i = 0; i < n; i++) {
      for (var j = i + 1; j < n; j++) {
        final d = (pts[i] - pts[j]).distance;
        if (d >= reach) continue;
        paint.color = line.withValues(alpha: (1 - d / reach) * 0.11 * strength);
        canvas.drawLine(pts[i], pts[j], paint);
      }
    }

    // a finger nearby: links light up to it, fading out after letting go
    final tc = touch.value;
    if (tc != null) {
      final age = t - tc.time;
      final fade = (1 - age / 0.8).clamp(0.0, 1.0);
      if (fade > 0) {
        const rr = 140.0;
        for (final p in pts) {
          final d = (p - tc.at).distance;
          if (d >= rr) continue;
          paint.color = line.withValues(alpha: (1 - d / rr) * 0.35 * fade);
          canvas.drawLine(p, tc.at, paint);
        }
      }
    }

    final dot = Paint();
    for (var i = 0; i < n; i++) {
      final lime = i % 9 == 0;
      final tw = lime ? 0.5 + 0.5 * math.sin(t * 1.6 + i) : 1.0;
      dot.color = (lime ? spark : line)
          .withValues(alpha: (lime ? 0.45 * tw : 0.28) * strength);
      canvas.drawCircle(pts[i], lime ? 1.7 : 1.2, dot);
    }
  }

  @override
  bool shouldRepaint(_PlexusPainter old) =>
      old.line != line || old.spark != spark || old.strength != strength;
}
