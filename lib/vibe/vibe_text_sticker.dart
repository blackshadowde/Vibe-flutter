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

/// Die-cut text stickers (like printed vinyl stickers): bold words with a
/// dark outline, a thick white border cut around them and a soft shadow.
enum VibeTextSticker { classic, duo, sunny, love, vibey }

class _StickerPainter extends CustomPainter {
  final String text;
  final VibeTextSticker style;
  _StickerPainter(this.text, this.style);

  static const _ink = Color(0xFF1E1F22);
  static const _blue = Color(0xFF5865F2);
  static const _pink = Color(0xFFFF8FB1);
  static const _red = Color(0xFFF23F43);
  static const _yellow = Color(0xFFFFD54F);

  static Path _heart(Offset c, double w) => Path()
    ..moveTo(c.dx, c.dy + w * 0.35)
    ..cubicTo(c.dx - w * 0.6, c.dy - w * 0.05, c.dx - w * 0.3, c.dy - w * 0.55, c.dx, c.dy - w * 0.2)
    ..cubicTo(c.dx + w * 0.3, c.dy - w * 0.55, c.dx + w * 0.6, c.dy - w * 0.05, c.dx, c.dy + w * 0.35);

  /// The words split in two colours (first half / second half), like
  /// "Not my" white and "problem" pink.
  List<(String, Color)> _parts(Color a, Color b) {
    final words = text.split(RegExp(r'\s+'));
    if (words.length < 2 || a == b) return [(text, a)];
    final half = (words.length / 2).ceil();
    return [
      ('${words.take(half).join(' ')}\n', a),
      (words.skip(half).join(' '), b),
    ];
  }

  /// Lays the words out as big as fit in [box] (up to 3 lines) and paints
  /// them die-cut: shadow, white border, dark outline, colour fill.
  Rect _dieCut(
    Canvas c,
    Rect box,
    List<(String, Color)> parts, {
    Color outline = _ink,
    Color border = Colors.white,
    double maxFrac = 0.36,
    bool italic = false,
  }) {
    TextPainter make(double size, Paint? stroke, {bool fill = false}) =>
        TextPainter(
          text: TextSpan(
            children: [
              for (final (t, col) in parts)
                TextSpan(
                  text: t,
                  style: TextStyle(
                    fontSize: size,
                    height: 0.98,
                    fontWeight: FontWeight.w900,
                    fontStyle: italic ? FontStyle.italic : FontStyle.normal,
                    letterSpacing: -size * 0.02,
                    color: stroke == null ? col : null,
                    foreground: stroke,
                  ),
                ),
            ],
          ),
          textAlign: TextAlign.center,
          textDirection: TextDirection.ltr,
          maxLines: 3,
        );
    var size = box.height * maxFrac;
    late TextPainter fill;
    while (true) {
      fill = make(size, null)..layout(maxWidth: box.width);
      if ((fill.height <= box.height && !fill.didExceedMaxLines) || size < 10) {
        break;
      }
      size *= 0.92;
    }
    final at = Offset(
      box.center.dx - fill.width / 2,
      box.center.dy - fill.height / 2,
    );
    Paint stroke(Color col, double w) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..color = col;
    // soft shadow under the whole sticker
    make(size, stroke(const Color(0x40000000), size * 0.62)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, size * 0.08))
      ..layout(maxWidth: box.width)
      ..paint(c, at + Offset(0, size * 0.06));
    // the white die-cut border
    make(size, stroke(border, size * 0.58))
      ..layout(maxWidth: box.width)
      ..paint(c, at);
    // the dark outline of the letters
    make(size, stroke(outline, size * 0.2))
      ..layout(maxWidth: box.width)
      ..paint(c, at);
    fill.paint(c, at);
    return Rect.fromLTWH(at.dx, at.dy, fill.width, fill.height);
  }

  void _sparks(Canvas c, Rect r, Color col) {
    final p = Paint()
      ..color = col
      ..strokeWidth = r.height * 0.045 + 3
      ..strokeCap = StrokeCap.round;
    for (final side in [-1.0, 1.0]) {
      final o = side < 0 ? r.topLeft : r.topRight;
      for (var k = 0; k < 3; k++) {
        final a = -math.pi / 2 + side * (0.5 + k * 0.45);
        final from = o + Offset(math.cos(a), math.sin(a)) * 14;
        final to = o + Offset(math.cos(a), math.sin(a)) * 30;
        c.drawLine(from, to, p);
      }
    }
  }

  @override
  void paint(Canvas c, Size s) {
    final w = s.width;
    final box = Rect.fromLTWH(w * 0.12, w * 0.14, w * 0.76, w * 0.72);
    c.save();
    void tilt(double a) {
      c.translate(w / 2, w / 2);
      c.rotate(a);
      c.translate(-w / 2, -w / 2);
    }

    switch (style) {
      case VibeTextSticker.classic:
        // white letters, black outline, white border (like "Verified")
        tilt(-0.04);
        _dieCut(c, box, [(text, Colors.white)]);
      case VibeTextSticker.duo:
        // two colours with little sparks (like "Not my problem")
        tilt(-0.06);
        final r = _dieCut(c, box, _parts(Colors.white, _pink));
        _sparks(c, r, _ink);
      case VibeTextSticker.sunny:
        // yellow italic letters, a bit more tilt
        tilt(0.07);
        _dieCut(c, box, [(text, _yellow)], italic: true);
      case VibeTextSticker.love:
        // pink and red with hearts
        tilt(-0.05);
        final r = _dieCut(c, box, _parts(_pink, _red), outline: const Color(0xFF6A1B3A));
        for (final (o, sz) in [
          (r.topRight + Offset(-w * 0.02, -w * 0.02), w * 0.16),
          (r.bottomLeft + Offset(w * 0.02, w * 0.03), w * 0.12),
        ]) {
          c.drawPath(_heart(o, sz * 1.25), Paint()..color = Colors.white);
          c.drawPath(_heart(o, sz), Paint()..color = _red);
        }
      case VibeTextSticker.vibey:
        // Vibey holding up a sign
        final sign = RRect.fromRectAndRadius(
          Rect.fromLTWH(w * 0.08, w * 0.06, w * 0.84, w * 0.46),
          Radius.circular(w * 0.06),
        );
        c.drawRRect(sign.inflate(w * 0.02), Paint()..color = _ink);
        c.drawRRect(sign, Paint()..color = Colors.white);
        _dieCut(c, sign.outerRect.deflate(w * 0.06), [(text, _blue)], outline: Colors.white, border: Colors.white, maxFrac: 0.4);
        final body = Offset(w / 2, w * 0.78);
        c.drawOval(Rect.fromCenter(center: body, width: w * 0.5, height: w * 0.4), Paint()..color = _blue);
        final arm = Paint()
          ..color = _blue
          ..strokeWidth = w * 0.06
          ..strokeCap = StrokeCap.round;
        c.drawLine(body.translate(-w * 0.2, -w * 0.05), Offset(w * 0.24, w * 0.52), arm);
        c.drawLine(body.translate(w * 0.2, -w * 0.05), Offset(w * 0.76, w * 0.52), arm);
        for (final dx in [-w * 0.08, w * 0.08]) {
          c.drawCircle(body.translate(dx, -w * 0.03), w * 0.035, Paint()..color = Colors.white);
          c.drawCircle(body.translate(dx, -w * 0.03), w * 0.017, Paint()..color = _ink);
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
            ..color = _ink,
        );
    }
    c.restore();
  }

  @override
  bool shouldRepaint(_StickerPainter old) =>
      old.text != text || old.style != style;
}
