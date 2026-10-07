// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/pages/chat_list/chat_list.dart';
import 'package:fluffychat/utils/stream_extension.dart';
import 'package:fluffychat/vibe/vibe_dm_pane.dart';
import 'package:fluffychat/vibe/vibe_dm_rail.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

/// Discord-style home: [rail of DM avatars] | [middle pane].
class VibeHomeView extends StatelessWidget {
  final ChatListController controller;
  const VibeHomeView(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final client = Matrix.of(context).client;
    return StreamBuilder(
      key: ValueKey(client.userID.toString()),
      stream: client.onSync.stream
          .where((s) => s.hasRoomUpdate)
          .rateLimit(const Duration(seconds: 1)),
      builder: (context, _) {
        final rooms = client.rooms
            .where(
              (r) =>
                  !r.isSpace &&
                  (r.membership == Membership.join ||
                      r.membership == Membership.invite),
            )
            .toList();
        return Row(
          children: [
            VibeDmRail(
              rooms: rooms.where((r) => r.membership == Membership.join).toList(),
              activeRoomId: controller.activeChat,
              onTap: controller.onChatTap,
            ),
            Expanded(
              child: VibeDmPane(
                rooms: rooms,
                activeRoomId: controller.activeChat,
                onTap: controller.onChatTap,
              ),
            ),
          ],
        );
      },
    );
  }
}
