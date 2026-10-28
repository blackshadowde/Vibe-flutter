// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:vibe/vibe/vibe_palette.dart';
import 'package:vibe/vibe/vibe_profile_cache.dart';
import 'package:vibe/widgets/avatar.dart';
import 'package:vibe/widgets/matrix.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:matrix/matrix.dart';

/// Settings > Style: the Text size preview, drawn exactly like Vibe's chat
/// (and Vibgram's): picture, name and time above the text, the reply line
/// with its curve, ticks after your message. Uses Telegram's preview lines.
class VibeTextSizePreview extends StatelessWidget {
  /// The size being previewed (passing it makes the preview redraw while
  /// the slider moves).
  final int size;
  const VibeTextSizePreview({required this.size, super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final client = Matrix.of(context).client;
    final textSize = (size + 1).toDouble(); // as VibeTextSize.message
    final now = DateTime.now();
    final t1 = DateFormat('h:mm a').format(now.subtract(const Duration(minutes: 2)));
    final t2 = DateFormat('h:mm a').format(now);
    final otherName = dark ? const Color(0xFFF2F3F5) : const Color(0xFF060607);
    final ownName = dark ? const Color(0xFFB5BAC1) : const Color(0xFF4E5058);
    final lineColor = cs.onSurfaceVariant.withValues(alpha: 0.45);

    return MediaQuery(
      // Same as the chat: only message text follows the size.
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        padding: const EdgeInsets.fromLTRB(0, 10, 12, 14),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(20),
        ),
        child: VibeOwnProfileBuilder(
          client: client,
          builder: (context, me) {
            final myName = me?.displayName ?? client.userID?.localpart ?? 'You';
            Widget header(String name, Color color, String time) => Row(
              children: [
                Flexible(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      height: 1.15,
                      color: color,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  time,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.15,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            );
            final body = TextStyle(
              fontSize: textSize,
              height: 1.3,
              color: cs.onSurface,
            );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Reply line: ╭ @me Good morning! 👋
                SizedBox(
                  height: 22,
                  child: Row(
                    children: [
                      SizedBox(
                        width: 64,
                        height: 22,
                        child: Padding(
                          padding: const EdgeInsets.only(left: 12),
                          child: CustomPaint(painter: _Curve(lineColor)),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Avatar(
                        mxContent: me?.avatarUrl,
                        name: myName,
                        size: 16,
                        client: client,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '@$myName',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: ownName,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Hey! Still on for tonight? 🍕',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13.5,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                _Row(
                  avatar: const Avatar(name: 'Maya', size: 40),
                  header: header('Maya', otherName, t1),
                  child: Text('Yes! I\'ll bring the board games', style: body),
                ),
                const SizedBox(height: 14),
                _Row(
                  avatar: Avatar(
                    mxContent: me?.avatarUrl,
                    name: myName,
                    size: 40,
                    client: client,
                  ),
                  header: header(myName, ownName, t2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Flexible(
                        child: Text('Perfect, see you at 8 🎲', style: body),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(left: 6, bottom: 3),
                        child: Icon(
                          Icons.done_all,
                          size: 18,
                          color: VibePalette.accent,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final Widget avatar;
  final Widget header;
  final Widget child;
  const _Row({required this.avatar, required this.header, required this.child});

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(width: 12),
      avatar,
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [header, const SizedBox(height: 2), child],
        ),
      ),
    ],
  );
}

class _Curve extends CustomPainter {
  final Color color;
  const _Curve(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    // Same curve as replies in the chat: from the avatar up and right.
    final cx = 20.0; // centre of a 40 px avatar
    final mid = size.height / 2;
    const r = 8.0;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final path = Path()
      ..moveTo(cx, size.height + 2)
      ..lineTo(cx, mid + r)
      ..quadraticBezierTo(cx, mid, cx + r, mid)
      ..lineTo(size.width, mid);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _Curve old) => old.color != color;
}
