// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

/// Floating user card: big round avatar overlapping a pill with name,
/// status, bell and gear.
class VibeUserBar extends StatelessWidget {
  const VibeUserBar({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final client = Matrix.of(context).client;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 6, 12, 10),
        child: SizedBox(
          height: 70,
          child: FutureBuilder<Profile?>(
            future: client.fetchOwnProfile(),
            builder: (context, snapshot) {
              final name =
                  snapshot.data?.displayName ?? client.userID?.localpart ?? '';
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: 30,
                    right: 0,
                    top: 9,
                    bottom: 9,
                    child: Material(
                      color: theme.colorScheme.surfaceContainerHigh,
                      elevation: 8,
                      shadowColor: Colors.black,
                      shape: const StadiumBorder(),
                      child: Padding(
                        padding: const EdgeInsets.only(left: 52, right: 6),
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
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                  const Text(
                                    'Online',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.green,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.notifications_none),
                              onPressed: () =>
                                  context.go('/rooms/settings/notifications'),
                            ),
                            IconButton(
                              icon: const Icon(Icons.settings_outlined),
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
                        mxContent: snapshot.data?.avatarUrl,
                        name: name,
                        size: 64,
                        client: client,
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
