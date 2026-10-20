// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/vibe/vibe_mute.dart';
import 'package:fluffychat/vibe/vibe_dialog.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/vibe/vibe_archive.dart';
import 'package:fluffychat/vibe/vibe_communities.dart';
import 'package:fluffychat/vibe/vibe_dm_finder.dart';
import 'package:fluffychat/vibe/vibe_haptics.dart';
import 'package:fluffychat/vibe/vibe_lock.dart';
import 'package:fluffychat/vibe/vibe_settings_style.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/vibe/vibe_motion.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

/// Long-press a chat (rail picture or chat row): Pin, Mute and Archive as
/// three round, filled, white/grey buttons; Lock and Mark as read below.
/// Pin, mute and archive are stored on the server, so they follow you to
/// every device.
abstract class VibeChatActions {
  static Future<void> show(
    BuildContext context,
    Room room, {
    required VoidCallback onOpen,
  }) async {
    VibeHaptics.medium();
    final messenger = ScaffoldMessenger.of(context);
    final action = await showVibeSheet<String>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      backgroundColor: VibeSettingsStyle.page(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => _Sheet(room: room, messenger: messenger),
    );
    if (action == null || !context.mounted) return;
    try {
      switch (action) {
        case 'open':
          onOpen();
        case 'lock':
          await VibeLock.toggle(context, room);
        case 'delete':
          final ok = await showVibeDialog<bool>(
            context: context,
            useRootNavigator: true,
            builder: (ctx) => AlertDialog(
              title: const Text('Delete chat?'),
              content: Text(
                'You\'ll leave ${room.getLocalizedDisplayname()} and it '
                'disappears from Vibe. The other person keeps their copy.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFDA373C),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Delete'),
                ),
              ],
            ),
          );
          if (ok != true) return;
          final name = room.getLocalizedDisplayname();
          final problem = await VibeDmFinder.delete(room);
          if (problem != null) {
            Logs().w('Vibe: delete chat: server said $problem');
          }
          messenger.showSnackBar(
            SnackBar(content: Text('Deleted $name')),
          );
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

class _Sheet extends StatefulWidget {
  final Room room;
  final ScaffoldMessengerState messenger;
  const _Sheet({required this.room, required this.messenger});

  @override
  State<_Sheet> createState() => _SheetState();
}

class _SheetState extends State<_Sheet> {
  late bool _pinned = widget.room.isFavourite;
  late bool _muted = VibeMute.isMuted(widget.room);
  late bool _archived = VibeArchive.isArchived(widget.room);
  bool _busy = false;

  /// Flip the button at once (it animates), save in the background, then
  /// close the pane a moment later so you see the change.
  Future<void> _run(
    void Function() flip,
    Future<void> Function() save,
    String done,
  ) async {
    if (_busy) return;
    _busy = true;
    VibeHaptics.light();
    setState(flip);
    try {
      await save();
      widget.messenger.showSnackBar(
        SnackBar(content: Text(done), duration: const Duration(seconds: 2)),
      );
    } catch (e) {
      widget.messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
    await Future<void>.delayed(const Duration(milliseconds: 260));
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final room = widget.room;
    final name = room.getLocalizedDisplayname(MatrixLocals(L10n.of(context)));
    final t1 = VibeSettingsStyle.text(context);
    final t2 = VibeSettingsStyle.text2(context);
    final locked = VibeLock.isLocked(room.id);
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
            child: Row(
              children: [
                Avatar(
                  mxContent: room.avatar,
                  name: name,
                  size: 44,
                  client: room.client,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: t1,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _RoundAction(
                  icon: Icons.push_pin,
                  offIcon: Icons.push_pin,
                  on: _pinned,
                  label: _pinned ? 'Unpin' : 'Pin',
                  onTap: () => _run(
                    () => _pinned = !_pinned,
                    () => room.setFavourite(_pinned),
                    _pinned ? 'Pinned $name' : 'Unpinned $name',
                  ),
                ),
                _RoundAction(
                  icon: Icons.notifications_off,
                  offIcon: Icons.notifications,
                  on: _muted,
                  label: _muted ? 'Unmute' : 'Mute',
                  onTap: () => _run(
                    () => _muted = !_muted,
                    () => room.isSpace
                        ? VibeCommunities.setMuted(room, _muted)
                        : VibeMute.set(room, _muted),
                    _muted ? 'Muted $name' : 'Notifications on for $name',
                  ),
                ),
                _RoundAction(
                  icon: Icons.unarchive,
                  offIcon: Icons.archive,
                  on: _archived,
                  label: _archived ? 'Unarchive' : 'Archive',
                  onTap: () => _run(
                    () => _archived = !_archived,
                    () => VibeArchive.setArchived(room, _archived),
                    _archived
                        ? 'Archived $name · long-press your picture to see it'
                        : 'Moved $name back to your chats',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: VibeSettingsStyle.card(context),
              borderRadius: BorderRadius.circular(20),
            ),
            clipBehavior: Clip.antiAlias,
            child: Material(
              type: MaterialType.transparency,
              child: Column(
                children: [
                  ListTile(
                    leading: Icon(Icons.chat_bubble, color: t1),
                    title: Text(
                      room.isSpace ? 'Open community' : 'Open chat',
                      style: TextStyle(color: t1),
                    ),
                    onTap: () => Navigator.pop(context, 'open'),
                  ),
                  if (!room.isSpace)
                  ListTile(
                    leading: Icon(
                      locked ? Icons.lock_open : Icons.lock,
                      color: t1,
                    ),
                    title: Text(
                      locked ? 'Unlock chat' : 'Lock chat',
                      style: TextStyle(color: t1),
                    ),
                    subtitle: locked
                        ? null
                        : Text(
                            'Hide it behind your fingerprint',
                            style: TextStyle(color: t2),
                          ),
                    onTap: () => Navigator.pop(context, 'lock'),
                  ),
                  ListTile(
                    leading: const Icon(
                      Icons.delete,
                      color: Color(0xFFDA373C),
                    ),
                    title: Text(
                      room.isDirectChat ? 'Delete chat' : 'Leave',
                      style: const TextStyle(color: Color(0xFFDA373C)),
                    ),
                    onTap: () => Navigator.pop(context, 'delete'),
                  ),
                  if (room.isUnread)
                    ListTile(
                      leading: Icon(Icons.mark_chat_read, color: t1),
                      title: Text(
                        'Mark as read',
                        style: TextStyle(color: t1),
                      ),
                      onTap: () => Navigator.pop(context, 'read'),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

/// Round grey button with a filled white (dark) / black (light) icon. When
/// switched on it fills in with the text colour and the icon inverts,
/// with a small spring pop.
class _RoundAction extends StatelessWidget {
  final IconData icon;
  final IconData offIcon;
  final bool on;
  final String label;
  final VoidCallback onTap;
  const _RoundAction({
    required this.icon,
    required this.offIcon,
    required this.on,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final grey = dark ? const Color(0xFF3A393F) : const Color(0xFFE3E5E8);
    final ink = VibeSettingsStyle.text(context);
    final bg = on ? ink : grey;
    final fg = on ? (dark ? const Color(0xFF1A191E) : Colors.white) : ink;
    return VibePressable(
      scale: 0.92,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: 88,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                width: 60,
                height: 60,
                decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 260),
                  switchInCurve: vibeSpring,
                  transitionBuilder: (child, a) =>
                      ScaleTransition(scale: a, child: child),
                  child: Icon(
                    on ? icon : offIcon,
                    key: ValueKey(on),
                    color: fg,
                    size: 26,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: Text(
                  label,
                  key: ValueKey(label),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: VibeSettingsStyle.text2(context),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
