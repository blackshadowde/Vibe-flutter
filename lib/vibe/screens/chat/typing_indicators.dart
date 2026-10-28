// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:math' as math;

import 'package:vibe/vibe/screens/chat/chat.dart';
import 'package:vibe/widgets/avatar.dart';
import 'package:vibe/widgets/matrix.dart';
import 'package:flutter/material.dart';

/// Typing indicator at the bottom of the timeline, like Vibgram: a small
/// round picture of who is typing and three bouncing dots, no bubble.
/// Dots are white in dark mode and black in light mode. Fades and slides
/// up into place, and makes room so it never sits on the last message.
class TypingIndicators extends StatelessWidget {
  final ChatController controller;
  const TypingIndicators(this.controller, {super.key});

  static const _duration = Duration(milliseconds: 180);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Object>(
      stream: controller.room.client.onSync.stream.where(
        (syncUpdate) =>
            syncUpdate.rooms?.join?[controller.room.id]?.ephemeral?.any(
              (ephemeral) => ephemeral.type == 'm.typing',
            ) ??
            false,
      ),
      builder: (context, _) {
        final me = Matrix.of(context).client.userID;
        final typingUsers = controller.room.typingUsers
            .where((u) => u.stateKey != me)
            .toList();
        final typing = typingUsers.isNotEmpty;
        final who = typing ? typingUsers.first : null;

        return AnimatedContainer(
          duration: _duration,
          curve: Curves.easeOut,
          height: typing ? 26 : 0,
          alignment: Alignment.centerLeft,
          clipBehavior: Clip.hardEdge,
          decoration: const BoxDecoration(),
          child: AnimatedOpacity(
            duration: _duration,
            opacity: typing ? 1 : 0,
            child: AnimatedSlide(
              duration: _duration,
              curve: Curves.easeOut,
              offset: typing ? Offset.zero : const Offset(0, 0.25),
              child: Padding(
                padding: const EdgeInsets.only(left: 16),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (who != null) ...[
                      Avatar(
                        size: 20,
                        mxContent: who.avatarUrl,
                        name: who.calcDisplayname(),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      const SizedBox(width: 8),
                    ],
                    if (typing) const _VibeTypingDots(),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Three dots bouncing one after another (1.2 s cycle), like Vibgram.
class _VibeTypingDots extends StatefulWidget {
  const _VibeTypingDots();

  @override
  State<_VibeTypingDots> createState() => _VibeTypingDotsState();
}

class _VibeTypingDotsState extends State<_VibeTypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return CustomPaint(
      size: const Size(24, 16),
      painter: _DotsPainter(
        _ctrl,
        dark ? const Color(0xFFFFFFFF) : const Color(0xFF000000),
      ),
    );
  }
}

class _DotsPainter extends CustomPainter {
  final Animation<double> progress;
  final Color color;

  _DotsPainter(this.progress, this.color) : super(repaint: progress);

  @override
  void paint(Canvas canvas, Size size) {
    const r = 3.0;
    final paint = Paint()..isAntiAlias = true;
    final cy = size.height / 2 + 2;
    for (var i = 0; i < 3; i++) {
      final phase = progress.value * math.pi * 2 - i * 0.7;
      final bounce = math.max(0.0, math.sin(phase));
      paint.color = color.withAlpha((150 + 105 * bounce).round());
      canvas.drawCircle(Offset(r + i * 9, cy - bounce * 4), r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _DotsPainter old) => old.color != color;
}
