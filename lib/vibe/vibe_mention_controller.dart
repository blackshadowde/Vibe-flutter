// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';

/// Text box controller that shows mentions (`@[Name]`, how the text is
/// sent) as a highlighted `@Name`, like the mention pill in messages. The
/// brackets stay in the text, just invisible.
class VibeMentionController extends TextEditingController {
  static final _mention = RegExp(r'@\[[^\]\n]+\]');

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final text = this.text;
    if (!text.contains('@[')) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }
    final accent = Theme.of(context).colorScheme.primary;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final pill = (style ?? const TextStyle()).copyWith(
      color: dark
          ? Color.lerp(accent, Colors.white, 0.35)
          : Color.lerp(accent, Colors.black, 0.15),
      backgroundColor: accent.withValues(alpha: 0.18),
      fontWeight: FontWeight.w600,
    );
    final hidden = pill.copyWith(
      color: Colors.transparent,
      fontSize: 0.1,
      letterSpacing: 0,
    );
    final spans = <InlineSpan>[];
    var last = 0;
    for (final m in _mention.allMatches(text)) {
      if (m.start > last) {
        spans.add(TextSpan(text: text.substring(last, m.start)));
      }
      final s = m.group(0)!;
      spans
        ..add(TextSpan(text: '@', style: pill))
        ..add(TextSpan(text: '[', style: hidden))
        ..add(TextSpan(text: s.substring(2, s.length - 1), style: pill))
        ..add(TextSpan(text: ']', style: hidden));
      last = m.end;
    }
    if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
    return TextSpan(style: style, children: spans);
  }
}
