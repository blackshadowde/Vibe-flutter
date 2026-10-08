// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/chat.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/utils/sync_status_localization.dart';
import 'package:fluffychat/vibe/vibe_status.dart';
import 'package:fluffychat/vibe/vibe_typing_pen.dart';
import 'package:fluffychat/vibe/vibe_user_sheet.dart';
import 'package:fluffychat/widgets/avatar.dart';
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
          child:Avatar(
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
                if (dmUser != null)
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
                    if (!syncing) return const SizedBox.shrink();
                    return Row(
                      children: [
                        SizedBox.square(
                          dimension: 10,
                          child: CircularProgressIndicator.adaptive(
                            strokeWidth: 1,
                            value: status.progress,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            status.calcLocalizedString(context),
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
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
