// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:fluffychat/pages/chat/chat.dart';
import 'package:fluffychat/vibe/vibe_haptics.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

/// Hike-style text stickers: as you type a short message, it shows up above
/// the message box as a few stickers (Love, Pop and Vibey holding a sign).
/// Tap one to send it as a sticker instead of the text.
///
/// The sticker is a picture made on this phone and sent like a photo, so
/// it's end-to-end encrypted like everything else, and other Matrix apps
/// show it as a picture.
class VibeTextStickerBar extends StatelessWidget {
  final ChatController controller;
  const VibeTextStickerBar(this.controller, {super.key});

  static const int _maxLen = 28;

  static bool _fits(String t) {
    final s = t.trim();
    if (s.length < 2 || s.length > _maxLen) return false;
    if (s.contains('\n') || s.startsWith('/') || s.contains('://')) {
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller.sendController,
        builder: (context, v, _) {
          final text = v.text.trim();
          final show = _fits(text) && controller.editEvent == null;
          return AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.bottomCenter,
            child: !show
                ? const SizedBox(width: double.infinity)
                : SizedBox(
                    height: 92,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
                      children: [
                        for (final style in VibeTextSticker.values)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: GestureDetector(
                              onTap: () => _send(context, text, style),
                              child: SizedBox.square(
                                dimension: 80,
                                child: CustomPaint(
                                  painter: _StickerPainter(text, style),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
          );
        },
      );

  Future<void> _send(
    BuildContext context,
    String text,
    VibeTextSticker style,
  ) async {
    VibeHaptics.light();
    final messenger = ScaffoldMessenger.of(context);
    controller.sendController.clear();
    try {
      final bytes = await render(text, style);
      final file = MatrixImageFile(
        bytes: bytes,
        name: 'sticker.png',
        mimeType: 'image/png',
        width: _px,
        height: _px,
      );
      await controller.room.sendFileEvent(
        file,
        inReplyTo: controller.replyEvent,
        extraContent: {'body': text, 'chat.vibe.sticker': true},
      );
      controller.cancelReplyEventAction();
    } catch (e) {
      controller.sendController.text = text;
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not send the sticker')),
      );
    }
  }

  static const int _px = 384;

  /// The sticker as a see-through PNG.
  static Future<Uint8List> render(String text, VibeTextSticker style) async {
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    _StickerPainter(text, style).paint(c, const Size(384, 384));
    final pic = rec.endRecording();
    final image = await pic.toImage(_px, _px);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    pic.dispose();
    return data!.buffer.asUint8List();
  }
}

enum VibeTextSticker { love, pop, vibey }

class _StickerPainter extends CustomPainter {
  final String text;
  final VibeTextSticker style;
  _StickerPainter(this.text, this.style);

  static const _blue = Color(0xFF5865F2);
  static const _red = Color(0xFFF23F43);
  static const _pink = Color(0xFFFF6B8B);

  static Path _heart(Offset c, double w) => Path()
    ..moveTo(c.dx, c.dy + w * 0.35)
    ..cubicTo(c.dx - w * 0.6, c.dy - w * 0.05, c.dx - w * 0.3, c.dy - w * 0.55, c.dx, c.dy - w * 0.2)
    ..cubicTo(c.dx + w * 0.3, c.dy - w * 0.55, c.dx + w * 0.6, c.dy - w * 0.05, c.dx, c.dy + w * 0.35);

  /// Draws [text] as big as fits in [box] (up to 3 lines), outlined.
  void _words(Canvas c, Rect box, Color fill, Color edge, {double max = 0.34}) {
    var size = box.height * max;
    TextPainter make(double s, Paint? stroke) => TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: s,
          height: 1.0,
          fontWeight: FontWeight.w900,
          color: stroke == null ? fill : null,
          foreground: stroke,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      maxLines: 3,
    );
    late TextPainter tp;
    while (true) {
      tp = make(size, null)..layout(maxWidth: box.width);
      if ((tp.height <= box.height && !tp.didExceedMaxLines) || size < 10) {
        break;
      }
      size *= 0.9;
    }
    final at = Offset(
      box.center.dx - tp.width / 2,
      box.center.dy - tp.height / 2,
    );
    final outline = make(
      size,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size * 0.22
        ..strokeJoin = StrokeJoin.round
        ..color = edge,
    )..layout(maxWidth: box.width);
    outline.paint(c, at);
    tp.paint(c, at);
  }

  @override
  void paint(Canvas c, Size s) {
    final w = s.width;
    c.save();
    switch (style) {
      case VibeTextSticker.love:
        // a soft pink card, hearts around, tilted a little
        c.translate(w / 2, w / 2);
        c.rotate(-0.08);
        c.translate(-w / 2, -w / 2);
        final card = RRect.fromRectAndRadius(
          Rect.fromLTWH(w * 0.06, w * 0.2, w * 0.88, w * 0.6),
          Radius.circular(w * 0.12),
        );
        c.drawRRect(card.inflate(w * 0.025), Paint()..color = Colors.white);
        c.drawRRect(
          card,
          Paint()
            ..shader = const LinearGradient(
              colors: [Color(0xFFFF8FB1), Color(0xFFE91E63)],
            ).createShader(card.outerRect),
        );
        _words(c, card.outerRect.deflate(w * 0.06), Colors.white, const Color(0xFFAD1457));
        c.drawPath(_heart(Offset(w * 0.86, w * 0.18), w * 0.2), Paint()..color = _red);
        c.drawPath(_heart(Offset(w * 0.14, w * 0.84), w * 0.15), Paint()..color = _pink);
        c.drawPath(_heart(Offset(w * 0.1, w * 0.2), w * 0.1), Paint()..color = Colors.white);
      case VibeTextSticker.pop:
        // a yellow comic burst
        final center = Offset(w / 2, w / 2);
        final burst = Path();
        for (var i = 0; i < 24; i++) {
          final a = i * math.pi / 12;
          final r = i.isEven ? w * 0.47 : w * 0.38;
          final p = center + Offset(math.cos(a) * r, math.sin(a) * r * 0.86);
          i == 0 ? burst.moveTo(p.dx, p.dy) : burst.lineTo(p.dx, p.dy);
        }
        burst.close();
        c.drawPath(
          burst,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = w * 0.03
            ..strokeJoin = StrokeJoin.round
            ..color = const Color(0xFF1E1F22),
        );
        c.drawPath(burst, Paint()..color = const Color(0xFFFFD54F));
        _words(
          c,
          Rect.fromCenter(center: center, width: w * 0.62, height: w * 0.44),
          const Color(0xFF1E1F22),
          Colors.white,
        );
      case VibeTextSticker.vibey:
        // Vibey holding up a sign
        final sign = RRect.fromRectAndRadius(
          Rect.fromLTWH(w * 0.08, w * 0.06, w * 0.84, w * 0.46),
          Radius.circular(w * 0.06),
        );
        c.drawRRect(sign.inflate(w * 0.02), Paint()..color = const Color(0xFF1E1F22));
        c.drawRRect(sign, Paint()..color = Colors.white);
        _words(c, sign.outerRect.deflate(w * 0.05), _blue, Colors.white);
        final body = Offset(w / 2, w * 0.78);
        c.drawOval(Rect.fromCenter(center: body, width: w * 0.5, height: w * 0.4), Paint()..color = _blue);
        // arms up to the sign
        final arm = Paint()
          ..color = _blue
          ..strokeWidth = w * 0.06
          ..strokeCap = StrokeCap.round;
        c.drawLine(body.translate(-w * 0.2, -w * 0.05), Offset(w * 0.24, w * 0.52), arm);
        c.drawLine(body.translate(w * 0.2, -w * 0.05), Offset(w * 0.76, w * 0.52), arm);
        for (final dx in [-w * 0.08, w * 0.08]) {
          c.drawCircle(body.translate(dx, -w * 0.03), w * 0.035, Paint()..color = Colors.white);
          c.drawCircle(body.translate(dx, -w * 0.03), w * 0.017, Paint()..color = const Color(0xFF1E1F22));
        }
        c.drawArc(
          Rect.fromCenter(center: body.translate(0, w * 0.06), width: w * 0.12, height: w * 0.07),
          0.2,
          math.pi - 0.4,
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = w * 0.015
            ..strokeCap = StrokeCap.round
            ..color = const Color(0xFF1E1F22),
        );
    }
    c.restore();
  }

  @override
  bool shouldRepaint(_StickerPainter old) =>
      old.text != text || old.style != style;
}
