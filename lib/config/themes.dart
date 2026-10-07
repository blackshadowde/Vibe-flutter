// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/app_config.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

abstract class FluffyThemes {
  static const double columnWidth = 380.0;

  static const double maxTimelineWidth = columnWidth * 2;

  static const double navRailWidth = 80.0;

  static bool isColumnModeByWidth(double width) =>
      width > columnWidth * 2 + navRailWidth;

  static bool isColumnMode(BuildContext context) =>
      isColumnModeByWidth(MediaQuery.sizeOf(context).width);

  static bool isThreeColumnMode(BuildContext context) =>
      MediaQuery.sizeOf(context).width > FluffyThemes.columnWidth * 3.5;

  static LinearGradient backgroundGradient(BuildContext context, int alpha) {
    final colorScheme = Theme.of(context).colorScheme;
    return LinearGradient(
      begin: Alignment.topCenter,
      colors: [
        colorScheme.primaryContainer.withAlpha(alpha),
        colorScheme.secondaryContainer.withAlpha(alpha),
        colorScheme.tertiaryContainer.withAlpha(alpha),
        colorScheme.primaryContainer.withAlpha(alpha),
      ],
    );
  }

  static const Duration animationDuration = Duration(milliseconds: 250);
  static const Curve animationCurve = Curves.easeInOut;

  static ThemeData buildTheme(
    BuildContext context,
    Brightness brightness, [
    Color? seed,
  ]) {
    // Vibe: Discord palette (no generated accent colours)
    final colorScheme = brightness == Brightness.dark
        ? const ColorScheme(
            brightness: Brightness.dark,
            primary: Color(0xFF5865F2),
            onPrimary: Color(0xFFFFFFFF),
            primaryContainer: Color(0xFF3C45A5),
            onPrimaryContainer: Color(0xFFE0E3FF),
            secondary: Color(0xFFB5BAC1),
            onSecondary: Color(0xFF1A191E),
            secondaryContainer: Color(0xFF2E2D33),
            onSecondaryContainer: Color(0xFFF2F3F5),
            tertiary: Color(0xFF949BA4),
            onTertiary: Color(0xFF1A191E),
            tertiaryContainer: Color(0xFF29282D),
            onTertiaryContainer: Color(0xFFF2F3F5),
            error: Color(0xFFF23F42),
            onError: Color(0xFFFFFFFF),
            errorContainer: Color(0xFF5A1D1E),
            onErrorContainer: Color(0xFFFFDAD9),
            surface: Color(0xFF1A191E),
            onSurface: Color(0xFFF2F3F5),
            surfaceContainerLowest: Color(0xFF121214),
            surfaceContainerLow: Color(0xFF1E1D22),
            surfaceContainer: Color(0xFF252429),
            surfaceContainerHigh: Color(0xFF29282D),
            surfaceContainerHighest: Color(0xFF323136),
            onSurfaceVariant: Color(0xFFB5BAC1),
            outline: Color(0xFF6D6F78),
            outlineVariant: Color(0xFF3A393F),
            inverseSurface: Color(0xFFF2F3F5),
            onInverseSurface: Color(0xFF1A191E),
            inversePrimary: Color(0xFF5865F2),
            shadow: Color(0xFF000000),
            scrim: Color(0xFF000000),
            surfaceTint: Color(0x00000000),
          )
        : const ColorScheme(
            brightness: Brightness.light,
            primary: Color(0xFF5865F2),
            onPrimary: Color(0xFFFFFFFF),
            primaryContainer: Color(0xFFE0E3FF),
            onPrimaryContainer: Color(0xFF1E2370),
            secondary: Color(0xFF5C5E66),
            onSecondary: Color(0xFFFFFFFF),
            secondaryContainer: Color(0xFFE3E5E8),
            onSecondaryContainer: Color(0xFF313338),
            tertiary: Color(0xFF80848E),
            onTertiary: Color(0xFFFFFFFF),
            tertiaryContainer: Color(0xFFF2F3F5),
            onTertiaryContainer: Color(0xFF313338),
            error: Color(0xFFD83C3E),
            onError: Color(0xFFFFFFFF),
            errorContainer: Color(0xFFFFDAD9),
            onErrorContainer: Color(0xFF5A1D1E),
            surface: Color(0xFFFFFFFF),
            onSurface: Color(0xFF313338),
            surfaceContainerLowest: Color(0xFFE3E5E8),
            surfaceContainerLow: Color(0xFFF7F7F8),
            surfaceContainer: Color(0xFFF2F3F5),
            surfaceContainerHigh: Color(0xFFEBEDEF),
            surfaceContainerHighest: Color(0xFFE3E5E8),
            onSurfaceVariant: Color(0xFF5C5E66),
            outline: Color(0xFF80848E),
            outlineVariant: Color(0xFFD8D9DC),
            inverseSurface: Color(0xFF313338),
            onInverseSurface: Color(0xFFF2F3F5),
            inversePrimary: Color(0xFF5865F2),
            shadow: Color(0xFF000000),
            scrim: Color(0xFF000000),
            surfaceTint: Color(0x00000000),
          );
    final isColumnMode = FluffyThemes.isColumnMode(context);
    final dividerColor = brightness == Brightness.dark
        ? colorScheme.surfaceContainerHighest
        : colorScheme.surfaceContainer;
    return ThemeData(
      visualDensity: VisualDensity.standard,
      useMaterial3: true,
      fontFamily: 'GGSans',
      brightness: brightness,
      colorScheme: colorScheme,
      dividerColor: dividerColor,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.linux: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
        },
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          iconColor: colorScheme.onSurface,
          disabledIconColor: colorScheme.onSurface,
        ),
      ),
      textSelectionTheme: TextSelectionThemeData(
        selectionColor: colorScheme.onSurface.withAlpha(128),
        selectionHandleColor: colorScheme.secondary,
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConfig.borderRadius / 2),
        ),
        contentPadding: const EdgeInsets.all(12),
      ),
      chipTheme: ChipThemeData(
        showCheckmark: false,
        backgroundColor: colorScheme.surfaceContainer,
        side: BorderSide.none,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConfig.borderRadius),
        ),
      ),
      appBarTheme: AppBarTheme(
        toolbarHeight: isColumnMode ? 72 : 56,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        backgroundColor: colorScheme.surface,
        actionsPadding: isColumnMode
            ? const EdgeInsets.symmetric(horizontal: 16.0)
            : null,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: brightness.reversed,
          statusBarBrightness: brightness,
          systemNavigationBarIconBrightness: brightness.reversed,
          systemNavigationBarColor: colorScheme.surface,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          side: BorderSide(width: 1, color: colorScheme.primary),
          shape: RoundedRectangleBorder(
            side: BorderSide(color: colorScheme.primary),
            borderRadius: BorderRadius.circular(AppConfig.borderRadius / 2),
          ),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        strokeCap: StrokeCap.round,
        color: colorScheme.primary,
        refreshBackgroundColor: colorScheme.primaryContainer,
      ),
      snackBarTheme: isColumnMode
          ? const SnackBarThemeData(
              showCloseIcon: true,
              behavior: SnackBarBehavior.floating,
              width: FluffyThemes.columnWidth * 1.5,
            )
          : const SnackBarThemeData(behavior: SnackBarBehavior.floating),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colorScheme.secondaryContainer,
          foregroundColor: colorScheme.onSecondaryContainer,
          elevation: 0,
          padding: const EdgeInsets.all(16),
          textStyle: const TextStyle(fontSize: 16),
        ),
      ),
    );
  }
}

extension on Brightness {
  Brightness get reversed =>
      this == Brightness.dark ? Brightness.light : Brightness.dark;
}

extension BubbleColorTheme on ThemeData {
  Color get bubbleColor => brightness == Brightness.light
      ? colorScheme.primary
      : colorScheme.primaryContainer;

  Color get onBubbleColor => brightness == Brightness.light
      ? colorScheme.onPrimary
      : colorScheme.onPrimaryContainer;

  Color get secondaryBubbleColor => HSLColor.fromColor(
    brightness == Brightness.light
        ? colorScheme.tertiary
        : colorScheme.tertiaryContainer,
  ).withSaturation(0.5).toColor();
}
