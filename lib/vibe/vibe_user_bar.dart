// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/vibe/vibe_connection.dart';
import 'package:fluffychat/vibe/vibe_own_profile.dart';
import 'package:fluffychat/vibe/vibe_profile_cache.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

/// Full-width floating user card (Discord style): big round avatar
/// overlapping a pill with name, status, bell and gear.
class VibeUserBar extends StatelessWidget {
  const VibeUserBar({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final client = Matrix.of(context).client;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
        child: SizedBox(
          height: 76,
          child: VibeOwnProfileBuilder(
            client: client,
            builder: (context, profile) {
              final name =
                  profile?.displayName ?? client.userID?.localpart ?? '';
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: 34,
                    right: 0,
                    top: 8,
                    bottom: 8,
                    child: Material(
                      color: theme.colorScheme.surfaceContainer,
                      elevation: 6,
                      shadowColor: Colors.black,
                      shape: const StadiumBorder(),
                      child: Padding(
                        padding: const EdgeInsets.only(left: 50, right: 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 16,
                                    ),
                                  ),
                                  VibeConnectionBuilder(
                                    client: client,
                                    builder: (context, conn) => Text(
                                      conn.label,
                                      style: TextStyle(
                                        fontSize: 13,
                                        color:
                                            theme.colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.notifications),
                              color: theme.colorScheme.onSurfaceVariant,
                              onPressed: () =>
                                  context.go('/rooms/settings/notifications'),
                            ),
                            IconButton(
                              icon: const Icon(Icons.settings),
                              color: theme.colorScheme.onSurfaceVariant,
                              onPressed: () => context.go('/rooms/settings'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    top: 0,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: theme.colorScheme.surface,
                      ),
                      child: Avatar(
                        mxContent: profile?.avatarUrl,
                        name: name,
                        size: 64,
                        client: client,
                        onTap: () => VibeOwnProfile.show(context, client),
                        presenceUserId: client.userID,
                        presenceBackgroundColor: theme.colorScheme.surface,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
