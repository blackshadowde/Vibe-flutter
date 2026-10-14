// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/vibe/vibe_chat_actions.dart';
import 'package:fluffychat/vibe/vibe_haptics.dart';
import 'package:fluffychat/vibe/vibe_motion.dart';
import 'package:fluffychat/vibe/vibe_settings_style.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

/// Archived chats: hidden from the rail and the chat list, opened only by
/// long-pressing your own picture at the top of the rail.
///
/// Stored as a room tag, so the archive is the same on all your devices.
/// Like Telegram, an archived chat comes back while it has new messages
/// (unless it's muted) and returns to the archive once read.
abstract class VibeArchive {
  static const tag = 'chat.vibe.archived';

  static bool isArchived(Room room) => room.tags.containsKey(tag);

  /// Hidden from Home right now?
  static bool hidden(Room room) =>
      isArchived(room) &&
      !(room.notificationCount > 0 &&
          room.pushRuleState == PushRuleState.notify);

  static Future<void> setArchived(Room room, bool archived) =>
      archived ? room.addTag(tag) : room.removeTag(tag);

  static List<Room> archived(Client client) => client.rooms
      .where(
        (r) =>
            isArchived(r) &&
            !r.isSpace &&
            (r.membership == Membership.join ||
                r.membership == Membership.invite),
      )
      .toList();

  /// The archive, sliding up from the bottom.
  static Future<void> open(
    BuildContext context,
    Client client, {
    required void Function(Room room) onOpen,
  }) {
    VibeHaptics.medium();
    return showVibeSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: VibeSettingsStyle.page(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => _ArchiveSheet(client: client, onOpen: onOpen),
    );
  }
}

class _ArchiveSheet extends StatefulWidget {
  final Client client;
  final void Function(Room room) onOpen;
  const _ArchiveSheet({required this.client, required this.onOpen});

  @override
  State<_ArchiveSheet> createState() => _ArchiveSheetState();
}

class _ArchiveSheetState extends State<_ArchiveSheet> {
  @override
  Widget build(BuildContext context) {
    final rooms = VibeArchive.archived(widget.client);
    final t1 = VibeSettingsStyle.text(context);
    final t2 = VibeSettingsStyle.text2(context);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: Row(
                children: [
                  Icon(Icons.archive, color: t1, size: 22),
                  const SizedBox(width: 10),
                  Text(
                    'Archived chats',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: t1,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: Text(
                'Only you can see this. Long-press a chat here to bring it back.',
                style: TextStyle(fontSize: 13, color: t2),
              ),
            ),
            if (rooms.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
                child: Text(
                  'No archived chats. Long-press a picture in the left rail '
                  'and tap Archive.',
                  style: TextStyle(color: t2),
                ),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(bottom: 16),
                  itemCount: rooms.length,
                  itemBuilder: (context, i) {
                    final r = rooms[i];
                    final name = r.getLocalizedDisplayname(
                      MatrixLocals(L10n.of(context)),
                    );
                    final last = r.lastEvent;
                    return ListTile(
                      leading: Avatar(
                        mxContent: r.avatar,
                        name: name,
                        size: 44,
                        client: r.client,
                      ),
                      title: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: t1,
                          fontWeight: r.isUnread
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                      subtitle: last == null
                          ? null
                          : Text(
                              last.calcLocalizedBodyFallback(
                                MatrixLocals(L10n.of(context)),
                                hideReply: true,
                                withSenderNamePrefix: true,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: t2),
                            ),
                      onTap: () {
                        Navigator.of(context).pop();
                        widget.onOpen(r);
                      },
                      onLongPress: () async {
                        await VibeChatActions.show(
                          context,
                          r,
                          onOpen: () => widget.onOpen(r),
                        );
                        if (mounted) setState(() {});
                      },
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
