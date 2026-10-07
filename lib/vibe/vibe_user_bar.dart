// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

/// Bottom card of the middle pane: own avatar, name, status, bell, gear.
class VibeUserBar extends StatelessWidget {
  const VibeUserBar({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final client = Matrix.of(context).client;
    return Material(
      color: theme.colorScheme.surfaceContainerLowest,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
          child: FutureBuilder<Profile?>(
            future: client.fetchOwnProfile(),
            builder: (context, snapshot) {
              final name =
                  snapshot.data?.displayName ?? client.userID?.localpart ?? '';
              return Row(
                children: [
                  Avatar(
                    mxContent: snapshot.data?.avatarUrl,
                    name: name,
                    size: 40,
                    client: client,
                    presenceUserId: client.userID,
                    presenceBackgroundColor:
                        theme.colorScheme.surfaceContainerLowest,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'Online',
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.notifications_none),
                    onPressed: () => context.go('/rooms/settings/notifications'),
                  ),
                  IconButton(
                    icon: const Icon(Icons.settings_outlined),
                    onPressed: () => context.go('/rooms/settings'),
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
