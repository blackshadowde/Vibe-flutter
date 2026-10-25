// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';

/// Discord-style colourful names (a colour or a two-colour gradient; emojis
/// can simply be typed into the name).
///
/// The chosen colours travel with the display name, so they work on every
/// Matrix server: after the name come invisible characters (a separator and
/// 48 zero-width 0/1 characters = two RGB colours). Vibe reads them and
/// paints the name; other apps just show the plain name.
@immutable
class VibeNameStyle {
  /// 0xRRGGBB
  final int c1, c2;
  const VibeNameStyle(int first, [int? second])
      : c1 = first,
        c2 = second ?? first;

  static const _sep = '\u2063';
  static const _zero = '\u200b';
  static const _one = '\u200c';
  static const _bits = 48;

  /// Splits a stored display name into the readable name and its style.
  static (String, VibeNameStyle?) split(String raw) {
    final i = raw.lastIndexOf(_sep);
    if (i < 0) return (raw, null);
    final tail = raw.substring(i + 1);
    if (tail.length != _bits) return (raw, null);
    var value = 0;
    var c1 = 0;
    for (var k = 0; k < _bits; k++) {
      final ch = tail[k];
      if (ch != _zero && ch != _one) return (raw, null);
      value = (value << 1) | (ch == _one ? 1 : 0);
      if (k == 23) {
        c1 = value;
        value = 0;
      }
    }
    return (raw.substring(0, i), VibeNameStyle(c1, value));
  }

  /// The name as stored on the server: [plain] plus the style, if any.
  static String compose(String plain, VibeNameStyle? style) {
    if (style == null) return plain;
    final b = StringBuffer(plain)..write(_sep);
    for (final c in [style.c1, style.c2]) {
      for (var k = 23; k >= 0; k--) {
        b.write(((c >> k) & 1) == 1 ? _one : _zero);
      }
    }
    return b.toString();
  }

  /// The name with the style bits removed.
  static String plain(String raw) => split(raw).$1;

  @override
  bool operator ==(Object other) =>
      other is VibeNameStyle && other.c1 == c1 && other.c2 == c2;

  @override
  int get hashCode => Object.hash(c1, c2);

  /// Ready-made styles to pick from.
  static const presets = <VibeNameStyle>[
    VibeNameStyle(0xED4245), // red
    VibeNameStyle(0xF0883E), // orange
    VibeNameStyle(0xFEE75C), // yellow
    VibeNameStyle(0x23A55A), // green
    VibeNameStyle(0x00B0F4), // cyan
    VibeNameStyle(0x5865F2), // blurple
    VibeNameStyle(0xEB459E), // pink
    VibeNameStyle(0xFF512F, 0xF09819), // sunset
    VibeNameStyle(0x2193B0, 0x6DD5ED), // ocean
    VibeNameStyle(0x11998E, 0x38EF7D), // mint
    VibeNameStyle(0xF953C6, 0x5865F2), // neon
    VibeNameStyle(0xFC466B, 0x3F5EFB), // dusk
  ];

  Color _at(double t) {
    int ch(int shift) {
      final a = (c1 >> shift) & 0xFF, b = (c2 >> shift) & 0xFF;
      return (a + (b - a) * t).round().clamp(0, 255);
    }

    return Color.fromARGB(0xFF, ch(16), ch(8), ch(0));
  }

  /// The name painted letter by letter (emojis keep their own colours).
  TextSpan span(String text, TextStyle base) {
    final chars = text.characters.toList();
    final n = chars.length;
    return TextSpan(
      style: base,
      children: [
        for (var i = 0; i < n; i++)
          TextSpan(
            text: chars[i],
            style: TextStyle(color: _at(n <= 1 ? 0 : i / (n - 1))),
          ),
      ],
    );
  }
}

/// A name that is painted with its style when it has one, and is a plain
/// [Text] exactly as before when it has none.
class VibeNameText extends StatelessWidget {
  final String name;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;
  const VibeNameText(
    this.name, {
    this.style,
    this.maxLines,
    this.overflow,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final (plain, s) = VibeNameStyle.split(name);
    if (s == null) {
      return Text(name, style: style, maxLines: maxLines, overflow: overflow);
    }
    final base = DefaultTextStyle.of(context).style.merge(style);
    return Text.rich(
      s.span(plain, base),
      maxLines: maxLines,
      overflow: overflow,
    );
  }
}
