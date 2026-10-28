// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:vibe/vibe/vibe_palette.dart';
import 'package:vibe/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:vibe/l10n/l10n.dart';
import 'package:vibe/vibe/vibe_haptics.dart';
import 'package:vibe/vibe/vibe_lock.dart';
import 'package:vibe/vibe/vibe_motion.dart';
import 'package:vibe/widgets/avatar.dart';
import 'package:vibe/widgets/fluffy_chat_app.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

/// While you're in a chat, someone else typing or writing to you doesn't
/// pop up a notification: their picture peeks in from the side, just above
/// the typing bar. Tap it to jump to their chat, swipe it away to dismiss.
class VibePeek extends ChangeNotifier {
  VibePeek._();
  static final VibePeek instance = VibePeek._();

  /// Room ID -> what's happening there, newest last.
  final Map<String, VibePeekItem> _items = {};
  final Map<String, Timer> _timers = {};
  final Set<String> _dismissed = {};

  List<VibePeekItem> itemsFor(String currentRoomId) => _items.values
      .where((i) => i.room.id != currentRoomId)
      .toList()
      .reversed
      .take(3)
      .toList();

  Client? _client;
  StreamSubscription? _sync;

  /// Watch typing in your other chats.
  void attach(Client client) {
    if (_client == client) return;
    _client = client;
    _sync?.cancel();
    _sync = client.onSync.stream.listen((_) => _scanTyping(client));
  }

  void _scanTyping(Client client) {
    final me = client.userID;
    var changed = false;
    for (final r in client.rooms) {
      if (r.membership != Membership.join || VibeLock.isLocked(r.id)) continue;
      final typing = r.typingUsers.where((u) => u.id != me).toList();
      final item = _items[r.id];
      if (typing.isNotEmpty) {
        if (_dismissed.contains(r.id)) continue;
        if (item == null || !item.typing) {
          _put(VibePeekItem(room: r, userId: typing.first.id, typing: true));
          changed = true;
        }
      } else {
        _dismissed.remove(r.id);
        if (item != null && item.typing) {
          // stopped typing: linger a moment unless a message comes
          _expire(r.id, const Duration(seconds: 2));
        }
      }
    }
    if (changed) notifyListeners();
  }

  /// A message arrived in another chat while you're in one (instead of a
  /// notification).
  void message(Event event) {
    if (VibeLock.isLocked(event.room.id)) return;
    _dismissed.remove(event.room.id);
    _put(
      VibePeekItem(
        room: event.room,
        userId: event.senderId,
        typing: false,
        unread: true,
      ),
      life: const Duration(seconds: 8),
    );
    VibeHaptics.light();
    notifyListeners();
  }

  void _put(VibePeekItem item, {Duration life = const Duration(seconds: 15)}) {
    _items.remove(item.room.id);
    _items[item.room.id] = item;
    _expire(item.room.id, life);
  }

  void _expire(String roomId, Duration after) {
    _timers[roomId]?.cancel();
    _timers[roomId] = Timer(after, () {
      _timers.remove(roomId);
      if (_items.remove(roomId) != null) notifyListeners();
    });
  }

  void dismiss(String roomId) {
    _dismissed.add(roomId);
    _timers.remove(roomId)?.cancel();
    if (_items.remove(roomId) != null) notifyListeners();
  }

  void open(String roomId) {
    dismiss(roomId);
    _dismissed.remove(roomId);
    FluffyChatApp.router.go('/rooms/$roomId');
  }
}

class VibePeekItem {
  final Room room;
  final String userId;
  final bool typing;
  final bool unread;
  const VibePeekItem({
    required this.room,
    required this.userId,
    required this.typing,
    this.unread = false,
  });
}

/// The peeking pictures, right-aligned above the typing bar.
class VibePeekBar extends StatelessWidget {
  final Room room;
  const VibePeekBar({required this.room, super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: VibePeek.instance,
    builder: (context, _) {
      final items = VibePeek.instance.itemsFor(room.id);
      return Align(
        alignment: Alignment.centerRight,
        child: AnimatedSize(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          alignment: Alignment.bottomRight,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final i in items)
                _Peek(key: ValueKey(i.room.id), item: i),
            ],
          ),
        ),
      );
    },
  );
}

class _Peek extends StatefulWidget {
  final VibePeekItem item;
  const _Peek({required this.item, super.key});

  @override
  State<_Peek> createState() => _PeekState();
}

class _PeekState extends State<_Peek> with SingleTickerProviderStateMixin {
  late final AnimationController _in = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  )..forward();
  double _drag = 0;

  @override
  void dispose() {
    _in.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final room = item.room;
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final user = room.unsafeGetUserFromMemoryOrFallback(item.userId);
    final name = room.isDirectChat
        ? room.getLocalizedDisplayname(MatrixLocals(L10n.of(context)))
        : user.calcDisplayname();
    final pic = room.isDirectChat ? room.avatar : user.avatarUrl;
    final bubble = !VibePalette.isVibe
        ? Theme.of(context).colorScheme.surfaceContainerHigh
        : dark ? const Color(0xFF2B2D31) : Colors.white;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          VibeHaptics.selection();
          VibePeek.instance.open(room.id);
        },
        onHorizontalDragUpdate: (d) =>
            setState(() => _drag = (_drag + d.delta.dx).clamp(0, 120)),
        onHorizontalDragEnd: (d) {
          if (_drag > 40 || (d.primaryVelocity ?? 0) > 300) {
            VibePeek.instance.dismiss(room.id);
          } else {
            setState(() => _drag = 0);
          }
        },
        child: AnimatedBuilder(
          animation: _in,
          builder: (context, child) {
            final t = vibeSpring.transform(_in.value);
            // slides in from beyond the right edge and stays half tucked
            return Transform.translate(
              offset: Offset((1 - t) * 70 + _drag, 0),
              child: Opacity(opacity: _in.value.clamp(0.0, 1.0), child: child),
            );
          },
          child: Container(
            padding: const EdgeInsets.fromLTRB(4, 4, 14, 4),
            decoration: BoxDecoration(
              color: bubble,
              borderRadius: const BorderRadius.horizontal(
                left: Radius.circular(26),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(dark ? 90 : 40),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Avatar(
                      mxContent: pic,
                      name: name,
                      size: 36,
                      client: room.client,
                    ),
                    if (item.unread)
                      Positioned(
                        right: -1,
                        top: -1,
                        child: Container(
                          width: 11,
                          height: 11,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF23F43),
                            shape: BoxShape.circle,
                            border: Border.all(color: bubble, width: 2),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 8),
                if (item.typing)
                  const _Dots()
                else
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 110),
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Three bouncing dots.
class _Dots extends StatefulWidget {
  const _Dots();

  @override
  State<_Dots> createState() => _DotsState();
}

class _DotsState extends State<_Dots> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 3; i++)
            Builder(
              builder: (context) {
                final p = ((_c.value - i * 0.18) % 1.0);
                final up = p < 0.4 ? (p < 0.2 ? p / 0.2 : (0.4 - p) / 0.2) : 0.0;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Transform.translate(
                    offset: Offset(0, -4 * up),
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: color.withAlpha((140 + 115 * up).round()),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}
