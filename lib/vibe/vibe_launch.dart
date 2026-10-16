// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Opening the app: the blue 💬 sits still and its three dots hop once,
/// like someone typing, then it fades away. The app loads underneath the
/// whole time, so it never makes you wait.
class VibeLaunch extends StatefulWidget {
  final Widget child;
  const VibeLaunch({required this.child, super.key});

  static bool _shown = false;

  @override
  State<VibeLaunch> createState() => _VibeLaunchState();
}

class _VibeLaunchState extends State<VibeLaunch> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late bool _show = !VibeLaunch._shown;
  bool _closed = false;
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1150));
  bool _done = false;

  @override
  void initState() {
    super.initState();
    VibeLaunch._shown = true;
    WidgetsBinding.instance.addObserver(this);
    if (_show) _play();
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
      _c.reset();
      setState(() {
        _show = true;
        _done = false;
      });
      _play();
    }
  }

  void _play() {
    {
      // The first frames after start are heavy (the chat list builds), so
      // wait until they're drawn, or the hop plays while frames are dropped
      // and you'd only see a still icon.
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await WidgetsBinding.instance.endOfFrame;
        await Future<void>.delayed(const Duration(milliseconds: 250));
        if (!mounted) return;
        _c.forward().whenComplete(() {
          if (mounted) setState(() => _done = true);
        });
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_show || _done) return widget.child;
    final bg = Theme.of(context).brightness == Brightness.dark ? const Color(0xFF1A191E) : Colors.white;
    return Stack(
      children: [
        widget.child,
        IgnorePointer(
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) {
              final t = _c.value;
              final out = ((t - 0.72) / 0.28).clamp(0.0, 1.0);
              return Opacity(
                opacity: 1 - out,
                child: ColoredBox(
                  color: bg,
                  child: Center(
                    child: Transform.scale(
                      scale: 1 + 0.12 * out,
                      child: SizedBox.square(dimension: 150, child: CustomPaint(painter: _BubblePainter(t))),
                    ),
                  ),
                ),
              );
            },
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
