// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:vibe/vibe/vibe_mute.dart';
import 'package:vibe/config/setting_keys.dart';
import 'package:vibe/config/themes.dart';
import 'package:vibe/l10n/l10n.dart';
import 'package:vibe/pages/chat/chat.dart';
import 'package:vibe/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:vibe/utils/sync_status_localization.dart';
import 'package:vibe/vibe/vibe_connection.dart';
import 'package:vibe/vibe/vibe_status.dart';
import 'package:vibe/vibe/vibe_typing_pen.dart';
import 'package:vibe/vibe/vibe_user_sheet.dart';
import 'package:vibe/widgets/avatar.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

class ChatAppBarTitle extends StatelessWidget {
  final ChatController controller;
  const ChatAppBarTitle(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final room = controller.room;
    if (controller.selectedEvents.isNotEmpty) {
      return Text(
        controller.selectedEvents.length.toString(),
        style: TextStyle(
          color: Theme.of(context).colorScheme.onTertiaryContainer,
        ),
      );
    }
    final name = room.getLocalizedDisplayname(MatrixLocals(L10n.of(context)));
    final dmUser = room.directChatMatrixID;
    return Row(
      children: [
        VibeTypingOverlay(
          room: room,
          child: VibeMuteBadge(
          room: room,
          child: Avatar(
          mxContent: room.avatar,
          name: name,
          size: 40,
          client: room.client,
          presenceUserId: dmUser,
          onTap: controller.isArchived
              ? null
              : () {
                  if (dmUser != null) {
                    VibeUserSheet.show(
                      context,
                      client: room.client,
                      userId: dmUser,
                      displayName: name,
                      avatarUrl: room.avatar,
                      currentRoomId: room.id,
                    );
                  } else {
                    context.go('/rooms/${room.id}/details');
                  }
                },
        ),
        ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: InkWell(
            hoverColor: Colors.transparent,
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
            onTap: controller.isArchived
                ? null
                : () => FluffyThemes.isThreeColumnMode(context)
                      ? controller.toggleDisplayChatDetailsColumn()
                      : context.go('/rooms/${room.id}/details'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (dmUser != null && !AppSettings.vibeStatusBubble.value)
                  VibeStatusLine(room: room, userId: dmUser),
                StreamBuilder(
                  stream: room.client.onSyncStatus.stream,
                  builder: (context, snapshot) {
                    final status =
                        room.client.onSyncStatus.value ??
                        const SyncStatusUpdate(SyncStatus.waitingForResponse);
                    final syncing =
                        !(room.client.onSync.value != null &&
                            status.status != SyncStatus.error &&
                            room.client.prevBatch != null);
                    // connecting: •-•-• with a running light; connected:
                    // the dots turn green, then their local time comes back
                    return VibeConnectBar(
                      syncing: syncing,
                      label: status.calcLocalizedString(context),
                      idle: dmUser != null &&
                              AppSettings.vibeStatusBubble.value
                          ? VibeTheirTime(room: room, userId: dmUser)
                          : const SizedBox.shrink(),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
