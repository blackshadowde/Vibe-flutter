// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/pages/chat_list/chat_list.dart';
import 'package:fluffychat/utils/stream_extension.dart';
import 'package:fluffychat/vibe/vibe_dm_detail.dart';
import 'package:fluffychat/vibe/vibe_dm_pane.dart';
import 'package:fluffychat/vibe/vibe_dm_rail.dart';
import 'package:fluffychat/vibe/vibe_user_bar.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

/// Discord-style home: [rail of DM avatars] | [Home list or selected DM].
class VibeHomeView extends StatefulWidget {
  final ChatListController controller;
  const VibeHomeView(this.controller, {super.key});

  @override
  State<VibeHomeView> createState() => _VibeHomeViewState();
}

class _VibeHomeViewState extends State<VibeHomeView> {
  String? selectedId;

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final client = Matrix.of(context).client;
    return PopScope(
      canPop: selectedId == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => selectedId = null);
      },
      child: StreamBuilder(
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
          Room? selected;
          for (final r in rooms) {
            if (r.id == selectedId) selected = r;
          }
          final theme = Theme.of(context);
          return ColoredBox(
            color: theme.colorScheme.surfaceContainerLowest,
            child: Stack(
              children: [
                Row(
                  children: [
                    VibeDmRail(
                      rooms: rooms,
                      selectedId: selected?.id,
                      activeRoomId: controller.activeChat,
                      onSelect: (room) => setState(() => selectedId = room.id),
                      onHome: () => setState(() => selectedId = null),
                    ),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(24),
                        ),
                        child: selected == null
                            ? VibeDmPane(
                                rooms: rooms,
                                activeRoomId: controller.activeChat,
                                onTap: (room) =>
                                    setState(() => selectedId = room.id),
                                onOpen: controller.onChatTap,
                              )
                            : VibeDmDetail(
                                key: ValueKey(selected.id),
                                room: selected,
                                onBack: () => setState(() => selectedId = null),
                                onOpenChat: () =>
                                    controller.onChatTap(selected!),
                              ),
                      ),
                    ),
                  ],
                ),
                const Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: VibeUserBar(),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
