// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:fluffychat/vibe/call/vibe_call.dart';
import 'package:fluffychat/vibe/call/vibe_call_members.dart';
import 'package:fluffychat/vibe/vibe_motion.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

const _green = Color(0xFF23A55A);

/// Rebuilds when the room's call starts, ends, or someone joins / leaves,
/// and when your own call changes.
class VibeCallWatch extends StatefulWidget {
  final Room room;
  final Widget Function(BuildContext context, List<String> inCall) builder;
  const VibeCallWatch({required this.room, required this.builder, super.key});

  @override
  State<VibeCallWatch> createState() => _VibeCallWatchState();
}

class _VibeCallWatchState extends State<VibeCallWatch> {
  StreamSubscription? _sub;
  Timer? _expiry;

  @override
  void initState() {
    super.initState();
    _listen();
    VibeCall.instance.addListener(_changed);
    // memberships also run out on their own
    _expiry = Timer.periodic(const Duration(seconds: 30), (_) => _changed());
  }

  @override
  void didUpdateWidget(VibeCallWatch old) {
    super.didUpdateWidget(old);
    if (old.room.id != widget.room.id) _listen();
  }

  void _listen() {
    _sub?.cancel();
    _sub = widget.room.client.onRoomState.stream
        .where(
          (u) =>
              u.roomId == widget.room.id &&
              u.state.type == VibeCallMembers.memberType,
        )
        .listen((_) => _changed());
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _sub?.cancel();
    _expiry?.cancel();
    VibeCall.instance.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, VibeCallMembers.userIds(widget.room));
}

/// Call buttons for the chat's top bar. DMs get voice and video; groups get
/// one "join voice" button. While a call is live it turns into a green
/// "Join · 2" pill (or "In call" if it's yours).
class VibeCallActions extends StatelessWidget {
  final Room room;
  const VibeCallActions({required this.room, super.key});

  @override
  Widget build(BuildContext context) {
    if (room.membership != Membership.join) return const SizedBox.shrink();
    return VibeCallWatch(
      room: room,
      builder: (context, inCall) {
        final mine = VibeCall.instance.isIn(room);
        if (mine || inCall.isNotEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: _Pill(
              label: mine
                  ? 'In call'
                  : 'Join${inCall.length > 1 ? ' · ${inCall.length}' : ''}',
              onTap: () => VibeCall.join(context, room),
            ),
          );
        }
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.call),
              tooltip: room.isDirectChat ? 'Voice call' : 'Start a voice call',
              onPressed: () => VibeCall.join(context, room),
            ),
            if (room.isDirectChat)
              IconButton(
                icon: const Icon(Icons.videocam),
                tooltip: 'Video call',
                onPressed: () => VibeCall.join(context, room, video: true),
              ),
          ],
        );
      },
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _Pill({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => VibePressable(
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: _green,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.graphic_eq, size: 16, color: Colors.white),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 13.5,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Little faces of who's in the call (for panes and channel rows).
class VibeCallFaces extends StatelessWidget {
  final Room room;
  final List<String> userIds;
  final int max;
  const VibeCallFaces({
    required this.room,
    required this.userIds,
    this.max = 4,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final shown = userIds.take(max).toList();
    final bg = Theme.of(context).colorScheme.surface;
    return SizedBox(
      height: 24,
      width: shown.isEmpty ? 0 : 24 + (shown.length - 1) * 16.0,
      child: Stack(
        children: [
          for (var i = 0; i < shown.length; i++)
            Positioned(
              left: i * 16.0,
              child: Container(
                padding: const EdgeInsets.all(1.5),
                decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
                child: Builder(
                  builder: (context) {
                    final u = room.unsafeGetUserFromMemoryOrFallback(shown[i]);
                    return Avatar(
                      mxContent: u.avatarUrl,
                      name: u.calcDisplayname(),
                      size: 21,
                      client: room.client,
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Small green speaker on a rail picture while that chat has a live call.
class VibeCallBadge extends StatelessWidget {
  final Color ring;
  const VibeCallBadge({required this.ring, super.key});

  @override
  Widget build(BuildContext context) => Container(
    width: 20,
    height: 20,
    decoration: BoxDecoration(
      color: _green,
      shape: BoxShape.circle,
      border: Border.all(color: ring, width: 2.5),
    ),
    child: const Icon(Icons.volume_up, size: 11, color: Colors.white),
  );
}
