// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';

/// Three dots that fade between gray and near-black, one after the other.
class TypingAnimation extends StatefulWidget {
  final double size;
  const TypingAnimation({this.size = 6.0, super.key});

  @override
  State<TypingAnimation> createState() => _TypingAnimationState();
}

class _TypingAnimationState extends State<TypingAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  static const Color _light = Color(0xFFB5BAC1);
  static const Color _dark = Color(0xFF1A191E);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 3; i++)
            Container(
              width: size,
              height: size,
              margin: EdgeInsets.symmetric(horizontal: size * 0.5),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Color.lerp(
                  _light,
                  _dark,
                  _wave((_controller.value - i * 0.18) % 1.0),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 0 -> 1 -> 0 smooth pulse over one cycle.
  double _wave(double t) {
    final v = t < 0.5 ? t * 2 : (1 - t) * 2;
    return Curves.easeInOut.transform(v);
  }
}
