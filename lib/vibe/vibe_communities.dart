// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/vibe/call/vibe_call.dart';
import 'package:fluffychat/vibe/call/vibe_call_buttons.dart';
import 'package:fluffychat/vibe/call/vibe_call_members.dart';
import 'package:fluffychat/vibe/vibe_dm_detail.dart';
import 'package:fluffychat/vibe/vibe_groups.dart';
import 'package:fluffychat/vibe/vibe_haptics.dart';
import 'package:fluffychat/vibe/vibe_motion.dart';
import 'package:fluffychat/vibe/vibe_settings_style.dart' hide VibeGroups;
import 'package:fluffychat/widgets/avatar.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/matrix.dart' as sdk show Visibility;

/// Communities are Matrix spaces: one place that holds several group chats
/// ("channels"), like a Discord server. They sit in the rail under your
/// groups; tapping one opens its channels in the middle pane.
abstract class VibeCommunities {
  /// Ask Home to open a community (after creating or joining one).
  static final ValueNotifier<String?> select = ValueNotifier(null);

  static List<Room> joined(Client client) => client.rooms
      .where(
        (r) =>
            r.isSpace &&
            (r.membership == Membership.join ||
                r.membership == Membership.invite),
      )
      .toList();

  static Set<String> childIds(Room space) {
    if (!space.isSpace) return const {};
    return {
      for (final c in space.spaceChildren)
        if (c.roomId != null) c.roomId!,
    };
  }

  /// Rooms that live inside one of your communities: shown there instead of
  /// as their own rail icons.
  static Set<String> channelIds(Client client) => {
    for (final s in client.rooms)
      if (s.isSpace && s.membership == Membership.join) ...childIds(s),
  };

  /// Unread messages across a community's channels (for the rail badge).
  static int unread(Room space) {
    var n = 0;
    for (final id in childIds(space)) {
      final r = space.client.getRoomById(id);
      if (r != null && r.membership == Membership.join) {
        n += r.notificationCount;
      }
    }
    return n;
  }

  static Future<void> _waitFor(Client client, String id) async {
    if (client.getRoomById(id) != null) return;
    try {
      await client
          .waitForRoomInSync(id, join: true)
          .timeout(const Duration(seconds: 20));
    } on TimeoutException catch (_) {}
  }

  static Future<String> create(
    Client client, {
    required String name,
    required bool isPublic,
    String? alias,
    List<String> invite = const [],
    List<StateEvent> initialState = const [],
  }) async {
    final id = await client.createRoom(
      name: name,
      creationContent: {'type': RoomCreationTypes.mSpace},
      preset: isPublic
          ? CreateRoomPreset.publicChat
          : CreateRoomPreset.privateChat,
      visibility: isPublic ? sdk.Visibility.public : sdk.Visibility.private,
      roomAliasName: alias,
      invite: invite,
      initialState: initialState,
      // only admins post into the space room itself
      powerLevelContentOverride: {'events_default': 100},
    );
    await _waitFor(client, id);
    final space = client.getRoomById(id);
    if (space != null) {
      try {
        await createChannel(client, space, 'general', invite: invite);
      } catch (e, s) {
        Logs().w('Vibe: could not create #general', e, s);
      }
    }
    return id;
  }

  /// A new channel. In a private community it's end-to-end encrypted and
  /// anyone in the community can join it; in a public one anyone can.
  static Future<String> createChannel(
    Client client,
    Room space,
    String name, {
    List<String> invite = const [],
    bool voice = false,
  }) async {
    final isPublic = space.joinRules == JoinRules.public;
    final id = await client.createRoom(
      name: name,
      // voice channels are call rooms, the same kind Sable and Element use
      creationContent: voice ? {'type': VibeCallMembers.voiceRoomType} : null,
      powerLevelContentOverride: VibeCallPower.createOverride,
      preset: isPublic
          ? CreateRoomPreset.publicChat
          : CreateRoomPreset.privateChat,
      invite: invite.isEmpty ? null : invite,
      initialState: [
        if (!isPublic)
          StateEvent(
            type: EventTypes.RoomJoinRules,
            content: {
              'join_rule': 'restricted',
              'allow': [
                {'type': 'm.room_membership', 'room_id': space.id},
              ],
            },
          ),
        if (!isPublic)
          StateEvent(
            type: EventTypes.Encryption,
            content: {'algorithm': 'm.megolm.v1.aes-sha2'},
          ),
      ],
    );
    await space.setSpaceChild(id);
    return id;
  }

  static Future<void> newChannel(BuildContext context, Room space) async {
    final ctrl = TextEditingController();
    var voice = false;
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('New channel'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: ChoiceChip(
                      avatar: const Icon(Icons.tag, size: 18),
                      label: const Text('Text'),
                      selected: !voice,
                      showCheckmark: false,
                      onSelected: (_) => setLocal(() => voice = false),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ChoiceChip(
                      avatar: const Icon(Icons.volume_up, size: 18),
                      label: const Text('Voice'),
                      selected: voice,
                      showCheckmark: false,
                      onSelected: (_) => setLocal(() => voice = true),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                autofocus: true,
                decoration: InputDecoration(
                  prefixText: voice ? '🔊 ' : '# ',
                  hintText: voice ? 'voice-chat' : 'channel-name',
                ),
                onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
    ctrl.dispose();
    if (name == null || name.isEmpty || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await createChannel(space.client, space, name, voice: voice);
      VibeHaptics.light();
      messenger.showSnackBar(
        SnackBar(content: Text(voice ? 'Created voice channel $name' : 'Created #$name')),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  /// Put one of your existing groups into the community.
  static Future<void> addExisting(BuildContext context, Room space) async {
    final inside = childIds(space);
    final groups = space.client.rooms
        .where(
          (r) =>
              VibeGroups.isGroup(r) &&
              r.membership == Membership.join &&
              !inside.contains(r.id),
        )
        .toList();
    final t1 = VibeSettingsStyle.text(context);
    final t2 = VibeSettingsStyle.text2(context);
    final room = await showVibeSheet<Room>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: VibeSettingsStyle.page(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(ctx).height * 0.7,
          ),
          child: groups.isEmpty
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                  child: Text(
                    'You have no other groups to add.',
                    style: TextStyle(color: t2),
                  ),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: groups.length,
                  itemBuilder: (ctx, i) {
                    final g = groups[i];
                    return ListTile(
                      leading: Avatar(
                        mxContent: g.avatar,
                        name: VibeGroups.nameOf(ctx, g),
                        size: 40,
                        client: g.client,
                      ),
                      title: Text(
                        VibeGroups.nameOf(ctx, g),
                        style: TextStyle(color: t1),
                      ),
                      subtitle: Text(
                        '${VibeGroups.memberCount(g)} members',
                        style: TextStyle(color: t2),
                      ),
                      onTap: () => Navigator.pop(ctx, g),
                    );
                  },
                ),
        ),
      ),
    );
    if (room == null || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await space.setSpaceChild(room.id);
      messenger.showSnackBar(
        SnackBar(content: Text('Added ${room.getLocalizedDisplayname()}')),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }
}

/// One channel of a community, from the server's list or your own rooms.
class _Channel {
  final String id;
  final String name;
  final String? topic;
  final int members;
  final List<String> via;
  final bool voice;
  const _Channel({
    required this.id,
    required this.name,
    this.topic,
    this.members = 0,
    this.via = const [],
    this.voice = false,
  });
}

/// The middle pane for a community: its channels, then its settings.
class VibeCommunityPane extends StatefulWidget {
  final Room space;
  final VoidCallback onBack;
  final void Function(Room room) onOpenRoom;
  const VibeCommunityPane({
    required this.space,
    required this.onBack,
    required this.onOpenRoom,
    super.key,
  });

  @override
  State<VibeCommunityPane> createState() => _VibeCommunityPaneState();
}

class _VibeCommunityPaneState extends State<VibeCommunityPane> {
  List<_Channel>? _remote;
  String? _joining;
  StreamSubscription? _sub;

  Room get space => widget.space;

  @override
  void initState() {
    super.initState();
    _load();
    // channels added or removed elsewhere
    _sub = space.client.onSync.stream
        .where((s) {
          final u = s.rooms?.join?[space.id];
          if (u == null) return false;
          bool child(e) => e.type == EventTypes.SpaceChild;
          return (u.state?.any(child) ?? false) ||
              (u.timeline?.events?.any(child) ?? false);
        })
        .listen((_) => _load());
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (space.membership != Membership.join) return;
    try {
      final h = await space.client.getSpaceHierarchy(
        space.id,
        maxDepth: 1,
        limit: 100,
      );
      final via = {
        for (final c in space.spaceChildren)
          if (c.roomId != null) c.roomId!: c.via,
      };
      final list = [
        for (final r in h.rooms)
          if (r.roomId != space.id && r.roomType != RoomCreationTypes.mSpace)
            _Channel(
              id: r.roomId,
              name: r.name ?? r.canonicalAlias ?? 'channel',
              topic: r.topic,
              members: r.numJoinedMembers,
              via: via[r.roomId] ?? const [],
              voice: r.roomType == VibeCallMembers.voiceRoomType,
            ),
      ];
      if (mounted) setState(() => _remote = list);
    } catch (e) {
      Logs().w('Vibe: space hierarchy failed', e);
      if (mounted) setState(() => _remote ??= const []);
    }
  }

  List<_Channel> _channels(BuildContext context) {
    final out = <_Channel>[...?_remote];
    final known = out.map((c) => c.id).toSet();
    // channels you're already in that the server didn't list (yet)
    for (final c in space.spaceChildren) {
      final id = c.roomId;
      if (id == null || known.contains(id)) continue;
      final r = space.client.getRoomById(id);
      if (r == null || r.isSpace) continue;
      out.add(
        _Channel(
          id: id,
          name: VibeGroups.nameOf(context, r),
          members: VibeGroups.memberCount(r),
          via: c.via,
          voice: VibeCallMembers.isVoiceRoom(r),
        ),
      );
    }
    return out;
  }

  Future<void> _open(_Channel c) async {
    final client = space.client;
    final local = client.getRoomById(c.id);
    if (local != null && local.membership == Membership.join) {
      if (c.voice) {
        await VibeCall.join(context, local);
      } else {
        widget.onOpenRoom(local);
      }
      return;
    }
    setState(() => _joining = c.id);
    try {
      await client.joinRoom(c.id, via: c.via.isEmpty ? null : c.via);
      await VibeCommunities._waitFor(client, c.id);
      VibeHaptics.light();
      final r = client.getRoomById(c.id);
      if (r != null && mounted) {
        if (c.voice) {
          await VibeCall.join(context, r);
        } else {
          widget.onOpenRoom(r);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _joining = null);
    }
  }

  Future<void> _channelMenu(_Channel c) async {
    if (!space.canChangeStateEvent(EventTypes.SpaceChild)) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove #${c.name} from this community?'),
        content: const Text(
          'The chat itself stays; it just won\'t be listed here any more.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await space.removeSpaceChild(c.id);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _accept(bool join) async {
    try {
      if (join) {
        await space.join();
        VibeHaptics.medium();
        await _load();
      } else {
        await space.leave();
        widget.onBack();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _leave() async {
    final name = VibeGroups.nameOf(context, space);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Leave $name?'),
        content: const Text(
          'You\'ll stay in the channels you joined; you can leave them '
          'one by one.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Leave',
              style: TextStyle(color: Theme.of(ctx).colorScheme.error),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await space.leave();
      widget.onBack();
      if (mounted) context.go('/rooms');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final name = space.getLocalizedDisplayname(MatrixLocals(L10n.of(context)));
    final invited = space.membership == Membership.invite;
    final isPublic = VibeGroups.isPublic(space);
    final canAdd = space.canChangeStateEvent(EventTypes.SpaceChild);
    final channels = _channels(context);
    final topic = space.topic;

    return Material(
      color: cs.surface,
      child: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 120),
          children: [
            GestureDetector(
              onTap: widget.onBack,
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
                  onLongPress: space.canChangeStateEvent(EventTypes.RoomAvatar)
                      ? () => VibeGroupEdit.changePicture(context, space)
                      : null,
                  child: Avatar(
                    mxContent: space.avatar,
                    name: name,
                    size: 62,
                    client: space.client,
                    borderRadius: BorderRadius.circular(18),
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
              child: Text(
                '${VibeGroups.memberCount(space)} members · '
                '${isPublic ? 'Public community' : 'Private community'}',
                style: TextStyle(fontSize: 13.5, color: cs.onSurfaceVariant),
              ),
            ),
            if (topic.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 6, top: 6),
                child: Text(
                  topic,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13.5, color: cs.onSurfaceVariant),
                ),
              ),
            const SizedBox(height: 8),
            if (invited)
              _InviteBanner(name: name, onAnswer: _accept)
            else ...[
              VibePaneHeader(
                'CHANNELS',
                onAdd: canAdd ? () => VibeCommunities.newChannel(context, space) : null,
              ),
              if (_remote == null && channels.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator.adaptive()),
                )
              else if (channels.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(6, 8, 6, 8),
                  child: Text(
                    canAdd
                        ? 'No channels yet. Tap + to add one.'
                        : 'No channels yet.',
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
                ),
              for (final c in channels) _row(context, c),
              if (canAdd)
                VibeHashRow(
                  label: 'add-existing-group',
                  onTap: () => VibeCommunities.addExisting(context, space),
                ),
              const VibePaneHeader('COMMUNITY'),
              VibeHashRow(
                label: 'members',
                subtitle: '${VibeGroups.memberCount(space)} people',
                onTap: () => VibeGroups.showMembers(context, space),
              ),
              if (space.canInvite)
                VibeHashRow(
                  label: 'invite-people',
                  onTap: () => VibeGroups.showInvite(context, space),
                ),
              if (space.canChangeStateEvent(EventTypes.RoomAvatar))
                VibeHashRow(
                  label: 'community-picture',
                  onTap: () => VibeGroupEdit.changePicture(context, space),
                ),
              if (space.canChangeStateEvent(EventTypes.RoomName))
                VibeHashRow(
                  label: 'rename-community',
                  onTap: () => VibeGroups.rename(context, space),
                ),
              VibeHashRow(
                label: 'privacy',
                subtitle: isPublic
                    ? 'Public · anyone can join'
                    : 'Private · invite only',
                subtitleIcon: isPublic ? Icons.public_rounded : Icons.lock_rounded,
                onTap: () => VibeGroupEdit.privacy(context, space),
              ),
              VibeHashRow(label: 'leave-community', onTap: _leave),
            ],
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext context, _Channel c) {
    final cs = Theme.of(context).colorScheme;
    final found = space.client.getRoomById(c.id);
    final local = found != null && found.membership == Membership.join
        ? found
        : null;
    final unread = local?.notificationCount ?? 0;
    final label = VibeGroups.slug(
      local != null ? VibeGroups.nameOf(context, local) : c.name,
    );
    String? subtitle;
    if (local != null) {
      subtitle = local.lastEvent?.calcLocalizedBodyFallback(
        MatrixLocals(L10n.of(context)),
        hideReply: true,
        withSenderNamePrefix: true,
      );
    } else {
      subtitle = [
        if (c.members > 0) '${c.members} members',
        if (c.topic != null && c.topic!.isNotEmpty) c.topic!,
      ].join(' · ');
      if (subtitle.isEmpty) subtitle = null;
    }
    Widget? trailing;
    if (_joining == c.id) {
      trailing = const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    } else if (local == null) {
      trailing = Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          'Join',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: cs.onSurface,
          ),
        ),
      );
    } else if (unread > 0) {
      trailing = Container(
        constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
        padding: const EdgeInsets.symmetric(horizontal: 6),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: cs.error,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          '$unread',
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.bold,
            color: cs.onError,
          ),
        ),
      );
    }
    if (c.voice && local != null) {
      // Voice channel you're in: show who's talking in it, Discord style.
      return VibeCallWatch(
        key: ValueKey(c.id),
        room: local,
        builder: (context, inCall) {
          final mine = VibeCall.instance.isIn(local);
          final live = mine || inCall.isNotEmpty;
          return VibeHashRow(
            label: label.isEmpty ? 'voice' : label,
            icon: Icons.volume_up,
            iconColor: live ? const Color(0xFF23A55A) : null,
            bold: live,
            subtitle: mine
                ? 'You\'re here · tap to open'
                : inCall.isNotEmpty
                ? '${inCall.length} talking · tap to join'
                : 'Tap to join voice',
            trailing: _joining == c.id
                ? trailing
                : inCall.isEmpty
                ? null
                : VibeCallFaces(room: local, userIds: inCall),
            onTap: () => _open(c),
            onLongPress: () => _channelMenu(c),
          );
        },
      );
    }
    return VibeHashRow(
      key: ValueKey(c.id),
      label: label.isEmpty ? 'channel' : label,
      icon: c.voice ? Icons.volume_up : null,
      subtitle: c.voice && local == null
          ? (c.members > 0 ? '${c.members} members · voice' : 'Voice channel')
          : subtitle,
      bold: local?.isUnread ?? false,
      trailing: trailing,
      onTap: () => _open(c),
      onLongPress: () => _channelMenu(c),
    );
  }
}

class _InviteBanner extends StatelessWidget {
  final String name;
  final Future<void> Function(bool join) onAnswer;
  const _InviteBanner({required this.name, required this.onAnswer});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Material(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'You\'re invited to $name',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => onAnswer(false),
                      child: const Text('Decline'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF5865F2),
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () => onAnswer(true),
                      child: const Text('Join'),
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
