// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

/// Extreme-left rail: own avatar, round DM avatars, "+" button.
class VibeDmRail extends StatelessWidget {
  final List<Room> rooms;
  final String? selectedId;
  final String? activeRoomId;
  final void Function(Room room) onSelect;
  final VoidCallback onHome;

  const VibeDmRail({
    required this.rooms,
    required this.selectedId,
    required this.activeRoomId,
    required this.onSelect,
    required this.onHome,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final client = Matrix.of(context).client;
    return Material(
      color: theme.colorScheme.surfaceContainerLowest,
      child: SafeArea(
        right: false,
        child: SizedBox(
          width: 72,
          child: Column(
            children: [
              const SizedBox(height: 10),
              FutureBuilder<Profile?>(
                future: client.fetchOwnProfile(),
                builder: (context, snapshot) => Avatar(
                  mxContent: snapshot.data?.avatarUrl,
                  name: snapshot.data?.displayName ?? client.userID?.localpart,
                  size: 48,
                  client: client,
                  onTap: onHome,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 20),
                child: Divider(height: 1, color: theme.dividerColor),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.only(bottom: 8),
                  itemCount: rooms.length + 1,
                  itemBuilder: (context, i) {
                    if (i == rooms.length) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Center(
                          child: Material(
                            color: theme.colorScheme.surfaceContainerHigh,
                            shape: const CircleBorder(),
                            child: IconButton(
                              icon: Icon(
                                Icons.add,
                                color: theme.colorScheme.primary,
                              ),
                              tooltip: L10n.of(context).newChat,
                              onPressed: () =>
                                  context.go('/rooms/newprivatechat'),
                            ),
                          ),
                        ),
                      );
                    }
                    final room = rooms[i];
                    final active = room.id == (selectedId ?? activeRoomId);
                    final invited = room.membership == Membership.invite;
                    final name = room.getLocalizedDisplayname(
                      MatrixLocals(L10n.of(context)),
                    );
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Tooltip(
                        message: name,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            AnimatedContainer(
                              duration: FluffyThemes.animationDuration,
                              width: 56,
                              height: 56,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  width: 2,
                                  color: active
                                      ? theme.colorScheme.primary
                                      : invited
                                      ? Colors.orange
                                      : Colors.transparent,
                                ),
                              ),
                              child: Avatar(
                                mxContent: room.avatar,
                                name: name,
                                size: 46,
                                client: room.client,
                                presenceUserId: room.directChatMatrixID,
                                presenceBackgroundColor:
                                    theme.colorScheme.surfaceContainerLowest,
                                onTap: () => onSelect(room),
                              ),
                            ),
                            if (room.notificationCount > 0)
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
                                      '${room.notificationCount}',
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
