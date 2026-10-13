// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/vibe/vibe_connection.dart';
import 'package:fluffychat/widgets/mxc_image.dart';
import 'package:fluffychat/widgets/presence_builder.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

class Avatar extends StatelessWidget {
  final Uri? mxContent;
  final String? name;
  final double size;
  final void Function()? onTap;
  static const double defaultSize = 48;
  final Client? client;
  final String? presenceUserId;
  final Color? presenceBackgroundColor;
  final BorderRadius? borderRadius;
  final IconData? icon;
  final ShapeBorder? shapeBorder;
  final Color? backgroundColor;
  final Color? textColor;

  const Avatar({
    this.mxContent,
    this.name,
    this.size = defaultSize,
    this.onTap,
    this.client,
    this.presenceUserId,
    this.presenceBackgroundColor,
    this.borderRadius,
    this.shapeBorder,
    this.icon,
    this.backgroundColor,
    this.textColor,
    super.key,
  });

  String _calcFallbackLetters() {
    final name = this.name?.trim();
    if (name == null || name.isEmpty) return '@';
    final words = name.split(' ');
    if (words.length <= 1) return name.substring(0, 1);
    return '${words.first.substring(0, 1)}${words.last.substring(0, 1)}';
  }

  Widget _dot(ThemeData theme, Color dotColor) {
    final ring = presenceBackgroundColor ?? theme.colorScheme.surface;
    return Positioned(
      bottom: -3,
      right: -3,
      child: Container(
        width: 16,
        height: 16,
        decoration: BoxDecoration(
          color: ring,
          borderRadius: BorderRadius.circular(32),
        ),
        alignment: Alignment.center,
        child: Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: dotColor,
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final fallbackLetters = _calcFallbackLetters();

    final noPic =
        mxContent == null ||
        mxContent.toString().isEmpty ||
        mxContent.toString() == 'null';
    // Round everywhere; a custom radius (the DM rail) gets a rounded square.
    final borderRadius = this.borderRadius ?? BorderRadius.circular(size / 2);
    final ShapeBorder shape =
        shapeBorder ??
        (this.borderRadius == null
            ? const CircleBorder()
            : RoundedRectangleBorder(borderRadius: borderRadius));
    // Vibgram-style placeholder: plain grey with white initials.
    final dark = theme.brightness == Brightness.dark;
    final grey = dark ? const Color(0xFF4E5058) : const Color(0xFFA4A9B1);
    final presenceUserId = this.presenceUserId;
    final container = Stack(
      children: [
        SizedBox(
          width: size,
          height: size,
          child: Material(
            color: theme.brightness == Brightness.light
                ? Colors.white
                : Colors.black,
            shape: shape,
            clipBehavior: Clip.antiAlias,
            child: MxcImage(
              client: client,
              borderRadius: borderRadius,
              key: ValueKey(mxContent.toString()),
              cacheKey: '${mxContent}_$size',
              uri: mxContent,
              fit: BoxFit.cover,
              width: size,
              height: size,
              placeholder: (_) => Container(
                color: backgroundColor ?? grey,
                alignment: Alignment.center,
                child: noPic
                    ? Text(
                        fallbackLetters.toUpperCase(),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: textColor ?? Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: (size / 2.4).roundToDouble(),
                          height: 1,
                        ),
                      )
                    : null,
              ),
            ),
          ),
        ),
        if (presenceUserId != null)
          if (client != null && presenceUserId == client!.userID)
            VibeConnectionBuilder(
              client: client!,
              builder: (context, conn) =>
                  _dot(theme, conn.color),
            )
          else
            PresenceBuilder(
              client: client,
              userId: presenceUserId,
              builder: (context, presence) {
                final dotColor = presence == null
                    ? vibeDotGrey
                    : presence.presence.isOnline
                    ? vibeDotGreen
                    : presence.presence.isUnavailable
                    ? vibeDotOrange
                    : vibeDotGrey;
                return _dot(theme, dotColor);
              },
            ),
      ],
    );
    if (onTap == null) return container;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(onTap: onTap, child: container),
    );
  }
}
