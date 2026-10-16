// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Opening the app: the blue 💬 sits still and its three dots hop once,
/// like someone typing, then it fades away. The app loads underneath the
/// whole time, so it never makes you wait.
class VibeLaunch extends StatefulWidget {
  final Widget child;
  const VibeLaunch({required this.child, super.key});


  @override
  State<VibeLaunch> createState() => _VibeLaunchState();
}

/// The opening's clock is kept here, outside the widget, so the widget being
/// rebuilt or remounted while the app starts can't cut it short or skip it.
abstract class _Launch {
  static const ms = 1150;
  static DateTime? start; // when the hop began (null = not yet)
  static bool over = false;
  static bool scheduled = false;

  static double get t {
    final s = start;
    if (s == null) return 0;
    return (DateTime.now().difference(s).inMilliseconds / ms).clamp(0.0, 1.0);
  }

  /// Starts the hop once the heavy first frames are drawn, so it isn't
  /// played while frames are dropped (you'd only see a still icon).
  static void schedule() {
    if (scheduled || over) return;
    scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      for (var i = 0; i < 3; i++) {
        await WidgetsBinding.instance.endOfFrame;
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
      start = DateTime.now();
    });
  }

  static void replay() {
    start = null;
    over = false;
    scheduled = false;
    schedule();
  }
}

class _VibeLaunchState extends State<VibeLaunch>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final Ticker _ticker = createTicker(_tick);
  bool _closed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (!_Launch.over) {
      _Launch.schedule();
      _ticker.start();
    }
  }

  void _tick(Duration _) {
    if (!mounted) return;
    if (_Launch.t >= 1) {
      _Launch.over = true;
      _ticker.stop();
    }
    setState(() {});
  }

  // Vibe keeps running in the background after you leave it (the engine
  // stays), so opening it again only showed Android's still splash: play
  // the opening again whenever the app's screen was closed and reopened.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      _closed = true;
    } else if (state == AppLifecycleState.resumed && _closed) {
      _closed = false;
      if (!mounted) return;
      _Launch.replay();
      if (!_ticker.isActive) _ticker.start();
      setState(() {});
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bg = Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF1A191E)
        : Colors.white;
    final t = _Launch.t;
    final out = ((t - 0.72) / 0.28).clamp(0.0, 1.0);
    // The same Stack the whole time: the app underneath is never rebuilt
    // from scratch when the opening ends.
    return Stack(
      children: [
        widget.child,
        if (!_Launch.over)
          Positioned.fill(
            child: IgnorePointer(
              child: Opacity(
                opacity: 1 - out,
                child: ColoredBox(
                  color: bg,
                  child: Center(
                    child: Transform.scale(
                      scale: 1 + 0.12 * out,
                      child: SizedBox.square(
                        dimension: 150,
                        child: CustomPaint(painter: _BubblePainter(t)),
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

class _BubblePainter extends CustomPainter {
  final double t;
  _BubblePainter(this.t);

  // one hop per dot, each a beat after the one before (in the first 70%)
  double _hop(int i) {
    final u = ((t - i * 0.085) / 0.5).clamp(0.0, 1.0);
    if (u <= 0 || u >= 1) return 0;
    return u < 0.35 ? Curves.easeOut.transform(u / 0.35) : math.max(0, 1 - Curves.bounceOut.transform((u - 0.35) / 0.65));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 384;
    final blue = Paint()..color = const Color(0xFF226EFD);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(51 * k, 106 * k, 281 * k, 142 * k), Radius.circular(71 * k)), blue);
    canvas.drawPath(
      Path()
        ..moveTo(80 * k, 222 * k)
        ..lineTo(77 * k, 270 * k)
        ..quadraticBezierTo(77 * k, 281 * k, 87 * k, 276 * k)
        ..lineTo(132 * k, 243 * k)
        ..close(),
      blue,
    );
    const xs = [120.0, 184.5, 249.0];
    final white = Paint()..color = Colors.white;
    for (var i = 0; i < 3; i++) {
      canvas.drawCircle(Offset(xs[i] * k, (179 - 16 * _hop(i)) * k), 18.5 * k, white);
    }
  }

  @override
  bool shouldRepaint(covariant _BubblePainter old) => old.t != t;
}
