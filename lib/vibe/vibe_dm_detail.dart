// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/vibe/vibe_mute.dart';
import 'package:fluffychat/vibe/vibe_palette.dart';
import 'package:fluffychat/vibe/vibe_call.dart';
import 'package:fluffychat/vibe/vibe_sticker.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/events/audio_player.dart';
import 'package:fluffychat/utils/date_time_extension.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/event_extension.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/vibe/vibe_groups.dart';
import 'package:fluffychat/vibe/vibe_media_viewer.dart';
import 'package:fluffychat/vibe/vibe_motion.dart';
import 'package:fluffychat/vibe/vibe_starred.dart';
import 'package:fluffychat/vibe/vibe_status.dart';
import 'package:fluffychat/vibe/vibe_user_sheet.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/mxc_image.dart';
import 'package:fluffychat/widgets/presence_builder.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';
import 'package:url_launcher/url_launcher.dart';

final RegExp _urlRegex = RegExp(r'https?://\S+');

bool _isVoice(Event e) =>
    e.messageType == MessageTypes.Audio &&
    e.content.containsKey('org.matrix.msc3245.voice');

/// Middle pane for one DM, like Vibgram: big picture, name, online state,
/// then "# | chat" and the INFO channels. Nothing here loads media; each
/// channel opens its own pane that slides up from the bottom.
class VibeDmDetail extends StatelessWidget {
  final Room room;
  final VoidCallback onBack;
  final VoidCallback onOpenChat;

  const VibeDmDetail({
    required this.room,
    required this.onBack,
    required this.onOpenChat,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final name = room.getLocalizedDisplayname(MatrixLocals(L10n.of(context)));
    final invited = room.membership == Membership.invite;
    final other = room.directChatMatrixID;
    final group = VibeGroups.isGroup(room);

    void open(_Kind kind) => _DmSheet.open(context, room, kind);

    return Material(
      color: cs.surface,
      child: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 120),
          children: [
            // Same search bar as Home: tapping it goes back to Home.
            GestureDetector(
              onTap: onBack,
              child: Container(
                height: 46,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    Icon(Icons.search, size: 22, color: cs.onSurfaceVariant),
                    const SizedBox(width: 10),
                    Text(
                      'Find or start a conversation',
                      style: TextStyle(
                        fontSize: 15,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: GestureDetector(
                  onTap: invited ? null : onOpenChat,
                  onLongPress:
                      group && room.canChangeStateEvent(EventTypes.RoomAvatar)
                      ? () => VibeGroupEdit.changePicture(context, room)
                      : null,
                  child: VibeMuteBadge(
                    room: room,
                    size: 20,
                    child: Avatar(
                      mxContent: room.avatar,
                      name: name,
                      size: 62,
                      client: room.client,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 6, top: 2),
              child: group
                  ? Text(
                      '${VibeGroups.memberCount(room)} members',
                      style: TextStyle(
                        fontSize: 13.5,
                        color: cs.onSurfaceVariant,
                      ),
                    )
                  : PresenceBuilder(
                client: room.client,
                userId: other,
                builder: (context, p) {
                  final online = p?.presence.isOnline == true;
                  final last = p?.lastActiveTimestamp;
                  final text = online
                      ? 'online'
                      : last != null
                      ? 'last seen ${last.localizedTimeShort(context)}'
                      : '';
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (text.isNotEmpty)
                        Text(
                          text,
                          style: TextStyle(
                            fontSize: 13.5,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      VibeStatusLine(
                        room: room,
                        userId: other,
                        maxLines: 2,
                        alwaysTime: true,
                        style: TextStyle(
                          fontSize: 13,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            if (invited)
              _ApprovalBanner(room: room, name: name)
            else ...[
              StreamBuilder<Object?>(
                stream: room.client.onSync.stream.where(
                  (u) =>
                      (u.rooms?.join?.containsKey(room.id) ?? false) ||
                      (u.accountData?.isNotEmpty ?? false),
                ),
                builder: (context, _) => VibeHashRow(
                  label: 'chat',
                  subtitle: room.encrypted ? 'End-to-end encrypted' : null,
                  subtitleIcon: Icons.lock_rounded,
                  unread: room.notificationCount > 0
                      ? room.notificationCount
                      : (room.markedUnread ? 1 : 0),
                  onTap: onOpenChat,
                ),
              ),
              if (room.canSendDefaultMessages) ...[
                VibeHashRow(
                  label: 'voice-call',
                  icon: Icons.call_outlined,
                  onTap: () => VibeCall.startFrom(context, room, video: false),
                ),
                VibeHashRow(
                  label: 'video-call',
                  icon: Icons.videocam_outlined,
                  onTap: () => VibeCall.startFrom(context, room, video: true),
                ),
              ],
              const VibePaneHeader('INFO'),
              VibeHashRow(
                label: 'media',
                subtitle: 'Photos and videos',
                onTap: () => open(_Kind.media),
              ),
              VibeHashRow(label: 'files', onTap: () => open(_Kind.files)),
              VibeHashRow(label: 'links', onTap: () => open(_Kind.links)),
              VibeHashRow(
                label: 'voice-messages',
                onTap: () => open(_Kind.voice),
              ),
              VibeHashRow(
                label: 'starred-messages',
                onTap: () => open(_Kind.starred),
              ),
              if (group) ...[
                const VibePaneHeader('MEMBERS'),
                VibeHashRow(
                  label: 'members',
                  subtitle: '${VibeGroups.memberCount(room)} people',
                  onTap: () => VibeGroups.showMembers(context, room),
                ),
                if (room.canInvite)
                  VibeHashRow(
                    label: 'invite-people',
                    onTap: () => VibeGroups.showInvite(context, room),
                  ),
                const VibePaneHeader('GROUP'),
                if (room.canChangeStateEvent(EventTypes.RoomAvatar))
                  VibeHashRow(
                    label: 'group-picture',
                    onTap: () => VibeGroupEdit.changePicture(context, room),
                  ),
                if (room.canChangeStateEvent(EventTypes.RoomName))
                  VibeHashRow(
                    label: 'rename-group',
                    onTap: () => VibeGroups.rename(context, room),
                  ),
                VibeHashRow(
                  label: 'privacy',
                  subtitle: VibeGroups.isPublic(room)
                      ? 'Public · anyone can join'
                      : 'Private · invite only',
                  subtitleIcon: VibeGroups.isPublic(room)
                      ? Icons.public_rounded
                      : Icons.lock_rounded,
                  onTap: () => VibeGroupEdit.privacy(context, room),
                ),
                VibeHashRow(
                  label: 'leave-group',
                  onTap: () => VibeGroups.leave(context, room),
                ),
              ],
              if (other != null && !group)
                VibeHashRow(
                  label: 'profile',
                  onTap: () => VibeUserSheet.show(
                    context,
                    client: room.client,
                    userId: other,
                    displayName: name,
                    avatarUrl: room.avatar,
                    currentRoomId: room.id,
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class VibePaneHeader extends StatelessWidget {
  final String text;

  /// Optional "+" at the end of the header (add a channel, ...).
  final VoidCallback? onAdd;
  const VibePaneHeader(this.text, {this.onAdd, super.key});

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final label = Text(
      text,
      style: TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.4,
        color: muted,
      ),
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(6, 16, onAdd == null ? 6 : 0, onAdd == null ? 4 : 0),
      child: onAdd == null
          ? label
          : Row(
              children: [
                Expanded(child: label),
                SizedBox(
                  width: 36,
                  height: 32,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    icon: Icon(Icons.add, size: 20, color: muted),
                    onPressed: onAdd,
                  ),
                ),
              ],
            ),
    );
  }
}

/// "#   | label" with an optional line under it, Vibgram style.
class VibeHashRow extends StatelessWidget {
  final String label;
  final String? subtitle;

  /// Small icon in front of the line under the label (a lock, a globe).
  final IconData? subtitleIcon;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  /// Brighter label (an unread channel).
  final bool bold;

  /// Shown at the end of the row (unread badge, "Join").
  final Widget? trailing;

  /// Unread messages / missed calls: the row lights up (white in dark
  /// mode, black in light), with a counter and a small pill at the edge,
  /// like Discord's unread channels.
  final int unread;

  /// "#" for text, "🔊"-style icon for voice.
  final IconData? icon;
  final Color? iconColor;
  const VibeHashRow({
    required this.label,
    required this.onTap,
    this.subtitle,
    this.subtitleIcon,
    this.onLongPress,
    this.bold = false,
    this.trailing,
    this.icon,
    this.iconColor,
    this.unread = 0,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final lit = unread > 0;
    final muted = lit ? cs.onSurface : cs.onSurfaceVariant;
    final bold = this.bold || lit;
    final trailing =
        this.trailing ?? (lit ? VibeUnreadBadge(count: unread) : null);
    final row = VibePressable(
      scale: 0.97,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
          child: Row(
            children: [
              SizedBox(
                width: 28,
                child: icon != null
                    ? Icon(icon, size: 19, color: iconColor ?? muted)
                    : Text(
                        '#',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 19, color: muted),
                      ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: '|  ',
                            style: TextStyle(color: muted.withAlpha(0x88)),
                          ),
                          TextSpan(text: label),
                        ],
                      ),
                      style: TextStyle(
                        fontSize: 14.5,
                        color: bold ? cs.onSurface : muted,
                        fontWeight: bold ? FontWeight.w800 : FontWeight.w700,
                      ),
                    ),
                    if (subtitle != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 1),
                        child: Row(
                          children: [
                            if (subtitleIcon != null) ...[
                              Icon(subtitleIcon, size: 12.5, color: muted),
                              const SizedBox(width: 4),
                            ],
                            Flexible(
                              child: Text(
                                subtitle!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 12, color: muted),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 8),
                trailing,
              ],
            ],
          ),
        ),
      ),
    );
    if (!lit) return row;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        row,
        Positioned(
          left: -10,
          top: 0,
          bottom: 0,
          child: Center(
            child: Container(
              width: 4,
              height: 8,
              decoration: BoxDecoration(
                color: cs.onSurface,
                borderRadius: const BorderRadius.horizontal(
                  right: Radius.circular(4),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Red unread counter (99+ at most).
class VibeUnreadBadge extends StatelessWidget {
  final int count;
  const VibeUnreadBadge({required this.count, super.key});

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minWidth: 20),
    height: 20,
    padding: const EdgeInsets.symmetric(horizontal: 6),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: const Color(0xFFF23F43),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(
      count > 99 ? '99+' : '$count',
      style: const TextStyle(
        color: Colors.white,
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

/// "# | mute-notifications": silence a group or channel (stored on the
/// server, so it follows you to every device).
class VibeMuteRow extends StatefulWidget {
  final Room room;
  final String what;
  const VibeMuteRow({required this.room, this.what = 'notifications', super.key});

  static bool isMuted(Room room) => VibeMute.isMuted(room);

  static Future<void> setMuted(Room room, bool muted) =>
      VibeMute.set(room, muted);

  @override
  State<VibeMuteRow> createState() => _VibeMuteRowState();
}

class _VibeMuteRowState extends State<VibeMuteRow> {
  late bool _muted = VibeMuteRow.isMuted(widget.room);
  bool _busy = false;

  Future<void> _toggle() async {
    if (_busy) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _busy = true;
      _muted = !_muted;
    });
    try {
      await VibeMuteRow.setMuted(widget.room, _muted);
      messenger.showSnackBar(
        SnackBar(
          content: Text(_muted ? 'Muted' : 'Notifications on'),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (mounted) setState(() => _muted = !_muted);
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => VibeHashRow(
    label: _muted ? 'unmute-${widget.what}' : 'mute-${widget.what}',
    subtitle: _muted ? 'Muted · no notifications' : 'Notifications on',
    subtitleIcon: _muted
        ? Icons.notifications_off_rounded
        : Icons.notifications_rounded,
    onTap: _toggle,
  );
}

class _ApprovalBanner extends StatelessWidget {
  final Room room;
  final String name;
  const _ApprovalBanner({required this.room, required this.name});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Material(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'APPROVAL REQUEST',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.6,
                  color: Color(0xFFB5BAC1),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                VibeGroups.isGroup(room)
                    ? 'You\'re invited to the group $name.'
                    : '$name wants to start a chat with you.',
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        try {
                          await room.leave();
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('$e')),
                            );
                          }
                        }
                      },
                      child: const Text('Reject'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () async {
                        try {
                          await room.join();
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('$e')),
                            );
                          }
                        }
                      },
                      child: const Text('Accept'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// The channels' panes: slide up from the bottom. Tap an item to open it,
// long-press to jump to it in the chat.
// ---------------------------------------------------------------------------

enum _Kind { media, files, links, voice, starred }

extension on _Kind {
  String get label => switch (this) {
    _Kind.media => 'media',
    _Kind.files => 'files',
    _Kind.links => 'links',
    _Kind.voice => 'voice-messages',
    _Kind.starred => 'starred-messages',
  };

  String get empty => switch (this) {
    _Kind.media => 'No photos or videos in this chat yet.',
    _Kind.files => 'No files in this chat yet.',
    _Kind.links => 'No links in this chat yet.',
    _Kind.voice => 'No voice messages in this chat yet.',
    _Kind.starred => 'You haven\'t starred anything in this chat.',
  };

  bool Function(Event)? get filter => switch (this) {
    _Kind.media => (e) =>
        {MessageTypes.Image, MessageTypes.Video}.contains(e.messageType) &&
        !e.isVibeSticker,
    _Kind.files => (e) =>
        e.messageType == MessageTypes.File ||
        (e.messageType == MessageTypes.Audio && !_isVoice(e)),
    _Kind.links => (e) =>
        e.type == EventTypes.Message &&
        e.messageType == MessageTypes.Text &&
        _urlRegex.hasMatch(e.body),
    _Kind.voice => _isVoice,
    _ => null,
  };
}

/// What was found so far, kept while Vibe runs so a pane opens instantly
/// the second time (no searching or reloading pictures again).
class _Found {
  final List<Event> events = [];
  String? nextBatch;
  bool end = false;
  bool loading = false;
}

class _DmSheet extends StatefulWidget {
  final Room room;
  final _Kind kind;
  final ScrollController scroll;
  const _DmSheet({required this.room, required this.kind, required this.scroll});

  static final Map<String, _Found> _cache = {};

  static Future<void> open(BuildContext context, Room room, _Kind kind) {
    final cs = Theme.of(context).colorScheme;
    return showVibeSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      sheetAnimationStyle: vibeSheetStyle,
      backgroundColor: cs.surface,
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.72,
        minChildSize: 0.4,
        maxChildSize: 0.96,
        snap: true,
        snapSizes: const [0.72],
        builder: (ctx, scroll) => RepaintBoundary(
          child: _DmSheet(room: room, kind: kind, scroll: scroll),
        ),
      ),
    );
  }

  @override
  State<_DmSheet> createState() => _DmSheetState();
}

class _DmSheetState extends State<_DmSheet> {
  late final _Found _found = _DmSheet._cache.putIfAbsent(
    '${widget.room.id}|${widget.kind.name}',
    _Found.new,
  );

  // Starred: a fixed list of ids, loaded one by one.
  List<String> _ids = const [];
  final Map<String, Event?> _byId = {};

  @override
  void initState() {
    super.initState();
    if (widget.kind.filter != null) {
      if (_found.events.isEmpty && !_found.end) _more();
      widget.scroll.addListener(_onScroll);
    } else {
      _loadIds();
    }
  }

  @override
  void dispose() {
    widget.scroll.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll() {
    final p = widget.scroll.position;
    if (p.pixels > p.maxScrollExtent - 500) _more();
  }

  Future<void> _more() async {
    final f = _found;
    if (f.loading || f.end) return;
    setState(() => f.loading = true);
    try {
      final result = await widget.room.searchEvents(
        searchFunc: widget.kind.filter,
        nextBatch: f.nextBatch,
      );
      final known = f.events.map((e) => e.eventId).toSet();
      f.events.addAll(result.events.where((e) => known.add(e.eventId)));
      f.nextBatch = result.nextBatch;
      f.end = result.nextBatch == null;
    } catch (_) {
      f.end = true;
    }
    f.loading = false;
    if (mounted) setState(() {});
    // A page of history can hold few or no photos, and a short grid can't be
    // scrolled to ask for more: keep going back through the chat's history
    // on the server until the pane is filled (or the chat's start is reached).
    if (mounted && !f.end && f.events.length < 60 && _autoPages++ < 40) {
      await _more();
    }
  }

  int _autoPages = 0;

  Future<void> _loadIds() async {
    _ids = VibeStarred.ids(widget.room.id).toList();
    setState(() {});
    for (final id in _ids) {
      if (_byId.containsKey(id)) continue;
      final e = await widget.room.getEventById(id).catchError((_) => null);
      if (!mounted) return;
      setState(() => _byId[id] = e);
    }
  }

  /// Long-press: close the pane and show the message in the chat.
  void _jump(Event e) {
    final router = GoRouter.of(context);
    Navigator.of(context).pop();
    router.go('/rooms/${widget.room.id}?event=${e.eventId}');
  }

  String _who(Event e) => e.senderFromMemoryOrFallback.calcDisplayname(
    i18n: MatrixLocals(L10n.of(context)),
  );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final muted = cs.onSurfaceVariant;
    final listKind = widget.kind.filter != null;
    final count = listKind ? _found.events.length : _ids.length;
    final loading = listKind && _found.loading;

    final header = SliverToBoxAdapter(
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 5,
            decoration: BoxDecoration(
              color: muted.withAlpha(0x66),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
            child: Row(
              children: [
                Text(
                  '#',
                  style: TextStyle(fontSize: 24, color: muted),
                ),
                const SizedBox(width: 12),
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '|  ',
                        style: TextStyle(color: muted.withAlpha(0x88)),
                      ),
                      TextSpan(text: widget.kind.label),
                    ],
                  ),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                if (count > 0)
                  Text(
                    listKind && !_found.end ? '$count+' : '$count',
                    style: TextStyle(color: muted, fontWeight: FontWeight.w600),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Tap to open · long-press to see it in the chat',
                style: TextStyle(fontSize: 12.5, color: muted),
              ),
            ),
          ),
        ],
      ),
    );

    final Widget body;
    if (count == 0) {
      body = SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: loading || (!listKind && _ids.isNotEmpty)
              ? const CircularProgressIndicator.adaptive()
              : Text(widget.kind.empty, style: TextStyle(color: muted)),
        ),
      );
    } else {
      body = switch (widget.kind) {
        _Kind.media => _mediaGrid(),
        _Kind.links => _links(),
        _ => SliverList.builder(
          itemCount: listKind ? _found.events.length : _ids.length,
          itemBuilder: (context, i) => listKind
              ? _row(_found.events[i])
              : _idRow(_ids[i]),
        ),
      };
    }

    // The list / grid (and its pictures) is built once the pane has slid
    // up, so the slide itself stays smooth.
    return VibeSettled(
      placeholder: CustomScrollView(
        controller: widget.scroll,
        slivers: [header],
      ),
      child: CustomScrollView(
      controller: widget.scroll,
      slivers: [
        header,
        body,
        if (loading && count > 0)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator.adaptive()),
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
      ),
    );
  }

  Widget _mediaGrid() {
    final events = _found.events;
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      sliver: SliverGrid.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 4,
          crossAxisSpacing: 4,
        ),
        itemCount: events.length,
        itemBuilder: (context, i) {
          final e = events[i];
          return GestureDetector(
            onTap: () => VibeMediaViewer.open(context, events, i),
            onLongPress: () => _jump(e),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(color: Theme.of(context).colorScheme.surfaceContainerHigh),
                  LayoutBuilder(
                    builder: (context, c) => MxcImage(
                      // Kept in memory: scrolling back or reopening the
                      // pane doesn't download / decrypt it again.
                      key: ValueKey('thumb_${e.eventId}'),
                      cacheKey: 'thumb_${e.eventId}',
                      event: e,
                      width: c.maxWidth,
                      height: c.maxWidth,
                      fit: BoxFit.cover,
                      isThumbnail: true,
                      placeholder: (_) => const SizedBox.shrink(),
                    ),
                  ),
                  if (e.messageType == MessageTypes.Video)
                    const Center(
                      child: Icon(
                        Icons.play_circle_fill,
                        color: Colors.white,
                        size: 34,
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _links() {
    final links = <(Event, String)>[];
    for (final e in _found.events) {
      for (final m in _urlRegex.allMatches(e.body)) {
        links.add((e, m.group(0)!));
      }
    }
    return SliverList.builder(
      itemCount: links.length,
      itemBuilder: (context, i) {
        final (e, url) = links[i];
        final host = Uri.tryParse(url)?.host ?? url;
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: VibePalette.accent.withAlpha(0x33),
            child: const Icon(Icons.link, color: Color(0xFF8C96F6)),
          ),
          title: Text(host, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            '$url\n${_who(e)} · ${e.originServerTs.localizedTimeShort(context)}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          isThreeLine: true,
          onTap: () =>
              launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
          onLongPress: () => _jump(e),
        );
      },
    );
  }

  Widget _row(Event e) {
    final cs = Theme.of(context).colorScheme;
    final when = e.originServerTs.localizedTimeShort(context);
    switch (widget.kind) {
      case _Kind.voice:
        return GestureDetector(
          onLongPress: () => _jump(e),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_who(e)} · $when',
                  style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                ),
                AudioPlayerWidget(
                  e,
                  color: cs.onSurface,
                  linkColor: cs.primary,
                  fontSize: 15,
                ),
              ],
            ),
          ),
        );
      default:
        final name =
            e.content.tryGet<String>('filename') ??
            e.content.tryGet<String>('body') ??
            'File';
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: VibePalette.accent.withAlpha(0x33),
            child: Icon(
              e.messageType == MessageTypes.Audio
                  ? Icons.music_note_outlined
                  : Icons.insert_drive_file_outlined,
              color: const Color(0xFF8C96F6),
            ),
          ),
          title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            '${e.sizeString ?? ''}${e.sizeString == null ? '' : ' · '}${_who(e)} · $when',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () => e.saveFile(context),
          onLongPress: () => _jump(e),
        );
    }
  }

  Widget _idRow(String id) {
    final cs = Theme.of(context).colorScheme;
    final e = _byId[id];
    if (e == null) {
      return ListTile(
        title: Text(
          _byId.containsKey(id) ? 'Message not available' : '…',
          style: TextStyle(color: cs.onSurfaceVariant),
        ),
      );
    }
    return ListTile(
      leading: Avatar(
        mxContent: e.senderFromMemoryOrFallback.avatarUrl,
        name: _who(e),
        size: 40,
        client: widget.room.client,
      ),
      title: Text(
        '${_who(e)} · ${e.originServerTs.localizedTimeShort(context)}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
      subtitle: Text(
        e.calcLocalizedBodyFallback(
          MatrixLocals(L10n.of(context)),
          hideReply: true,
        ),
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: widget.kind == _Kind.starred
          ? IconButton(
              tooltip: 'Unstar',
              icon: const Icon(Icons.star, color: Color(0xFFFAA61A)),
              onPressed: () async {
                await VibeStarred.toggle(widget.room.id, id);
                if (mounted) setState(() => _ids = List.of(_ids)..remove(id));
              },
            )
          : null,
      // Starred messages are messages: opening one shows it in the chat
      // (tap or long-press).
      onTap: () => _jump(e),
      onLongPress: () => _jump(e),
    );
  }
}

