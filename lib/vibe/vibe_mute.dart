// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

/// One place for "is this chat muted?" that updates everywhere at once.
///
/// The server only confirms a mute with the next sync, so right after
/// tapping Mute the room still looked unmuted (the ⋮ menu kept offering
/// "Mute notifications"). Vibe remembers the choice until the server
/// agrees, and tells every badge and menu to update.
abstract class VibeMute {
  static final changes = ValueNotifier<int>(0);
  static final Map<String, bool> _pending = {};
  static final Map<String, DateTime> _pendingAt = {};

  static bool isMuted(Room room) {
    final real = room.pushRuleState != PushRuleState.notify;
    final want = _pending[room.id];
    if (want == null) return real;
    // A remembered choice only lasts until the server agrees, or 30 s. If it
    // stayed longer (the mute was changed elsewhere), the chat looked muted
    // by itself.
    final at = _pendingAt[room.id];
    if (want == real ||
        at == null ||
        DateTime.now().difference(at) > const Duration(seconds: 30)) {
      _pending.remove(room.id);
      _pendingAt.remove(room.id);
      return real;
    }
    return want;
  }

  static Future<void> set(Room room, bool muted) async {
    _pending[room.id] = muted;
    _pendingAt[room.id] = DateTime.now();
    changes.value++;
    try {
      await room.setPushRuleState(
        muted ? PushRuleState.dontNotify : PushRuleState.notify,
      );
    } catch (_) {
      _pending.remove(room.id);
      _pendingAt.remove(room.id);
      changes.value++;
      rethrow;
    }
  }
}

/// Rebuilds when [room]'s mute changes (here or from another device).
class VibeMuteBuilder extends StatelessWidget {
  final Room room;
  final Widget Function(BuildContext context, bool muted) builder;
  const VibeMuteBuilder({required this.room, required this.builder, super.key});

  @override
  Widget build(BuildContext context) => StreamBuilder<Object?>(
    stream: room.client.onSync.stream.where(
      (u) => u.accountData?.any((a) => a.type == 'm.push_rules') ?? false,
    ),
    builder: (context, _) => ValueListenableBuilder<int>(
      valueListenable: VibeMute.changes,
      builder: (context, _, _) => builder(context, VibeMute.isMuted(room)),
    ),
  );
}

/// A small "muted" bell on a chat's picture (top right; the online dot
/// keeps the bottom right).
class VibeMuteBadge extends StatelessWidget {
  final Room room;
  final Widget child;
  final double size;
  const VibeMuteBadge({
    required this.room,
    required this.child,
    this.size = 16,
    super.key,
  });

  @override
  Widget build(BuildContext context) => VibeMuteBuilder(
    room: room,
    builder: (context, muted) {
      if (!muted) return child;
      final cs = Theme.of(context).colorScheme;
      return Stack(
        clipBehavior: Clip.none,
        children: [
          child,
          Positioned(
            top: -2,
            right: -2,
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                shape: BoxShape.circle,
                border: Border.all(color: cs.surface, width: 1.5),
              ),
              child: Icon(
                Icons.notifications_off_rounded,
                size: size * 0.62,
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
        ],
      );
    },
  );
}
