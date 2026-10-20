// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';

/// Vibe's looks. Only colours change (backgrounds, accent, buttons); the
/// layout stays the same Discord-style, bubble-free chat everywhere.
enum VibeLook {
  /// Discord colours (the default).
  vibe,

  /// Colours from the phone's wallpaper / system theme (Material You,
  /// Android 12+), like Google Messages.
  wallpaper,

  /// Dark blue-grey with a teal accent, inspired by Parrot OS.
  parrot,
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
      case VibeLook.parrot:
        return brightness == Brightness.dark ? _parrotDark : _parrotLight;
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

  static const _parrotDark = ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFF0097A7),
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFF00474F),
    onPrimaryContainer: Color(0xFFA6F2FA),
    secondary: Color(0xFF8FA3B5),
    onSecondary: Color(0xFF0D1117),
    secondaryContainer: Color(0xFF1E2A36),
    onSecondaryContainer: Color(0xFFD6E4EF),
    tertiary: Color(0xFFA6E22E),
    onTertiary: Color(0xFF14200A),
    tertiaryContainer: Color(0xFF2E3D14),
    onTertiaryContainer: Color(0xFFD7F7A0),
    error: Color(0xFFF23F42),
    onError: Color(0xFFFFFFFF),
    errorContainer: Color(0xFF5A1D1E),
    onErrorContainer: Color(0xFFFFDAD9),
    surface: Color(0xFF0D1117),
    onSurface: Color(0xFFDCE6EE),
    surfaceContainerLowest: Color(0xFF070A0F),
    surfaceContainerLow: Color(0xFF111822),
    surfaceContainer: Color(0xFF16202B),
    surfaceContainerHigh: Color(0xFF1B2733),
    surfaceContainerHighest: Color(0xFF223040),
    onSurfaceVariant: Color(0xFF8FA3B5),
    outline: Color(0xFF5B6B7A),
    outlineVariant: Color(0xFF26323E),
    inverseSurface: Color(0xFFDCE6EE),
    onInverseSurface: Color(0xFF0D1117),
    inversePrimary: Color(0xFF0097A7),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    surfaceTint: Color(0x00000000),
  );

  static const _parrotLight = ColorScheme(
    brightness: Brightness.light,
    primary: Color(0xFF00838F),
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFFB2EBF2),
    onPrimaryContainer: Color(0xFF00363C),
    secondary: Color(0xFF4F6070),
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: Color(0xFFDDE7EF),
    onSecondaryContainer: Color(0xFF16222D),
    tertiary: Color(0xFF5C8A00),
    onTertiary: Color(0xFFFFFFFF),
    tertiaryContainer: Color(0xFFDDF5B0),
    onTertiaryContainer: Color(0xFF1A2A00),
    error: Color(0xFFD83C3E),
    onError: Color(0xFFFFFFFF),
    errorContainer: Color(0xFFFFDAD9),
    onErrorContainer: Color(0xFF5A1D1E),
    surface: Color(0xFFF7FAFC),
    onSurface: Color(0xFF16202B),
    surfaceContainerLowest: Color(0xFFFFFFFF),
    surfaceContainerLow: Color(0xFFF0F4F7),
    surfaceContainer: Color(0xFFE9EEF2),
    surfaceContainerHigh: Color(0xFFE2E8ED),
    surfaceContainerHighest: Color(0xFFDAE1E7),
    onSurfaceVariant: Color(0xFF4F6070),
    outline: Color(0xFF7D8C99),
    outlineVariant: Color(0xFFCBD4DB),
    inverseSurface: Color(0xFF16202B),
    onInverseSurface: Color(0xFFF0F4F7),
    inversePrimary: Color(0xFF4DD0E1),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    surfaceTint: Color(0x00000000),
  );
}
