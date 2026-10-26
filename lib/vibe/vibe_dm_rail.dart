// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/vibe/vibe_communities.dart';
import 'package:fluffychat/vibe/vibe_groups.dart';
import 'package:fluffychat/vibe/vibe_motion.dart';
import 'package:fluffychat/vibe/vibe_profile_cache.dart';
import 'package:fluffychat/vibe/vibe_typing_pen.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

/// Extreme-left rail: own avatar, round DM avatars, "+" button.
class VibeDmRail extends StatelessWidget {
  final List<Room> rooms;
  final String? selectedId;
  final String? activeRoomId;
  final void Function(Room room) onSelect;
  final VoidCallback onHome;
  final void Function(Room room)? onLongPress;

  /// Long-press your own picture: the hidden archive.
  final VoidCallback? onOwnLongPress;

  /// The "+": opens the start pane (highlighted while it's open).
  final VoidCallback? onAdd;
  final bool addSelected;

  const VibeDmRail({
    required this.rooms,
    required this.selectedId,
    required this.activeRoomId,
    required this.onSelect,
    required this.onHome,
    this.onLongPress,
    this.onOwnLongPress,
    this.onAdd,
    this.addSelected = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final client = Matrix.of(context).client;
    // DMs first, then groups below a line (like Discord's servers).
    final dms = rooms
        .where((r) => !VibeGroups.isGroup(r) && !r.isSpace)
        .toList();
    final groups = rooms.where(VibeGroups.isGroup).toList();
    // communities last, under their own line
    final spaces = rooms.where((r) => r.isSpace).toList();
    final list = [...dms, ...groups, ...spaces];
    final firstGroup = dms.length;
    final firstSpace = dms.length + groups.length;
    final pinnedCount = dms.takeWhile((r) => r.isFavourite).length;
    return Material(
      color: theme.colorScheme.surfaceContainerLowest,
      child: SafeArea(
        right: false,
        child: SizedBox(
          width: 72,
          child: Column(
            children: [
              const SizedBox(height: 10),
              VibeOwnProfileBuilder(
                client: client,
                builder: (context, profile) => GestureDetector(
                  onLongPress: onOwnLongPress,
                  child: Avatar(
                  mxContent: profile?.avatarUrl,
                  name: profile?.displayName ?? client.userID?.localpart,
                  size: 48,
                  client: client,
                  presenceUserId: client.userID,
                  presenceBackgroundColor:
                      theme.colorScheme.surfaceContainerLowest,
                  onTap: onHome,
                ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 20),
                child: Divider(height: 1, color: theme.dividerColor),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.only(bottom: 8),
                  itemCount: list.length + 1,
                  itemBuilder: (context, i) {
                    if (i == list.length) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Center(
                          child: Material(
                            color: addSelected
                                ? theme.colorScheme.primary
                                : theme.colorScheme.surfaceContainerHigh,
                            shape: const CircleBorder(),
                            child: IconButton(
                              icon: Icon(
                                Icons.add,
                                color: addSelected
                                    ? theme.colorScheme.onPrimary
                                    : theme.colorScheme.primary,
                              ),
                              tooltip: 'New chat or group',
                              onPressed:
                                  onAdd ?? () => VibeGroups.showNew(context),
                            ),
                          ),
                        ),
                      );
                    }
                    final room = list[i];
                    final active = room.id == (selectedId ?? activeRoomId);
                    final invited = room.membership == Membership.invite;
                    final unread = room.isSpace
                        ? VibeCommunities.unread(room)
                        : room.notificationCount;
                    final name = room.getLocalizedDisplayname(
                      MatrixLocals(L10n.of(context)),
                    );
                    final tile = Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: GestureDetector(
                        onLongPress: onLongPress == null
                            ? null
                            : () => onLongPress!(room),
                        // (no tooltip: it took the long press away from the
                        // pin / mute / archive menu)
                        behavior: HitTestBehavior.opaque,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Positioned(
                              left: 0,
                              top: 0,
                              bottom: 0,
                              child: Center(
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 260),
                                  curve: Curves.easeOutCubic,
                                  width: 4,
                                  height: active
                                      ? 30
                                      : (unread > 0 ? 8 : 0),
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.onSurface,
                                    borderRadius: const BorderRadius.only(
                                      topRight: Radius.circular(4),
                                      bottomRight: Radius.circular(4),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            VibePressable(
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 280),
                                curve: Curves.easeOutCubic,
                                width: 56,
                                height: 56,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(
                                    active ? 15 : 18,
                                  ),
                                  border: Border.all(
                                    width: 2,
                                    color: active
                                        ? theme.colorScheme.primary
                                        : invited
                                        ? Colors.orange
                                        : Colors.transparent,
                                  ),
                                ),
                                child: TweenAnimationBuilder<double>(
                                  tween: Tween(end: active ? 12.0 : 15.0), // rounded squares, like Vibgram
                                  duration: const Duration(milliseconds: 280),
                                  curve: Curves.easeOutCubic,
                                  builder: (context, r, child) =>
                                      VibeTypingOverlay(
                                        room: room,
                                        ringColor: theme
                                            .colorScheme
                                            .surfaceContainerLowest,
                                        child: Avatar(
                                          mxContent: room.avatar,
                                          name: name,
                                          size: 46,
                                          client: room.client,
                                          borderRadius: BorderRadius.circular(
                                            r,
                                          ),
                                          presenceUserId:
                                              room.directChatMatrixID,
                                          presenceBackgroundColor: theme
                                              .colorScheme
                                              .surfaceContainerLowest,
                                          onTap: () => onSelect(room),
                                        ),
                                      ),
                                ),
                              ),
                            ),
                            if (room.isFavourite)
                              Positioned(
                                bottom: 0,
                                left: 8,
                                child: IgnorePointer(
                                  child: Container(
                                    width: 18,
                                    height: 18,
                                    decoration: BoxDecoration(
                                      color: theme
                                          .colorScheme
                                          .surfaceContainerLowest,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.push_pin,
                                      size: 12,
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ),
                            if (unread > 0)
                              Positioned(
                                top: 0,
                                right: 6,
                                child: IgnorePointer(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 5,
                                    ),
                                    constraints: const BoxConstraints(
                                      minWidth: 18,
                                      minHeight: 18,
                                    ),
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: theme.colorScheme.error,
                                      borderRadius: BorderRadius.circular(9),
                                    ),
                                    child: Text(
                                      '$unread',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: theme.colorScheme.onError,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                    final groupLine =
                        (i == firstGroup && dms.isNotEmpty && groups.isNotEmpty) ||
                        (i == firstSpace && spaces.isNotEmpty && firstSpace > 0);
                    if (groupLine ||
                        (i == pinnedCount && pinnedCount > 0 && i < firstGroup)) {
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: 6,
                              horizontal: 24,
                            ),
                            child: Divider(
                              height: 1,
                              color: theme.dividerColor,
                            ),
                          ),
                          tile,
                        ],
                      );
                    }
                    return tile;
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

}
