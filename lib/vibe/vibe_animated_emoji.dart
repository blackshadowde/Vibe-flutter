// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/vibe/vibe_low_data.dart';
import 'package:flutter/material.dart';

/// Google's Noto Animated Emoji (CC BY 4.0): every emoji has its own
/// animation (a laughing face rocks, fire flickers, a heart beats…).
/// Loaded from Google Fonts and cached; shows the normal emoji while
/// loading, when an emoji has no animation, offline, or in Low data mode.
class VibeAnimatedEmoji extends StatefulWidget {
  final String emoji;
  final double size;
  const VibeAnimatedEmoji(this.emoji, {this.size = 32, super.key});

  /// Noto's file name: code points in lowercase hex joined by "_".
  static String code(String emoji) =>
      emoji.runes.map((r) => r.toRadixString(16)).join('_');

  static String url(String code) =>
      'https://fonts.gstatic.com/s/e/notoemoji/latest/$code/512.webp';

  @override
  State<VibeAnimatedEmoji> createState() => _VibeAnimatedEmojiState();
}

class _VibeAnimatedEmojiState extends State<VibeAnimatedEmoji> {
  late List<String> _codes = _candidates();
  int _try = 0;

  List<String> _candidates() {
    final full = VibeAnimatedEmoji.code(widget.emoji);
    final bare = full.replaceAll('_fe0f', '');
    return {full, bare}.toList();
  }

  @override
  void didUpdateWidget(VibeAnimatedEmoji old) {
    super.didUpdateWidget(old);
    if (old.emoji != widget.emoji) {
      _codes = _candidates();
      _try = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final plain = SizedBox(
      width: widget.size,
      height: widget.size,
      child: Center(
        child: Text(
          widget.emoji,
          style: TextStyle(fontSize: widget.size * 0.78, height: 1),
        ),
      ),
    );
    if (VibeLowData.on || _try >= _codes.length) return plain;
    return Image.network(
      VibeAnimatedEmoji.url(_codes[_try]),
      key: ValueKey(_codes[_try]),
      width: widget.size,
      height: widget.size,
      filterQuality: FilterQuality.medium,
      gaplessPlayback: true,
      frameBuilder: (context, child, frame, sync) =>
          frame == null && !sync ? plain : child,
      errorBuilder: (_, _, _) {
        // Try the other spelling once, then settle on the plain emoji.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _try < _codes.length) setState(() => _try++);
        });
        return plain;
      },
    );
  }
}
