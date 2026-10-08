// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/vibe/vibe_haptics.dart';
import 'package:fluffychat/vibe/vibe_disappearing.dart';
import 'package:fluffychat/vibe/vibe_media_saver.dart';
import 'package:fluffychat/vibe/vibe_send_later.dart';
import 'package:fluffychat/vibe/vibe_status.dart';
import 'package:fluffychat/vibe/vibe_typing_pen.dart';
import 'package:fluffychat/vibe/vibe_whats_new.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/fluffy_chat_app.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

class _Item {
  final Room room;
  final bool typing;
  final String text;
  const _Item(this.room, this.typing, this.text);
}

/// Wraps the whole app. While you are inside a chat (or anywhere except the
/// home list), a pill slides down from the top when someone in ANOTHER chat
/// starts typing or sends a message. Tap it to open that chat, swipe up to
/// dismiss. It floats, so the layout never changes.
class VibeActivityHost extends StatefulWidget {
  final Widget child;
  const VibeActivityHost({required this.child, super.key});

  @override
  State<VibeActivityHost> createState() => _VibeActivityHostState();
}

class _VibeActivityHostState extends State<VibeActivityHost> {
  StreamSubscription<SyncUpdate>? _typingSub;
  StreamSubscription<Event>? _msgSub;
  Timer? _hide;
  _Item? _item;
  bool _visible = false;
  Client? _client;

  String? get _path =>
      FluffyChatApp.router.routeInformationProvider.value.uri.path;

  String? _currentRoomId() {
    final seg =
        FluffyChatApp.router.routeInformationProvider.value.uri.pathSegments;
    if (seg.length >= 2 && seg[0] == 'rooms' && seg[1].startsWith('!')) {
      return seg[1];
    }
    return null;
  }

  /// Home list (rows already show typing + unread) -> no pill.
  bool get _onHome {
    final p = _path ?? '/rooms';
    return p == '/rooms' || p == '/' || p == '/rooms/';
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final c = Matrix.of(context).client;
    if (_client == c) return;
    _client = c;
    _typingSub?.cancel();
    _msgSub?.cancel();
    _typingSub = c.onSync.stream
        .where(
          (u) =>
              u.rooms?.join?.values.any(
                (r) => r.ephemeral?.any((e) => e.type == 'm.typing') ?? false,
              ) ??
              false,
        )
        .listen(_onTyping);
    // Keep my time zone + status present in every direct chat.
    Future.delayed(const Duration(seconds: 20), () => VibeStatus.refresh(c));
    VibeDisappearing.start(c);
    VibeSendLater.start(c);
    Future.delayed(const Duration(seconds: 3), () {
      if (c.isLogged()) VibeWhatsNew.maybeShow();
    });
    _msgSub = c.onTimelineEvent.stream.listen((e) {
      VibeMediaSaver.onEvent(e);
      _onMessage(e);
    });
  }

  void _onTyping(SyncUpdate u) {
    if (!mounted || _onHome) return;
    final c = _client!;
    final current = _currentRoomId();
    final l10n = L10n.of(context);
    for (final id in u.rooms?.join?.keys ?? const <String>[]) {
      final room = c.getRoomById(id);
      if (room == null || room.id == current) continue;
      final typers = room.typingUsers.where((x) => x.id != c.userID);
      if (typers.isNotEmpty) {
        _show(
          _Item(
            room,
            true,
            typers.length == 1
                ? 'is typing…'
                : '${typers.length} people are typing…',
          ),
          const Duration(seconds: 6),
        );
        return;
      }
      if (_item?.typing == true && _item?.room.id == id) {
        _hide?.cancel();
        _hide = Timer(const Duration(milliseconds: 900), _dismiss);
      }
    }
    // keep the compiler happy about unused l10n in some configurations
    l10n.toString();
  }

  void _onMessage(Event e) {
    if (!mounted || _onHome) return;
    final c = _client!;
    if (e.senderId == c.userID) return;
    if (e.room.id == _currentRoomId()) return;
    if (e.type != EventTypes.Message && e.type != EventTypes.Encrypted) return;
    if (!e.status.isSynced) return;
    final body = e.calcLocalizedBodyFallback(
      MatrixLocals(L10n.of(context)),
      plaintextBody: true,
      hideReply: true,
      hideEdit: true,
      removeMarkdown: true,
    );
    _show(_Item(e.room, false, body), const Duration(seconds: 4));
  }

  void _show(_Item item, Duration d) {
    _hide?.cancel();
    final wasVisible = _visible;
    setState(() {
      _item = item;
      _visible = true;
    });
    if (!wasVisible) VibeHaptics.light();
    _hide = Timer(d, _dismiss);
  }

  void _dismiss() {
    if (mounted && _visible) setState(() => _visible = false);
  }

  int _otherUnread() {
    final c = _client;
    final cur = _item?.room.id;
    if (c == null) return 0;
    return c.rooms
        .where((r) => r.id != cur && r.membership == Membership.join)
        .fold(0, (a, r) => a + r.notificationCount);
  }

  @override
  void dispose() {
    _hide?.cancel();
    _typingSub?.cancel();
    _msgSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = _item;
    final top = MediaQuery.paddingOf(context).top;
    return Stack(
      children: [
        widget.child,
        if (item != null)
          Positioned(
            top: top + 8,
            left: 12,
            right: 12,
            child: IgnorePointer(
              ignoring: !_visible,
              child: AnimatedSlide(
                offset: _visible ? Offset.zero : const Offset(0, -1.8),
                duration: const Duration(milliseconds: 380),
                curve: _visible ? Curves.easeOutBack : Curves.easeInCubic,
                child: AnimatedOpacity(
                  opacity: _visible ? 1 : 0,
                  duration: const Duration(milliseconds: 220),
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: GestureDetector(
                        onVerticalDragEnd: (d) {
                          if ((d.primaryVelocity ?? 0) < -120) _dismiss();
                        },
                        child: _Pill(
                          item: item,
                          unread: _otherUnread(),
                          onTap: () {
                            _dismiss();
                            FluffyChatApp.router.go('/rooms/${item.room.id}');
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  final _Item item;
  final int unread;
  final VoidCallback onTap;
  const _Pill({required this.item, required this.unread, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final room = item.room;
    final name = room.getLocalizedDisplayname(MatrixLocals(L10n.of(context)));
    return Material(
      color: cs.surfaceContainerHigh,
      elevation: 6,
      shadowColor: Colors.black54,
      borderRadius: BorderRadius.circular(28),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 14, 8),
          child: Row(
            children: [
              VibeTypingOverlay(
                room: room,
                badgeSize: 18,
                ringColor: cs.surfaceContainerHigh,
                child: Avatar(
                  mxContent: room.avatar,
                  name: name,
                  size: 38,
                  client: room.client,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      item.text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontStyle:
                            item.typing ? FontStyle.italic : FontStyle.normal,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (unread > 0) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF23F43),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    unread > 99 ? '99+' : '$unread',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Discord-style red count badge for DM rows.
class VibeUnreadBadge extends StatelessWidget {
  final Room room;
  const VibeUnreadBadge({required this.room, super.key});

  @override
  Widget build(BuildContext context) {
    final n = room.notificationCount;
    if (n <= 0) {
      return room.isUnread
          ? Padding(
              padding: const EdgeInsets.only(right: 14),
              child: Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            )
          : const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFFF23F43),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              n > 99 ? '99+' : '$n',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                height: 1.2,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
