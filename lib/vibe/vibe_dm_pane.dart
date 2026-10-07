// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat_list/unread_bubble.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/vibe/vibe_add_contact.dart';
import 'package:fluffychat/vibe/vibe_shared_page.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

/// Middle pane: search, starred, DM list, invites, user card.
class VibeDmPane extends StatefulWidget {
  final List<Room> rooms;
  final String? activeRoomId;
  final void Function(Room room) onTap;
  final void Function(Room room) onOpen;

  const VibeDmPane({
    required this.rooms,
    required this.activeRoomId,
    required this.onTap,
    required this.onOpen,
    super.key,
  });

  @override
  State<VibeDmPane> createState() => _VibeDmPaneState();
}

class _VibeDmPaneState extends State<VibeDmPane> {
  final TextEditingController _filter = TextEditingController();

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final client = Matrix.of(context).client;
    final l10n = L10n.of(context);
    final q = _filter.text.trim().toLowerCase();

    String nameOf(Room r) =>
        r.getLocalizedDisplayname(MatrixLocals(l10n));

    final visible = widget.rooms
        .where((r) => q.isEmpty || nameOf(r).toLowerCase().contains(q))
        .toList();
    final invites = visible
        .where((r) => r.membership == Membership.invite)
        .toList();
    final joined = visible
        .where((r) => r.membership != Membership.invite)
        .toList();

    return Material(
      color: theme.colorScheme.surface,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
              child: TextField(
                controller: _filter,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Find or start a conversation',
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: theme.colorScheme.surfaceContainerLowest,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(bottom: 110),
                children: [
                  _NavTile(
                    icon: Icons.star_outline,
                    label: 'Starred messages',
                    onTap: () => VibeSharedPage.open(context, client),
                  ),
                  if (invites.isNotEmpty) ...[
                    _SectionLabel('INVITES — ${invites.length}'),
                    for (final room in invites)
                      _InviteTile(
                        room: room,
                        name: nameOf(room),
                        onTap: () => widget.onTap(room),
                      ),
                  ],
                  _SectionLabel(
                    'DIRECT MESSAGES — ${joined.length}',
                    onAdd: () => VibeAddContact.show(context),
                  ),
                  for (final room in joined)
                    _DmTile(
                      room: room,
                      name: nameOf(room),
                      active: room.id == widget.activeRoomId,
                      onTap: () => widget.onTap(room),
                      onOpen: () => widget.onOpen(room),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  final VoidCallback? onAdd;
  const _SectionLabel(this.text, {this.onAdd});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.6,
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
          if (onAdd != null)
            IconButton(
              icon: Icon(Icons.add, color: cs.onSurfaceVariant),
              tooltip: 'Add contact',
              onPressed: onAdd,
            ),
        ],
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _NavTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => ListTile(
    dense: true,
    leading: Icon(icon),
    title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
    onTap: onTap,
  );
}

class _DmTile extends StatelessWidget {
  final Room room;
  final String name;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback onOpen;

  const _DmTile({
    required this.room,
    required this.name,
    required this.active,
    required this.onTap,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: Material(
        color: active ? theme.colorScheme.secondaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.hardEdge,
        child: ListTile(
          onTap: onTap,
          onLongPress: onOpen,
          contentPadding: const EdgeInsets.only(left: 10, right: 0),
          leading: Avatar(
            mxContent: room.avatar,
            name: name,
            size: 42,
            client: room.client,
            presenceUserId: room.directChatMatrixID,
          ),
          title: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: room.isUnread ? FontWeight.bold : FontWeight.w600,
            ),
          ),
          subtitle: Row(
            children: [
              Icon(
                room.encrypted ? Icons.lock : Icons.lock_open,
                size: 12,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  room.encrypted
                      ? 'Encrypted Direct Message'
                      : 'Direct Message',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
          trailing: UnreadBubble(room: room),
        ),
      ),
    );
  }
}

class _InviteTile extends StatelessWidget {
  final Room room;
  final String name;
  final VoidCallback onTap;
  const _InviteTile({
    required this.room,
    required this.name,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Material(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
        child: ListTile(
          onTap: onTap,
          contentPadding: const EdgeInsets.only(left: 10, right: 4),
          leading: Avatar(
            mxContent: room.avatar,
            name: name,
            size: 42,
            client: room.client,
          ),
          title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: const Text('Wants to chat with you'),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.close, color: Colors.redAccent),
                tooltip: 'Reject',
                onPressed: () async {
                  try {
                    await room.leave();
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text('$e')));
                    }
                  }
                },
              ),
              IconButton(
                icon: Icon(Icons.check, color: theme.colorScheme.onSurface),
                tooltip: 'Accept',
                onPressed: () async {
                  try {
                    await room.join();
                    if (context.mounted) context.go('/rooms/${room.id}');
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text('$e')));
                    }
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
