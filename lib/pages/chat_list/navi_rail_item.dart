// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:badges/badges.dart';
import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/widgets/hover_builder.dart';
import 'package:fluffychat/widgets/unread_rooms_badge.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import '../../config/themes.dart';

class NaviRailItem extends StatelessWidget {
  final String toolTip;
  final bool isSelected;
  final void Function() onTap;
  final Widget icon;
  final Widget? selectedIcon;
  final bool Function(Room)? unreadBadgeFilter;

  const NaviRailItem({
    required this.toolTip,
    required this.isSelected,
    required this.onTap,
    required this.icon,
    this.selectedIcon,
    this.unreadBadgeFilter,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final icon = isSelected ? selectedIcon ?? this.icon : this.icon;
    final unreadBadgeFilter = this.unreadBadgeFilter;

    return HoverBuilder(
      builder: (context, hovered) {
        return SizedBox(
          height: 64,
          width: FluffyThemes.navRailWidth,
          child: Stack(
            children: [
              Center(
                child: AnimatedScale(
                  scale: hovered ? 1.05 : 1.0,
                  duration: FluffyThemes.animationDuration,
                  curve: FluffyThemes.animationCurve,
                  child: Material(
                    color: isSelected
                        ? const Color(0xFF5865F2)
                        : Colors.transparent,
                    shape: const CircleBorder(),
                    clipBehavior: Clip.antiAlias,
                    child: Tooltip(
                      message: toolTip,
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: onTap,
                        child: unreadBadgeFilter == null
                            ? icon
                            : UnreadRoomsBadge(
                                filter: unreadBadgeFilter,
                                badgePosition: BadgePosition.topEnd(
                                  top: -12,
                                  end: -8,
                                ),
                                child: icon,
                              ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
