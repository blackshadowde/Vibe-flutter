// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/vibe/vibe_haptics.dart';
import 'package:fluffychat/vibe/vibe_lock.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

/// Long-press sheet for a DM (rail avatar or DM row): pin, open, mark read.
/// Pinning uses Matrix's m.favourite tag, so it syncs to all your devices.
abstract class VibeChatActions {
  static Future<void> show(
    BuildContext context,
    Room room, {
    required VoidCallback onOpen,
  }) async {
    VibeHaptics.medium();
    final cs = Theme.of(context).colorScheme;
    final name = room.getLocalizedDisplayname(MatrixLocals(L10n.of(context)));
    final pinned = room.isFavourite;
    final messenger = ScaffoldMessenger.of(context);
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      backgroundColor: cs.surfaceContainerLow,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Avatar(
                mxContent: room.avatar,
                name: name,
                size: 40,
                client: room.client,
              ),
              title: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: Icon(
                pinned ? Icons.push_pin : Icons.push_pin_outlined,
              ),
              title: Text(pinned ? 'Unpin chat' : 'Pin chat'),
              onTap: () => Navigator.pop(ctx, 'pin'),
            ),
            ListTile(
              leading: const Icon(Icons.chat_bubble_outline),
              title: const Text('Open chat'),
              onTap: () => Navigator.pop(ctx, 'open'),
            ),
            ListTile(
              leading: Icon(
                VibeLock.isLocked(room.id)
                    ? Icons.lock_open_outlined
                    : Icons.lock_outline,
              ),
              title: Text(
                VibeLock.isLocked(room.id) ? 'Unlock chat' : 'Lock chat',
              ),
              subtitle: VibeLock.isLocked(room.id)
                  ? null
                  : const Text('Hide it behind your fingerprint'),
              onTap: () => Navigator.pop(ctx, 'lock'),
            ),
            if (room.isUnread)
              ListTile(
                leading: const Icon(Icons.mark_chat_read_outlined),
                title: const Text('Mark as read'),
                onTap: () => Navigator.pop(ctx, 'read'),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    try {
      switch (action) {
        case 'pin':
          await room.setFavourite(!pinned);
          VibeHaptics.light();
          messenger.showSnackBar(
            SnackBar(
              content: Text(pinned ? 'Unpinned $name' : 'Pinned $name'),
              duration: const Duration(seconds: 2),
            ),
          );
        case 'open':
          onOpen();
        case 'lock':
          if (context.mounted) await VibeLock.toggle(context, room);
        case 'read':
          final last = room.lastEvent;
          if (room.markedUnread) await room.markUnread(false);
          if (last != null) {
            await room.setReadMarker(last.eventId, mRead: last.eventId);
          }
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  /// Pinned chats first; otherwise keep the existing order.
  static List<Room> pinnedFirst(List<Room> rooms) => [
    ...rooms.where((r) => r.isFavourite),
    ...rooms.where((r) => !r.isFavourite),
  ];
}
