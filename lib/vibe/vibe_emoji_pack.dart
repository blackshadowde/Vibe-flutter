// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:matrix/matrix.dart';

/// Vibe's own animated emoji pack: "Vibey", a little round blurple
/// character, drawn here in code (original artwork, no one else's).
///
/// "Add" draws each one as an animated GIF on this phone, uploads it to
/// your Matrix server and puts it in your personal emoji pack
/// (im.ponies.user_emotes), so it shows in the emoji / sticker picker and,
/// like any Matrix custom emoji, animates for the people you send it to
/// (Element and other apps too).
abstract class VibeEmojiPack {
  static const _size = 128;
  static const _frames = 16;
  static const _frameDelay = 7; // 1/100 s → about 1.1 s per loop

  /// shortcode → painter (t goes 0..1 over one loop)
  static final Map<String, void Function(Canvas, double)> emotes = {
    'vibe_hi': _hi,
    'vibe_lol': _lol,
    'vibe_love': _love,
    'vibe_cry': _cry,
    'vibe_angry': _angry,
    'vibe_cool': _cool,
    'vibe_wow': _wow,
    'vibe_sleepy': _sleepy,
    'vibe_party': _party,
    'vibe_think': _think,
    'vibe_wink': _wink,
    'vibe_yes': _yes,
  };

  /// Installs the pack; [progress] gets "3/12" style updates.
  static Future<void> install(
    Client client, {
    Map<String, void Function(Canvas, double)>? pack,
    void Function(String)? progress,
  }) async {
    final set = pack ?? emotes;
    final images = <String, Object?>{};
    var i = 0;
    for (final e in set.entries) {
      i++;
      progress?.call('Drawing ${e.key} ($i/${set.length})');
      final gif = await _gif(e.value);
      final uri = await client.uploadContent(
        gif,
        filename: '${e.key}.gif',
        contentType: 'image/gif',
      );
      images[e.key] = {
        'url': uri.toString(),
        'body': e.key,
        'info': {
          'mimetype': 'image/gif',
          'w': _size,
          'h': _size,
          'size': gif.length,
        },
        'usage': ['emoticon', 'sticker'],
      };
    }
    progress?.call('Saving the pack');
    final old = client.accountData['im.ponies.user_emotes']?.content ?? {};
    final oldImages = old.tryGetMap<String, Object?>('images') ?? {};
    final content = Map<String, Object?>.from(old);
    content['images'] = {...oldImages, ...images};
    content['pack'] ??= {'display_name': 'My emojis'};
    await client.setAccountData(
      client.userID!,
      'im.ponies.user_emotes',
      content,
    );
    // show it right away (the server's copy arrives with the next sync)
    client.accountData['im.ponies.user_emotes'] = BasicEvent(
      type: 'im.ponies.user_emotes',
      content: content,
    );
  }

  static bool installed(Client client, [String key = 'vibe_hi']) {
    final images = client.accountData['im.ponies.user_emotes']?.content
        .tryGetMap<String, Object?>('images');
    return images?.containsKey(key) ?? false;
  }

  /// Vibe's love pack (Valentine's day): hearts, hugs, kisses, a rose…
  static final Map<String, void Function(Canvas, double)> lovePack = {
    'love_heart': _loveHeart,
    'love_hug': _loveHug,
    'love_kiss': _loveKiss,
    'love_rose': _loveRose,
    'love_letter': _loveLetter,
    'love_you': _loveYou,
    'love_cupid': _loveCupid,
    'love_miss': _loveMiss,
  };

  // ---- drawing → GIF ------------------------------------------------------

  static Future<Uint8List> _gif(void Function(Canvas, double) paint) async {
    final enc = img.GifEncoder(delay: _frameDelay, repeat: 0);
    for (var f = 0; f < _frames; f++) {
      final rec = ui.PictureRecorder();
      final c = Canvas(rec);
      paint(c, f / _frames);
      final pic = rec.endRecording();
      final image = await pic.toImage(_size, _size);
      final data = await image.toByteData(
        format: ui.ImageByteFormat.rawStraightRgba,
      );
      image.dispose();
      pic.dispose();
      enc.addFrame(_toPalette(data!.buffer.asUint8List()));
    }
    return enc.finish()!;
  }

  static img.PaletteUint8 _palette() {
    final p = img.PaletteUint8(256, 4);
    p.setRgba(0, 0, 0, 0, 0); // see-through
    var i = 1;
    for (var r = 0; r < 6; r++) {
      for (var g = 0; g < 6; g++) {
        for (var b = 0; b < 6; b++) {
          p.setRgba(i++, r * 51, g * 51, b * 51, 255);
        }
      }
    }
    for (final c in _brand) {
      p.setRgba(i++, (c >> 16) & 255, (c >> 8) & 255, c & 255, 255);
    }
    return p;
  }

  // exact colours Vibey is drawn with (so they don't shift)
  static const _brand = [
    0x5865F2, 0x7983F5, 0x4752C4, 0xFFFFFF, 0x1E1F22, 0xF23F43, 0xFF6B8B,
    0xFFD54F, 0x4FC3F7, 0xFFB3C1, 0x23A55A, 0xE9EAFE, 0xF0B232, 0x949CF7,
  ];

  static img.Image _toPalette(Uint8List rgba) {
    final out = img.Image(
      width: _size,
      height: _size,
      numChannels: 1,
      palette: _palette(),
    );
    for (var y = 0; y < _size; y++) {
      for (var x = 0; x < _size; x++) {
        final o = (y * _size + x) * 4;
        final a = rgba[o + 3];
        if (a < 110) {
          out.setPixelIndex(x, y, 0);
          continue;
        }
        final r = rgba[o], g = rgba[o + 1], b = rgba[o + 2];
        var best = -1;
        var bestD = 900;
        for (var k = 0; k < _brand.length; k++) {
          final c = _brand[k];
          final d = (r - ((c >> 16) & 255)).abs() +
              (g - ((c >> 8) & 255)).abs() +
              (b - (c & 255)).abs();
          if (d < bestD) {
            bestD = d;
            best = k;
          }
        }
        if (bestD < 40) {
          out.setPixelIndex(x, y, 217 + best);
        } else {
          final q = 1 +
              ((r * 5 + 127) ~/ 255) * 36 +
              ((g * 5 + 127) ~/ 255) * 6 +
              ((b * 5 + 127) ~/ 255);
          out.setPixelIndex(x, y, q);
        }
      }
    }
    return out;
  }

  // ---- Vibey --------------------------------------------------------------

  static const _blue = Color(0xFF5865F2);
  static const _light = Color(0xFF7983F5);
  static const _ink = Color(0xFF1E1F22);
  static const _white = Color(0xFFFFFFFF);
  static const _red = Color(0xFFF23F43);
  static const _pink = Color(0xFFFF6B8B);
  static const _yellow = Color(0xFFFFD54F);
  static const _tear = Color(0xFF4FC3F7);

  static double _wave(double t, [double n = 1]) => math.sin(t * 2 * math.pi * n);
  static Paint _p(Color c) => Paint()..color = c..isAntiAlias = true;
  static Paint _s(Color c, double w) => Paint()
    ..color = c
    ..style = PaintingStyle.stroke
    ..strokeWidth = w
    ..strokeCap = StrokeCap.round;

  /// The round body; returns its centre. [sx]/[sy] squash and stretch.
  static Offset _body(Canvas c, {double dy = 0, double sx = 1, double sy = 1, Color color = _blue}) {
    final center = Offset(64, 70 + dy);
    final rect = Rect.fromCenter(center: center, width: 92 * sx, height: 88 * sy);
    c.drawOval(rect, _p(color));
    c.drawOval(
      Rect.fromCenter(center: center.translate(-16 * sx, -22 * sy), width: 26 * sx, height: 14 * sy),
      _p(_light),
    );
    return center;
  }

  static void _eyes(Canvas c, Offset o, {double open = 1, double look = 0}) {
    for (final dx in [-16.0, 16.0]) {
      final e = o.translate(dx, -6);
      if (open < 0.2) {
        c.drawLine(e.translate(-6, 0), e.translate(6, 0), _s(_ink, 4));
      } else {
        c.drawOval(Rect.fromCenter(center: e, width: 16, height: 18 * open), _p(_white));
        c.drawCircle(e.translate(look * 3, look.abs() * -2), 4.5 * open, _p(_ink));
      }
    }
  }

  static void _happyEyes(Canvas c, Offset o) {
    for (final dx in [-16.0, 16.0]) {
      final e = o.translate(dx, -4);
      c.drawArc(Rect.fromCenter(center: e, width: 14, height: 12), math.pi, math.pi, false, _s(_ink, 4));
    }
  }

  static void _smile(Canvas c, Offset o, {double w = 26, double h = 16}) {
    c.drawArc(Rect.fromCenter(center: o.translate(0, 12), width: w, height: h), 0.15, math.pi - 0.3, false, _s(_ink, 4));
  }

  static void _hi(Canvas c, double t) {
    final o = _body(c, dy: _wave(t, 2) * 2);
    _eyes(c, o);
    _smile(c, o);
    // waving hand
    c.save();
    c.translate(o.dx + 46, o.dy + 4);
    c.rotate(-0.4 + _wave(t, 2) * 0.45);
    c.drawOval(Rect.fromCenter(center: const Offset(0, -18), width: 18, height: 26), _p(_blue));
    c.drawCircle(const Offset(0, -30), 10, _p(_blue));
    c.restore();
  }

  static void _lol(Canvas c, double t) {
    final shake = _wave(t, 4) * 3;
    final o = _body(c, dy: -_wave(t, 2).abs() * 5, sx: 1 + _wave(t, 4) * 0.02);
    c.save();
    c.translate(shake, 0);
    _happyEyes(c, o);
    final m = Path()
      ..moveTo(o.dx - 16, o.dy + 8)
      ..quadraticBezierTo(o.dx, o.dy + 34, o.dx + 16, o.dy + 8)
      ..close();
    c.drawPath(m, _p(_ink));
    c.drawCircle(o.translate(0, 22), 5, _p(_pink));
    // tears popping out
    final k = (t * 2) % 1;
    for (final s in [-1.0, 1.0]) {
      c.drawOval(
        Rect.fromCenter(center: o.translate(s * (30 + k * 14), -4 + k * 10), width: 8, height: 11),
        _p(_tear.withValues(alpha: 1 - k)),
      );
    }
    c.restore();
  }

  static Path _heart(Offset c, double w) => Path()
    ..moveTo(c.dx, c.dy + w * 0.35)
    ..cubicTo(c.dx - w * 0.6, c.dy - w * 0.05, c.dx - w * 0.3, c.dy - w * 0.55, c.dx, c.dy - w * 0.2)
    ..cubicTo(c.dx + w * 0.3, c.dy - w * 0.55, c.dx + w * 0.6, c.dy - w * 0.05, c.dx, c.dy + w * 0.35);

  static void _love(Canvas c, double t) {
    final o = _body(c);
    final beat = 1 + 0.18 * math.max(0.0, _wave(t, 2));
    for (final dx in [-16.0, 16.0]) {
      c.drawPath(_heart(o.translate(dx, -6), 18 * beat), _p(_red));
    }
    _smile(c, o);
    final k = t;
    c.drawPath(_heart(Offset(100, 40 - k * 30), 14), _p(_pink.withValues(alpha: 1 - k)));
    final k2 = (t + 0.5) % 1;
    c.drawPath(_heart(Offset(26, 46 - k2 * 30), 11), _p(_pink.withValues(alpha: 1 - k2)));
  }

  static void _cry(Canvas c, double t) {
    final o = _body(c, dy: _wave(t, 2) * 1.5);
    for (final dx in [-16.0, 16.0]) {
      c.drawArc(Rect.fromCenter(center: o.translate(dx, -2), width: 14, height: 10), math.pi + 0.2, math.pi - 0.4, false, _s(_ink, 4));
    }
    c.drawArc(Rect.fromCenter(center: o.translate(0, 26), width: 22, height: 14), math.pi + 0.3, math.pi - 0.6, false, _s(_ink, 4));
    for (final dx in [-18.0, 18.0]) {
      for (var n = 0; n < 2; n++) {
        final k = (t + n * 0.5) % 1;
        c.drawOval(Rect.fromCenter(center: o.translate(dx, 6 + k * 36), width: 8, height: 12), _p(_tear.withValues(alpha: 1 - k * 0.8)));
      }
    }
  }

  static void _angry(Canvas c, double t) {
    final pulse = (_wave(t, 2) + 1) / 2;
    final o = _body(c, color: Color.lerp(_blue, _red, 0.35 + pulse * 0.4)!, sx: 1 + pulse * 0.03);
    c.drawLine(o.translate(-24, -18), o.translate(-8, -10), _s(_ink, 5));
    c.drawLine(o.translate(24, -18), o.translate(8, -10), _s(_ink, 5));
    _eyes(c, o.translate(0, 2), open: 0.7);
    c.drawArc(Rect.fromCenter(center: o.translate(0, 26), width: 24, height: 14), math.pi + 0.3, math.pi - 0.6, false, _s(_ink, 4));
    for (final s in [-1.0, 1.0]) {
      final k = (t * 2) % 1;
      c.drawCircle(Offset(64 + s * 40, 26 - k * 18), 6 + k * 6, _p(_white.withValues(alpha: (1 - k) * 0.9)));
    }
  }

  static void _cool(Canvas c, double t) {
    final o = _body(c, dy: _wave(t) * 2);
    final drop = math.min(1.0, t * 3);
    final g = o.translate(0, -30 + drop * 24);
    final glass = Path()
      ..addRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: g.translate(-15, 0), width: 26, height: 16), const Radius.circular(6)))
      ..addRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: g.translate(15, 0), width: 26, height: 16), const Radius.circular(6)));
    c.drawPath(glass, _p(_ink));
    c.drawLine(g.translate(-3, -2), g.translate(3, -2), _s(_ink, 4));
    c.drawArc(Rect.fromCenter(center: o.translate(4, 16), width: 22, height: 12), 0.2, math.pi - 0.9, false, _s(_ink, 4));
    if (t > 0.4) {
      final k = (t - 0.4) / 0.6;
      final s = math.sin(k * math.pi) * 9;
      final p = o.translate(30, -24);
      c.drawLine(p.translate(-s, 0), p.translate(s, 0), _s(_white, 3));
      c.drawLine(p.translate(0, -s), p.translate(0, s), _s(_white, 3));
    }
  }

  static void _wow(Canvas c, double t) {
    final st = 1 + 0.06 * _wave(t, 2);
    final o = _body(c, sx: 2 - st, sy: st);
    _eyes(c, o, open: 1.15);
    final m = 9 + 4 * ((_wave(t, 2) + 1) / 2);
    c.drawOval(Rect.fromCenter(center: o.translate(0, 22), width: m * 1.4, height: m * 1.8), _p(_ink));
  }

  static void _sleepy(Canvas c, double t) {
    final breathe = _wave(t) * 0.03;
    final o = _body(c, sx: 1 + breathe, sy: 1 - breathe);
    _eyes(c, o, open: 0);
    c.drawCircle(o.translate(0, 20), 4, _p(_ink));
    for (var n = 0; n < 3; n++) {
      final k = (t + n / 3) % 1;
      final tp = TextPainter(
        text: TextSpan(text: 'z', style: TextStyle(color: _white.withValues(alpha: 1 - k), fontSize: 14 + n * 4.0, fontWeight: FontWeight.w900)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(c, Offset(88 + k * 16, 40 - k * 34));
    }
  }

  static void _party(Canvas c, double t) {
    final o = _body(c, dy: -_wave(t, 2).abs() * 4);
    _happyEyes(c, o);
    _smile(c, o, w: 30, h: 22);
    final hat = Path()
      ..moveTo(o.dx - 14, o.dy - 38)
      ..lineTo(o.dx + 14, o.dy - 38)
      ..lineTo(o.dx + 4, o.dy - 70)
      ..close();
    c.drawPath(hat, _p(_yellow));
    c.drawCircle(Offset(o.dx + 4, o.dy - 72), 5, _p(_pink));
    const cols = [_red, _yellow, _tear, _pink, Color(0xFF23A55A)];
    final r = math.Random(3);
    for (var n = 0; n < 12; n++) {
      final x = r.nextDouble() * 128;
      final k = (t + r.nextDouble()) % 1;
      c.save();
      c.translate(x + math.sin(k * 6 + n) * 6, -8 + k * 140);
      c.rotate(k * 6 + n);
      c.drawRect(const Rect.fromLTWH(-3, -2, 6, 4), _p(cols[n % cols.length]));
      c.restore();
    }
  }

  static void _think(Canvas c, double t) {
    final o = _body(c);
    _eyes(c, o, look: -1);
    c.drawLine(o.translate(-6, 20), o.translate(10, 16), _s(_ink, 4));
    c.drawCircle(o.translate(22, 30), 11, _p(_light));
    for (var n = 0; n < 3; n++) {
      final on = t * 4 > n + 0.5;
      if (on) c.drawCircle(Offset(80 + n * 12.0, 22), 4.5, _p(_white));
    }
  }

  static void _wink(Canvas c, double t) {
    final o = _body(c, dy: _wave(t) * 2);
    final blink = t > 0.45 && t < 0.75;
    final l = o.translate(-16, -6);
    c.drawOval(Rect.fromCenter(center: l, width: 16, height: 18), _p(_white));
    c.drawCircle(l, 4.5, _p(_ink));
    final r = o.translate(16, -6);
    if (blink) {
      c.drawArc(Rect.fromCenter(center: r, width: 14, height: 10), math.pi, math.pi, false, _s(_ink, 4));
    } else {
      c.drawOval(Rect.fromCenter(center: r, width: 16, height: 18), _p(_white));
      c.drawCircle(r, 4.5, _p(_ink));
    }
    _smile(c, o.translate(4, 0), w: 24, h: 14);
    if (blink) {
      c.drawOval(Rect.fromCenter(center: o.translate(6, 26), width: 10, height: 12), _p(_pink));
    }
  }

  static void _yes(Canvas c, double t) {
    final nod = math.max(0.0, _wave(t, 2)) * 6;
    final o = _body(c, dy: nod);
    _happyEyes(c, o);
    _smile(c, o);
    // a green tick pops next to Vibey
    final k = math.min(1.0, t * 2);
    final p = Paint()
      ..color = const Color(0xFF23A55A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final tick = Path()
      ..moveTo(92, 28)
      ..lineTo(100, 36)
      ..lineTo(116, 16);
    final m = tick.computeMetrics().first;
    c.drawPath(m.extractPath(0, m.length * k), p);
  }

  // ---- love pack ----------------------------------------------------------

  static void _sparkle(Canvas c, Offset p, double r, Color col) {
    final path = Path()
      ..moveTo(p.dx, p.dy - r)
      ..quadraticBezierTo(p.dx, p.dy, p.dx + r, p.dy)
      ..quadraticBezierTo(p.dx, p.dy, p.dx, p.dy + r)
      ..quadraticBezierTo(p.dx, p.dy, p.dx - r, p.dy)
      ..quadraticBezierTo(p.dx, p.dy, p.dx, p.dy - r);
    c.drawPath(path, _p(col));
  }

  static void _loveHeart(Canvas c, double t) {
    final beat = 1 + 0.12 * math.max(0.0, _wave(t, 2));
    c.drawPath(_heart(const Offset(64, 70), 100 * beat), _p(_red));
    c.drawPath(_heart(const Offset(50, 54), 26 * beat), _p(_pink));
    for (var n = 0; n < 3; n++) {
      final k = (t + n / 3) % 1;
      _sparkle(c, Offset(20.0 + n * 44, 26 + (n.isEven ? 0 : 70)), 9 * math.sin(k * math.pi), _yellow);
    }
  }

  static void _blob(Canvas c, Offset o, double r, Color col, {bool happy = true}) {
    c.drawCircle(o, r, _p(col));
    for (final dx in [-r * 0.35, r * 0.35]) {
      c.drawArc(Rect.fromCenter(center: o.translate(dx, -r * 0.1), width: r * 0.32, height: r * 0.26), math.pi, math.pi, false, _s(_ink, 3.5));
    }
    if (happy) {
      c.drawArc(Rect.fromCenter(center: o.translate(0, r * 0.25), width: r * 0.5, height: r * 0.3), 0.2, math.pi - 0.4, false, _s(_ink, 3.5));
    }
    c.drawCircle(o.translate(-r * 0.55, r * 0.15), r * 0.12, _p(_pink.withValues(alpha: 0.7)));
    c.drawCircle(o.translate(r * 0.55, r * 0.15), r * 0.12, _p(_pink.withValues(alpha: 0.7)));
  }

  static void _loveHug(Canvas c, double t) {
    final squeeze = math.max(0.0, _wave(t, 1)) * 6;
    _blob(c, Offset(44 + squeeze, 78), 32, _blue);
    _blob(c, Offset(84 - squeeze, 78), 32, const Color(0xFFFF6B8B));
    // arms
    c.drawArc(Rect.fromCenter(center: const Offset(64, 84), width: 70 - squeeze * 2, height: 30), 0.2, math.pi - 0.4, false, _s(_light, 8));
    final k = t;
    c.drawPath(_heart(Offset(64, 36 - k * 18), 26 * (0.6 + 0.4 * math.sin(k * math.pi))), _p(_red.withValues(alpha: 1 - k * 0.6)));
  }

  static void _loveKiss(Canvas c, double t) {
    _blob(c, const Offset(50, 72), 36, const Color(0xFFFF6B8B), happy: false);
    // pursed lips
    c.drawOval(Rect.fromCenter(center: const Offset(56, 84), width: 12, height: 10), _p(_red));
    final k = t;
    final p = Offset(70 + k * 46, 72 - k * 40);
    c.drawPath(_heart(p, 20 + k * 10), _p(_red.withValues(alpha: 1 - k * 0.7)));
  }

  static void _loveRose(Canvas c, double t) {
    final open = 0.85 + 0.15 * math.sin(t * 2 * math.pi);
    c.drawLine(const Offset(64, 70), const Offset(64, 122), _s(const Color(0xFF23A55A), 6));
    c.drawOval(Rect.fromCenter(center: const Offset(52, 100), width: 22, height: 10), _p(const Color(0xFF23A55A)));
    for (var n = 0; n < 6; n++) {
      final a = n * math.pi / 3 + t * 0.6;
      c.drawCircle(Offset(64 + math.cos(a) * 16 * open, 50 + math.sin(a) * 14 * open), 16 * open, _p(_red));
    }
    c.drawCircle(const Offset(64, 50), 14, _p(const Color(0xFFC62828)));
    c.drawArc(Rect.fromCenter(center: const Offset(64, 50), width: 16, height: 14), 0, math.pi * 1.4, false, _s(const Color(0xFF8E1B1B), 3));
  }

  static void _loveLetter(Canvas c, double t) {
    final env = RRect.fromRectAndRadius(const Rect.fromLTWH(18, 58, 92, 58), const Radius.circular(8));
    final k = math.min(1.0, t * 2);
    // heart rising out
    c.drawPath(_heart(Offset(64, 80 - k * 46), 40), _p(_red));
    c.drawRRect(env, _p(_white));
    c.drawLine(const Offset(18, 58), const Offset(64, 92), _s(const Color(0xFFB0BEC5), 3));
    c.drawLine(const Offset(110, 58), const Offset(64, 92), _s(const Color(0xFFB0BEC5), 3));
    c.drawCircle(const Offset(64, 92), 7, _p(_pink));
  }

  static void _loveYou(Canvas c, double t) {
    final s = 1 + 0.08 * _wave(t, 2);
    c.save();
    c.translate(64, 64);
    c.scale(s);
    c.rotate(-0.12);
    final tp = TextPainter(
      text: TextSpan(
        text: 'Love\nyou',
        style: TextStyle(
          fontSize: 40,
          height: 0.95,
          fontWeight: FontWeight.w900,
          foreground: Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 8
            ..color = _white,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, Offset(-tp.width / 2, -tp.height / 2));
    final fill = TextPainter(
      text: const TextSpan(
        text: 'Love\nyou',
        style: TextStyle(fontSize: 40, height: 0.95, fontWeight: FontWeight.w900, color: _red),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout();
    fill.paint(c, Offset(-fill.width / 2, -fill.height / 2));
    c.restore();
    for (var n = 0; n < 3; n++) {
      final k = (t + n / 3) % 1;
      c.drawPath(_heart(Offset(18.0 + n * 46, 118 - k * 40), 14), _p(_pink.withValues(alpha: 1 - k)));
    }
  }

  static void _loveCupid(Canvas c, double t) {
    final beat = 1 + 0.08 * math.max(0.0, _wave(t, 2));
    c.drawPath(_heart(const Offset(64, 68), 84 * beat), _p(_red));
    final k = math.min(1.0, t * 2.5);
    final x = -20 + k * 104;
    c.drawLine(Offset(x - 40, 82 - (x - 40) * 0.3 + 10), Offset(x, 82 - x * 0.3 + 10), _s(const Color(0xFF8D6E63), 4));
    final tip = Offset(x, 82 - x * 0.3 + 10);
    c.drawPath(
      Path()
        ..moveTo(tip.dx + 10, tip.dy - 3)
        ..lineTo(tip.dx - 2, tip.dy - 8)
        ..lineTo(tip.dx, tip.dy + 4)
        ..close(),
      _p(_yellow),
    );
  }

  static void _loveMiss(Canvas c, double t) {
    final o = _body(c, dy: 10);
    for (final dx in [-16.0, 16.0]) {
      c.drawArc(Rect.fromCenter(center: o.translate(dx, -2), width: 14, height: 10), math.pi + 0.2, math.pi - 0.4, false, _s(_ink, 4));
    }
    c.drawArc(Rect.fromCenter(center: o.translate(0, 24), width: 18, height: 10), math.pi + 0.3, math.pi - 0.6, false, _s(_ink, 4));
    // a thought of a heart
    c.drawCircle(Offset(o.dx + 30, o.dy - 40), 4, _p(_white));
    c.drawCircle(Offset(o.dx + 38, o.dy - 50), 6, _p(_white));
    c.drawCircle(const Offset(106, 22), 18, _p(_white));
    final b = 1 + 0.15 * math.max(0.0, _wave(t, 2));
    c.drawPath(_heart(const Offset(106, 24), 22 * b), _p(_red));
  }
}
