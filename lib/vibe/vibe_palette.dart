// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/vibe/vibe_glass.dart';
import 'package:flutter/material.dart';

/// Vibe's looks. Only colours change (backgrounds, accent, buttons); the
/// layout stays the same Discord-style, bubble-free chat everywhere.
enum VibeLook {
  /// Discord colours (the default).
  vibe,

  /// Colours from the phone's wallpaper / system theme (Material You,
  /// Android 12+), like Google Messages.
  wallpaper,

  /// Frosted glass over a wallpaper you pick, like Hyprland's HyDE:
  /// colours from the picture ("wallbash") or a classic palette.
  glass,
}

abstract class VibePalette {
  static const discordBlurple = Color(0xFF5865F2);

  /// The look in use (set by the app's ThemeBuilder).
  static VibeLook look = VibeLook.vibe;

  /// The phone's wallpaper colours; null when the phone has none
  /// (Android 11 and older).
  static ColorScheme? wallLight;
  static ColorScheme? wallDark;

  static bool get wallpaperAvailable => wallLight != null || wallDark != null;

  /// The look actually shown (wallpaper falls back to Vibe without colours).
  static VibeLook get effective =>
      look == VibeLook.wallpaper && !wallpaperAvailable ? VibeLook.vibe : look;

  /// True while the Discord colours are used, so the hand-tuned Discord
  /// shades stay exactly as they were.
  static bool get isVibe => effective == VibeLook.vibe;

  /// Frosted glass look (see VibeGlass).
  static bool get isGlass => effective == VibeLook.glass;

  /// App font (the same in every look).
  static String get fontFamily => 'Figtree';

  /// The accent of the current look (buttons, links, ticks, toggles).
  /// Kept up to date by the app (from the active theme).
  static Color accent = discordBlurple;

  /// The colour scheme for [brightness], or null for the Discord one.
  static ColorScheme? scheme(Brightness brightness) {
    switch (effective) {
      case VibeLook.vibe:
        return null;
      case VibeLook.wallpaper:
        final dark = brightness == Brightness.dark;
        final source = (dark ? wallDark : wallLight) ?? wallDark ?? wallLight;
        if (source == null) return null;
        return _fromSeed(source.primary, brightness);
      case VibeLook.glass:
        return VibeGlass.scheme;
    }
  }

  /// A full scheme from one colour. The accent is a mid tone in light and
  /// dark alike (like Discord's blurple), so white text on buttons stays
  /// readable; error red stays Vibe's.
  static ColorScheme _fromSeed(Color seed, Brightness brightness) {
    final light = ColorScheme.fromSeed(seedColor: seed);
    final s = ColorScheme.fromSeed(seedColor: seed, brightness: brightness);
    final dark = brightness == Brightness.dark;
    return s.copyWith(
      primary: light.primary,
      onPrimary: Colors.white,
      inversePrimary: light.primary,
      error: dark ? const Color(0xFFF23F42) : const Color(0xFFD83C3E),
      onError: Colors.white,
      surfaceTint: Colors.transparent,
    );
  }
}
