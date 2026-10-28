// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:vibe/vibe/vibe_stickers.dart';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:vibe/vibe/screens/chat/chat.dart';
import 'package:vibe/vibe/vibe_haptics.dart';
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
    controller.clearInput();
    // the keyboard can put back the word it was still composing: clear again
    Future<void>.delayed(const Duration(milliseconds: 300), () {
      if (controller.mounted &&
          controller.sendController.text.trim() == text) {
        controller.clearInput();
      }
    });
    try {
      final (bytes, sw, sh) = await render(text, style);
      // the name is the words, so there's no caption under the sticker
      final name =
          '${text.replaceAll(RegExp(r'[\\/:*?"<>|\n]'), '').trim()}.png';
      final file = MatrixImageFile(
        bytes: bytes,
        name: name,
        mimeType: 'image/png',
        width: sw,
        height: sh,
      );
      // its own thumbnail: Matrix would otherwise make a JPEG one, which
      // has no see-through background (the black square)
      final thumb = MatrixImageFile(
        bytes: bytes,
        name: name,
        mimeType: 'image/png',
        width: sw,
        height: sh,
      );
      await controller.room.sendFileEvent(
        file,
        thumbnail: thumb,
        inReplyTo: controller.replyEvent,
        extraContent: {'chat.vibe.sticker': true, 'chat.vibe.sticker_text': text},
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

  /// The sticker as a see-through PNG, cut tight around the drawing (no
  /// empty space around it). Returns the bytes and the size.
  static Future<(Uint8List, int, int)> render(
    String text,
    VibeTextSticker style,
  ) async {
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    _StickerPainter(text, style).paint(c, const Size(384, 384));
    final pic = rec.endRecording();
    final image = await pic.toImage(_px, _px);
    pic.dispose();
    // find where the drawing is
    final raw = (await image.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    ))!.buffer.asUint8List();
    var minX = _px, minY = _px, maxX = -1, maxY = -1;
    for (var y = 0; y < _px; y++) {
      for (var x = 0; x < _px; x++) {
        if (raw[(y * _px + x) * 4 + 3] > 8) {
          if (x < minX) minX = x;
          if (x > maxX) maxX = x;
          if (y < minY) minY = y;
          if (y > maxY) maxY = y;
        }
      }
    }
    if (maxX < 0) {
      minX = minY = 0;
      maxX = maxY = _px - 1;
    }
    const pad = 4;
    final src = Rect.fromLTRB(
      (minX - pad).clamp(0, _px).toDouble(),
      (minY - pad).clamp(0, _px).toDouble(),
      (maxX + 1 + pad).clamp(0, _px).toDouble(),
      (maxY + 1 + pad).clamp(0, _px).toDouble(),
    );
    final w = src.width.round(), h = src.height.round();
    final rec2 = ui.PictureRecorder();
    Canvas(rec2).drawImageRect(
      image,
      src,
      Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      Paint()..filterQuality = FilterQuality.high,
    );
    final pic2 = rec2.endRecording();
    final out = await pic2.toImage(w, h);
    final data = await out.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    out.dispose();
    pic2.dispose();
    return (data!.buffer.asUint8List(), w, h);
  }
}

/// Die-cut text stickers (like printed vinyl stickers): bold words with a
/// dark outline, a thick white border cut around them and a soft shadow.
enum VibeTextSticker { marker, bubble, comic, brush, script, retro, classic, vibey }

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
    String? font,
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
                    fontFamily: font,
                    fontWeight: font == null ? FontWeight.w900 : FontWeight.w400,
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
      case VibeTextSticker.marker:
        // marker lettering, white then pink, with sparks ("Not My Problem")
        tilt(-0.06);
        final r = _dieCut(c, box, _parts(Colors.white, _pink), font: 'PermanentMarker', maxFrac: 0.3);
        _sparks(c, r, _ink);
      case VibeTextSticker.bubble:
        // fat round letters, white with black outline
        tilt(-0.04);
        _dieCut(c, box, [(text, Colors.white)], font: 'LuckiestGuy', maxFrac: 0.3);
      case VibeTextSticker.comic:
        // comic-book yellow
        tilt(0.06);
        _dieCut(c, box, [(text, _yellow)], font: 'Bangers', maxFrac: 0.38);
      case VibeTextSticker.brush:
        // hand brush lettering, pink and white
        tilt(-0.05);
        final r = _dieCut(c, box, _parts(_pink, Colors.white), font: 'CaveatBrush', maxFrac: 0.38);
        _sparks(c, r, _pink);
      case VibeTextSticker.script:
        // flowing script in pink and red, with hearts
        tilt(-0.07);
        final r = _dieCut(c, box, _parts(_pink, _red), outline: const Color(0xFF6A1B3A), font: 'Pacifico', maxFrac: 0.28);
        for (final (o, sz) in [
          (r.topRight + Offset(-w * 0.02, -w * 0.02), w * 0.16),
          (r.bottomLeft + Offset(w * 0.02, w * 0.03), w * 0.12),
        ]) {
          c.drawPath(_heart(o, sz * 1.25), Paint()..color = Colors.white);
          c.drawPath(_heart(o, sz), Paint()..color = _red);
        }
      case VibeTextSticker.retro:
        // retro script, Vibe blue and white
        tilt(-0.05);
        _dieCut(c, box, _parts(_blue, const Color(0xFF4FC3F7)), font: 'Lobster', maxFrac: 0.32);
      case VibeTextSticker.classic:
        // plain heavy letters, white on black (like "Verified")
        tilt(-0.03);
        _dieCut(c, box, [(text, Colors.white)]);
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

/// Vibe's own Telugu (Tenglish) text sticker pack: everyday phrases in the
/// sticker lettering styles, made on this phone and added to your stickers.
abstract class VibeTeluguPack {
  static const name = 'Telugu';
  static const phrases = [
    'Em chestunnav?',
    'Baagunnava?',
    'Super ra!',
    'Sare sare',
    'Ayyo!',
    'Chill ra',
    'Thinnava?',
    'Miss you ra',
    'Vasthunna!',
    'Late ayyindi',
    'Good night ra',
    'Hahaha',
    'Enti idhi?',
    'Thanks ra',
    'Kopam ah?',
    'Nijamga?',
  ];

  static Future<int> install(Client client) async {
    final files = <(String, Uint8List)>[];
    final styles = VibeTextSticker.values;
    for (final (i, ph) in phrases.indexed) {
      final (bytes, _, _) = await VibeTextStickerBar.render(
        ph,
        styles[i % styles.length],
      );
      files.add(('${ph.replaceAll(RegExp(r'[^A-Za-z ]'), '').trim()}.png', bytes));
    }
    return VibeStickers.add(client, files, name);
  }
}
